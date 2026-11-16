/// 题库 / 套卷概览的服务端数据源（F19 cache-first）。
///
/// 只做「拉取 + 映射」，不碰缓存与 UI：
/// - [HttpBankQuestionBankSource]：`GET /api/v1/bank/questions?page=N[&module=X]`
///   分页拉取整套题，映射成客户端 `Question` 契约后由
///   [CachedPracticeService] 写入 SQLite 本地题库。
/// - [HttpBankSetOverviewSource]：`GET /api/v1/bank/sets/{setId}/overview`
///   （F26 已接真实端点；失败 / 未登录按「接口未就绪」返回 null，不编数字）。
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config.dart';
import '../../core/modules.dart';
import '../../models/question.dart';
import '../../models/stats.dart';

/// 客户端题库分页拉取（F17 每日一练同源接口，公开、无需鉴权）。
abstract class BankQuestionBankSource {
  Future<List<Question>> fetchQuestions({
    required String setId,
    String? module,
  });
}

/// 套卷概览数据源；接口未就绪返回 null。
abstract class BankSetOverviewSource {
  Future<BankSetOverview?> fetchOverview(String setId);
}

class BankQuestionSourceException implements Exception {
  const BankQuestionSourceException(this.message);

  final String message;

  @override
  String toString() => 'BankQuestionSourceException: $message';
}

/// `/bank/questions` 的 HTTP 实现：pageSize 由后端固定 20，按 total 翻页。
class HttpBankQuestionBankSource implements BankQuestionBankSource {
  HttpBankQuestionBankSource({
    http.Client? client,
    String? baseUrl,
    this.maxPages = 40,
  }) : _client = client ?? http.Client(),
       _baseUrl = baseUrl ?? AppConfig.baseUrl;

  final http.Client _client;
  final String _baseUrl;

  /// 单次同步最多翻多少页（40 × 20 = 800 题，覆盖当前全库 650 题）。
  final int maxPages;

  static const Duration _timeout = Duration(seconds: 10);

  @override
  Future<List<Question>> fetchQuestions({
    required String setId,
    String? module,
  }) async {
    final filter = module ?? (kModuleOrder.contains(setId) ? setId : null);
    final questions = <Question>[];
    var page = 1;
    var totalPages = 1;
    while (page <= totalPages && page <= maxPages) {
      final data = await _fetchPage(page, filter);
      totalPages = data.pageSize <= 0 ? 1 : (data.total / data.pageSize).ceil();
      for (final item in data.questions) {
        if (item is! Map<String, dynamic>) continue;
        final mapped = mapBankQuestionJson(item);
        if (mapped != null) questions.add(mapped);
      }
      if (data.questions.isEmpty) break;
      page++;
    }
    return questions;
  }

  Future<({int total, int pageSize, List<dynamic> questions})> _fetchPage(
    int page,
    String? module,
  ) async {
    final query = <String>[
      'page=$page',
      if (module != null) 'module=${Uri.encodeQueryComponent(module)}',
    ].join('&');
    final uri = Uri.parse('$_baseUrl/api/v1/bank/questions?$query');
    final http.Response response;
    try {
      response = await _client.get(uri).timeout(_timeout);
    } catch (e) {
      throw BankQuestionSourceException('题库拉取失败：$e');
    }
    if (response.statusCode != 200) {
      throw BankQuestionSourceException('题库拉取失败（HTTP ${response.statusCode}）');
    }
    final dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (e) {
      throw BankQuestionSourceException('题库解析失败：$e');
    }
    if (decoded is! Map<String, dynamic> || decoded['questions'] is! List) {
      throw const BankQuestionSourceException('题库格式错误');
    }
    return (
      total: (decoded['total'] as num?)?.toInt() ?? 0,
      pageSize: (decoded['pageSize'] as num?)?.toInt() ?? 0,
      questions: decoded['questions'] as List<dynamic>,
    );
  }
}

