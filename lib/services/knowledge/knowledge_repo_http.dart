/// KnowledgeRepository 的 HTTP 装饰器（F26 chunk 8，F23 A5/B13）。
///
/// 真实知识点走既有后端端点（camelCase，逐行显式归一成 §4.8.2 snake_case
/// 契约后再走 `KnowledgePoint.fromJson`，与 HttpSearchService 同一映射）：
/// - `GET /api/v1/knowledge/points?page=&page_size=100` 全量分页拉取；
/// - `GET /api/v1/knowledge/points/{id}` 详情；
/// - `GET /api/v1/bank/questions/{id}` 反查题目的 knowledgePointId。
///
/// 章/节是展示分组，由 `code`（章.节）前缀聚合（§4.8.3）：模块 → 章，
/// topic → 节。只有 content_md 非空的正式 KP 进浏览结构——占位 KP 没有
/// 正文，不拿空内容冒充真实知识点。按题目反查同理：KP 无正文返回 []。
///
/// 未登录 / 离线 / 401 / 404 / 500 / 非 JSON 一律回落注入的 [fallback]
/// （生产为 Mock），不抛给 UI；Bearer 附加与 401 刷新一次重放由注入的
/// AuthHttpClient 统一承担。KP 内容全部来自后端 JSON，绝不进 app bundle。
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config.dart';
import '../../models/knowledge_point.dart';
import 'knowledge_repo.dart';

class HttpKnowledgeRepository implements KnowledgeRepository {
  HttpKnowledgeRepository({
    required this.fallback,
    http.Client? client,
    String? baseUrl,
    this.tokenProvider,
  }) : _client = client ?? http.Client(),
       _baseUrl = baseUrl ?? AppConfig.baseUrl;

  /// 任一请求失败 / 未登录时的兜底（生产为 MockKnowledgeRepository）。
  final KnowledgeRepository fallback;

  final http.Client _client;
  final String _baseUrl;

  /// 返回 access token 的回调；未登录返回 null → 直接走兜底，不发请求。
  final String? Function()? tokenProvider;

  static const Duration _timeout = Duration(seconds: 10);
  static const int _pageSize = 100;
  static const int _maxPages = 20;

  /// 正式 KP 缓存（进知识库页拉一次；本批数据量小，会话内不失效）。
  List<KnowledgePoint>? _cache;

  /// 章标题只是展示分组名（模块 → 章），不是后端数据。
  static const Map<String, String> _moduleTitles = <String, String>{
    'VLAN': 'VLAN 技术',
    'OSPF': 'OSPF 路由协议',
    'ACL': 'ACL 访问控制',
    'NAT': 'NAT 地址转换',
    'SUBNET': '子网划分',
    '子网': '子网划分',
    '基础知识': '网络基础知识',
    'H3CNE': 'H3CNE 综合',
  };

  @override
  Future<List<Chapter>> getChapters() async {
    final token = tokenProvider?.call();
    if (token == null || token.isEmpty) return fallback.getChapters();
    final points = await _realPoints(token);
    if (points == null) return fallback.getChapters();

    // 模块 + code 章前缀 → 章；后端已按 module, order_no, id 排序，
    // 章按首次出现顺序编号。
    final keys = <String>[];
    final byKey = <String, (String, int)>{};
    for (final p in points) {
      final chapter = _codePart(p.code, 0);
      final key = '${p.module}|$chapter';
      if (!byKey.containsKey(key)) {
        keys.add(key);
        byKey[key] = (p.module, chapter);
      }
    }
    return <Chapter>[
      for (var i = 0; i < keys.length; i++)
        Chapter(
          id: _chapterId(byKey[keys[i]]!.$1, byKey[keys[i]]!.$2),
          module: byKey[keys[i]]!.$1,
          title: _moduleTitles[byKey[keys[i]]!.$1] ?? byKey[keys[i]]!.$1,
          order: i + 1,
        ),
    ];
  }

