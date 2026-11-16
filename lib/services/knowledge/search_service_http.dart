/// SearchService 的 HTTP 装饰器（F26 chunk 5，F23 B11）。
///
/// 真实搜索走两个后端端点（page 1、page_size 20）：
/// - `GET /api/v1/knowledge/search?q=...` → `{points: [...], total}`；
/// - `GET /api/v1/bank/questions/search?q=...` → `{questions: [...], total}`。
/// 题目行复用题库拉取的既有映射 [mapBankQuestionJson]（后端是 camelCase +
/// 0 基 answer，`Question.fromJson` 的 snake_case 契约不能直接吃）；知识点
/// 行把后端 `_point()` 的 camelCase 显式归一成 §4.8.2 契约后再走
/// `KnowledgePoint.fromJson`（contentMd 可为 null → 空串，不编正文）。
/// 空关键词不发请求；未登录 / 离线 / 401 / 404 / 500 / 非 JSON 一律按区
/// 回落注入的 [fallback]（生产为 Mock），不抛给 UI；后端诚实返回空列表
/// 就是空结果，绝不拿样例数据冒充真实命中。
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config.dart';
import '../../models/knowledge_point.dart';
import '../../models/question.dart';
import '../../models/search.dart';
import '../bank/question_bank_source.dart';
import 'search_service.dart';

class HttpSearchService implements SearchService {
  HttpSearchService({
    required this.fallback,
    http.Client? client,
    String? baseUrl,
    this.tokenProvider,
  }) : _client = client ?? http.Client(),
       _baseUrl = baseUrl ?? AppConfig.baseUrl;

  /// 任一区失败 / 未登录时的兜底搜索（生产为 MockSearchService）。
  final SearchService fallback;

  final http.Client _client;
  final String _baseUrl;

  /// 返回 access token 的回调；未登录返回 null → 直接走兜底，不发请求。
  /// Bearer 附加与 401 刷新一次重放由注入的 AuthHttpClient 统一承担。
  final String? Function()? tokenProvider;

  static const Duration _timeout = Duration(seconds: 10);

  @override
  Future<SearchResult> search(String keyword) async {
    final key = keyword.trim();
    if (key.isEmpty) {
      return const SearchResult(knowledgePoints: [], questions: []);
    }
    final token = tokenProvider?.call();
    if (token == null || token.isEmpty) return fallback.search(key);

    final q = Uri.encodeQueryComponent(key);
    const paging = 'page=1&page_size=20';
    final pointJson = await _get(
      '/api/v1/knowledge/search?q=$q&$paging',
      token,
    );
    final questionJson = await _get(
      '/api/v1/bank/questions/search?q=$q&$paging',
      token,
    );
    final points = _parsePoints(pointJson);
    final questions = _parseQuestions(questionJson);
    if (points != null && questions != null) {
      return SearchResult(knowledgePoints: points, questions: questions);
    }
    // 只回落失败的那一区；成功区保留真实结果。
    final mock = await fallback.search(key);
    return SearchResult(
      knowledgePoints: points ?? mock.knowledgePoints,
      questions: questions ?? mock.questions,
    );
  }

  /// 请求：404 / 401 / 网络失败 / 非 JSON 一律返回 null（未就绪），
  /// 由调用方按区回落兜底，不抛给 UI。
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

  /// 后端 `{points: [...]}` → 知识点列表；形状不对 / 解析失败返回 null。
  /// 后端键是 `points`（不是 knowledgePoints），逐行显式映射。
  List<KnowledgePoint>? _parsePoints(Map<String, dynamic>? json) {
    if (json == null) return null;
    final items = json['points'];
    if (items is! List) return null;
    try {
      final points = <KnowledgePoint>[];
      for (final item in items) {
        if (item is! Map<String, dynamic>) continue;
        final point = _pointFromBackend(item);
        if (point != null) points.add(point);
      }
      return points;
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
  }

  /// 后端 `{questions: [...]}` → 题目列表；复用题库拉取的既有映射
  /// （options 字符串 → A/B/C…、answer 0 基下标 → 字母、set_no 记 0）。
  List<Question>? _parseQuestions(Map<String, dynamic>? json) {
    if (json == null) return null;
    final items = json['questions'];
    if (items is! List) return null;
    try {
      final questions = <Question>[];
      for (final item in items) {
        if (item is! Map<String, dynamic>) continue;
        final question = mapBankQuestionJson(item);
        if (question != null) questions.add(question);
      }
      return questions;
    } catch (_) {
      return null;
    }
  }
}