/// 后端题 JSON → 客户端 [Question]（题库列表与 /practice/next 共用）。
///
/// `options` 为纯字符串时映射成 A/B/C…，也接受已带 `{key, text}` 的选项；
/// `answer` 既接受 0 基下标数组，也接受字母数组（/practice/next 直接返回
/// answer+explanation）。考试卷面不含答案，[requireAnswer] 为 false 时
/// 允许空 answer。缺少 id / stem / options 的脏数据返回 null，不编题。
Question? mapBankQuestionJson(
  Map<String, dynamic> json, {
  bool requireAnswer = true,
}) {
  final id = json['id'];
  final stem = json['stem'];
  final optionsRaw = json['options'];
  if (id is! String || stem is! String || optionsRaw is! List) return null;
  final options = <QuestionOption>[];
  for (var i = 0; i < optionsRaw.length; i++) {
    final raw = optionsRaw[i];
    if (raw is String) {
      options.add(QuestionOption(key: _letter(i), text: raw));
    } else if (raw is Map<String, dynamic> &&
        raw['key'] is String &&
        raw['text'] is String) {
      options.add(
        QuestionOption(key: raw['key'] as String, text: raw['text'] as String),
      );
    } else {
      return null;
    }
  }
  if (options.isEmpty) return null;
  final answer = <String>[];
  for (final raw in (json['answer'] as List<dynamic>? ?? const [])) {
    if (raw is num) {
      final index = raw.toInt();
      if (index < 0 || index >= options.length) return null;
      answer.add(_letter(index));
    } else if (raw is String) {
      final key = raw.trim().toUpperCase();
      if (!options.any((o) => o.key == key)) return null;
      answer.add(key);
    } else {
      return null;
    }
  }
  if (requireAnswer && answer.isEmpty) return null;
  final module = json['module'] as String? ?? '';
  return Question(
    id: id,
    module: module,
    type: json['type'] as String? ?? 'single',
    stem: stem,
    options: options,
    answer: answer,
    explanation: json['explanation'] as String? ?? '',
    knowledge_point_id: json['knowledgePointId'] as String? ?? '',
    related_ids: (json['relatedKnowledgeIds'] as List<dynamic>?)
        ?.cast<String>(),
    difficulty: (json['difficulty'] as num?)?.toInt() ?? 1,
    set_no: 0,
    row_version: (json['rowVersion'] as num?)?.toInt() ?? 0,
  );
}

String _letter(int index) => String.fromCharCode('A'.codeUnitAt(0) + index);

/// 客户端选项 key（`["A", "C"]`）→ 服务端 0 基下标数组（`[0, 2]`）。
///
/// S11 `POST /practice/submit` 与 `POST /exam/{id}/answers|submit` 的
/// `answer` 契约都是下标数组；无法识别的 key 直接丢弃，不猜下标。
List<int> bankAnswerIndices(List<String> keys) {
  final indices = <int>[];
  for (final key in keys) {
    final normalized = key.trim().toUpperCase();
    if (normalized.length != 1) continue;
    final index = normalized.codeUnitAt(0) - 'A'.codeUnitAt(0);
    if (index < 0 || index > 25) continue;
    indices.add(index);
  }
  return indices;
}

/// 服务端答案数组 → 客户端选项 key 列表。
///
/// 既接受 0 基下标数组（S11 判分返回的 `answer`），也接受字母数组（旧
/// 本地 JSON）。形状不认识时返回 null，绝不编答案。
List<String>? bankAnswerKeys(Object? raw) {
  if (raw is! List) return null;
  final keys = <String>[];
  for (final item in raw) {
    if (item is num) {
      final index = item.toInt();
      if (index < 0 || index > 25) return null;
      keys.add(_letter(index));
    } else if (item is String) {
      final key = item.trim().toUpperCase();
      if (key.isEmpty) return null;
      keys.add(key);
    } else {
      return null;
    }
  }
  return keys;
}