  @override
  Future<List<Section>> getSections(String chapterId) async {
    final token = tokenProvider?.call();
    if (token == null || token.isEmpty) return fallback.getSections(chapterId);
    final split = _splitChapterId(chapterId);
    if (split == null) return fallback.getSections(chapterId);
    final points = await _realPoints(token);
    if (points == null) return fallback.getSections(chapterId);

    final module = split.$1;
    final chapter = split.$2;
    final sectionNums = <int>[];
    final topics = <int, String>{};
    for (final p in points) {
      if (p.module != module || _codePart(p.code, 0) != chapter) continue;
      final section = _codePart(p.code, 1);
      if (!sectionNums.contains(section)) {
        sectionNums.add(section);
        topics[section] = p.topic.isNotEmpty ? p.topic : p.code;
      }
    }
    sectionNums.sort();
    return <Section>[
      for (var i = 0; i < sectionNums.length; i++)
        Section(
          id: '$chapterId-${sectionNums[i].toString().padLeft(2, '0')}',
          chapterId: chapterId,
          title: topics[sectionNums[i]]!,
          order: i + 1,
        ),
    ];
  }

  @override
  Future<List<KnowledgePoint>> getPointsBySection(String sectionId) async {
    final token = tokenProvider?.call();
    if (token == null || token.isEmpty) {
      return fallback.getPointsBySection(sectionId);
    }
    final split = _splitSectionId(sectionId);
    if (split == null) return fallback.getPointsBySection(sectionId);
    final points = await _realPoints(token);
    if (points == null) return fallback.getPointsBySection(sectionId);

    final module = split.$1;
    final chapter = split.$2;
    final section = split.$3;
    final rows = points
        .where(
          (p) =>
              p.module == module &&
              _codePart(p.code, 0) == chapter &&
              _codePart(p.code, 1) == section,
        )
        .toList();
    // 模型没有 order_no 字段（§4.8.2 契约）；id 按展示顺序分配，按 id 排序。
    rows.sort((a, b) => a.id.compareTo(b.id));
    return rows;
  }

  @override
  Future<KnowledgePoint?> getPointDetail(String id) async {
    final token = tokenProvider?.call();
    if (token == null || token.isEmpty) return fallback.getPointDetail(id);
    final json = await _get(
      '/api/v1/knowledge/points/${Uri.encodeComponent(id)}',
      token,
    );
    if (json == null) return fallback.getPointDetail(id);
    final point = _pointFromBackend(json);
    if (point == null) return fallback.getPointDetail(id);
    return point;
  }

  @override
  Future<List<KnowledgePoint>> getPointsByQuestion(String questionId) async {
    final token = tokenProvider?.call();
    if (token == null || token.isEmpty) {
      return fallback.getPointsByQuestion(questionId);
    }
    // 先反查题目的 knowledgePointId（bank 端点 camelCase 原样下发）。
    final question = await _get(
      '/api/v1/bank/questions/${Uri.encodeComponent(questionId)}',
      token,
    );
    if (question == null) return fallback.getPointsByQuestion(questionId);
    final kpId = question['knowledgePointId'];
    if (kpId is! String || kpId.isEmpty) return <KnowledgePoint>[];
    final json = await _get(
      '/api/v1/knowledge/points/${Uri.encodeComponent(kpId)}',
      token,
    );
    if (json == null) return fallback.getPointsByQuestion(questionId);
    final point = _pointFromBackend(json);
    // 只有正式内容才上 chips：占位 KP（contentMd null/空）诚实返回 []。
    if (point == null || point.content_md.trim().isEmpty) {
      return <KnowledgePoint>[];
    }
    return <KnowledgePoint>[point];
  }

  @override
  Future<KnowledgePoint?> getDailyPoint() async {
    final token = tokenProvider?.call();
    if (token == null || token.isEmpty) return fallback.getDailyPoint();
    final points = await _realPoints(token);
    if (points == null) return fallback.getDailyPoint();
    return points.isEmpty ? null : points.first;
  }