/// `/bank/sets/{setId}/overview` 的 HTTP 实现（F26 chunk 6 接真实端点）。
///
/// Bearer 附加与 401 刷新一次重放由注入的 [AuthHttpClient] 统一承担；
/// 任何失败（404 未知套卷 / 401 未登录 / 500 / 断网 / 非 JSON）一律返回
/// null，前置页保留“完成情况待接口”，不抛给 UI，也不编数字。
class HttpBankSetOverviewSource implements BankSetOverviewSource {
  HttpBankSetOverviewSource({
    http.Client? client,
    String? baseUrl,
    this.tokenProvider,
  }) : _client = client ?? http.Client(),
       _baseUrl = baseUrl ?? AppConfig.baseUrl;

  final http.Client _client;
  final String _baseUrl;

  /// 返回 access token 的回调；未登录返回 null（不带 Authorization 头）。
  final String? Function()? tokenProvider;

  static const Duration _timeout = Duration(seconds: 10);

  @override
  Future<BankSetOverview?> fetchOverview(String setId) async {
    final uri = Uri.parse(
      '$_baseUrl/api/v1/bank/sets/${Uri.encodeComponent(setId)}/overview',
    );
    final token = tokenProvider?.call();
    try {
      final response = await _client
          .get(
            uri,
            headers: <String, String>{
              if (token != null && token.isNotEmpty)
                'Authorization': 'Bearer $token',
            },
          )
          .timeout(_timeout);
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) return null;
      return BankSetOverview.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }
}

/// S11 `GET /api/v1/practice/progress` → 前置页 done/remaining。
///
/// 契约是**裸数组** `[{module, total, answered, remaining}]`：按 setId
/// （练习模块代码）匹配数组元素，映射成 `{total, done: answered,
/// remaining}`。该接口不提供题型分布，`byType` 改从 [fallback] 的
/// `/bank/sets/{setId}/overview` 取（F26 chunk 7）；取不到为 null
/// （前置页显示“题型待接口”），绝不按比例推算。
///
/// 找不到匹配元素（例如 setId 是考试卷 id）或接口 404 / 401 / 失败时，
/// 回落到 [fallback]（`/bank/sets/{setId}/overview`）；仍取不到返回 null。
class HttpPracticeProgressOverviewSource implements BankSetOverviewSource {
  HttpPracticeProgressOverviewSource({
    http.Client? client,
    String? baseUrl,
    this.fallback,
    this.tokenProvider,
  }) : _client = client ?? http.Client(),
       _baseUrl = baseUrl ?? AppConfig.baseUrl;

  final http.Client _client;
  final String _baseUrl;
  final BankSetOverviewSource? fallback;
  final String? Function()? tokenProvider;

  static const Duration _timeout = Duration(seconds: 10);

  @override
  Future<BankSetOverview?> fetchOverview(String setId) async {
    final progress = await _fetchProgress();
    if (progress != null) {
      for (final item in progress) {
        if (item is! Map<String, dynamic>) continue;
        if (item['module'] != setId) continue;
        // progress 不含题型分布：byType 从 fallback 的套卷概览取，
        // 取不到保持 null（前置页“题型待接口”），绝不按比例推算。
        final overview = await fallback?.fetchOverview(setId);
        return BankSetOverview(
          setId: setId,
          total: (item['total'] as num?)?.toInt() ?? 0,
          done: (item['answered'] as num?)?.toInt() ?? 0,
          remaining: (item['remaining'] as num?)?.toInt() ?? 0,
          byType: overview?.byType,
        );
      }
    }
    return fallback?.fetchOverview(setId);
  }

  Future<List<dynamic>?> _fetchProgress() async {
    final token = tokenProvider?.call();
    try {
      final response = await _client
          .get(
            Uri.parse('$_baseUrl/api/v1/practice/progress'),
            headers: <String, String>{
              if (token != null && token.isNotEmpty)
                'Authorization': 'Bearer $token',
            },
          )
          .timeout(_timeout);
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      // 契约是裸数组；兼容 {items: [...]} 包装但不发明其他形状。
      if (decoded is List) return decoded;
      if (decoded is Map<String, dynamic> && decoded['items'] is List) {
        return decoded['items'] as List<dynamic>;
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