  /// 全量分页拉取正式 KP（content_md 非空）；失败返回 null 由调用方回落。
  /// 后端诚实返回空列表就是空结果，不拿样例冒充。
  Future<List<KnowledgePoint>?> _realPoints(String token) async {
    final cached = _cache;
    if (cached != null) return cached;
    final points = <KnowledgePoint>[];
    var page = 1;
    while (page <= _maxPages) {
      final json = await _get(
        '/api/v1/knowledge/points?page=$page&page_size=$_pageSize',
        token,
      );
      if (json == null) return null;
      final items = json['points'];
      if (items is! List) return null;
      for (final item in items) {
        if (item is! Map<String, dynamic>) continue;
        final point = _pointFromBackend(item);
        if (point != null && point.content_md.trim().isNotEmpty) {
          points.add(point);
        }
      }
      final total = (json['total'] as num?)?.toInt() ?? 0;
      if (items.isEmpty || page * _pageSize >= total) break;
      page++;
    }
    _cache = points;
    return points;
  }

  /// 请求：404 / 401 / 网络失败 / 非 JSON 一律返回 null（未就绪），
  /// 由调用方回落兜底，不抛给 UI。
  Future<Map<String, dynamic>?> _get(String path, String token) async {
    try {
      final response = await _client
          .get(
            Uri.parse('$_baseUrl$path'),
            headers: <String, String>{
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(_timeout);
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  /// 后端 `_point()` camelCase → §4.8.2 snake_case 契约后走既有解析器。
  /// contentMd 占位 KP 为 null → 空串（诚实为空，不编正文）；commands
  /// 为 null 时给空数组（解析器不接受 null）。缺 id / title 的脏行跳过。
  KnowledgePoint? _pointFromBackend(Map<String, dynamic> json) {
    final id = json['id'];
    final title = json['title'];
    if (id is! String || title is! String) return null;
    try {
      return KnowledgePoint.fromJson(<String, dynamic>{
        'id': id,
        'module': json['module'] as String? ?? '',
        'topic': json['topic'] as String? ?? '',
        'code': json['code'] as String? ?? '',
        'title': title,
        'summary': json['summary'] as String? ?? '',
        'content_md': json['contentMd'] as String? ?? '',
        'key_points': json['keyPoints'],
        'commands': json['commands'] ?? const <dynamic>[],
        'pitfalls': json['pitfalls'],
        'tags': json['tags'],
        'status': json['status'],
        'row_version': (json['rowVersion'] as num?)?.toInt() ?? 0,
      });
    } catch (_) {
      return null;
    }
  }

  /// code 的章/节数字部分；解析失败按 0 处理（脏 code 归入第 0 章）。
  static int _codePart(String code, int index) {
    final parts = code.split('.');
    if (index >= parts.length) return 0;
    return int.tryParse(parts[index]) ?? 0;
  }

  static String _chapterId(String module, int chapter) {
    return '$module-${chapter.toString().padLeft(2, '0')}';
  }

  /// `VLAN-01` → (VLAN, 1)；模块名不含 `-`，按最后一个 `-` 切。
  static (String, int)? _splitChapterId(String chapterId) {
    final idx = chapterId.lastIndexOf('-');
    if (idx <= 0 || idx == chapterId.length - 1) return null;
    final module = chapterId.substring(0, idx);
    final chapter = int.tryParse(chapterId.substring(idx + 1));
    if (chapter == null) return null;
    return (module, chapter);
  }

  /// `VLAN-01-03` → (VLAN, 1, 3)。
  static (String, int, int)? _splitSectionId(String sectionId) {
    final parts = sectionId.split('-');
    if (parts.length < 3) return null;
    final module = parts.sublist(0, parts.length - 2).join('-');
    final chapter = int.tryParse(parts[parts.length - 2]);
    final section = int.tryParse(parts[parts.length - 1]);
    if (module.isEmpty || chapter == null || section == null) return null;
    return (module, chapter, section);
  }
}
