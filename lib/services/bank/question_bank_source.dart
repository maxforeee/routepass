/// 题库 / 套卷概览的服务端数据源（F19 cache-first）。
///
/// 只做「拉取 + 映射」，不碰缓存与 UI：
/// - [HttpBankQuestionBankSource]：`GET /api/v1/bank/questions?page=N[&module=X]`
///   分页拉取整套题，映射成客户端 `Question` 契约后由
///   [CachedPracticeService] 写入 SQLite 本地题库。
/// - [HttpBankSetOverviewSource]：`GET /api/v1/bank/sets/{setId}/overview`
///   （后端仍返回 404 时按「接口未就绪」返回 null，不编数字）。
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
        final mapped = _mapQuestion(item);
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

  /// 后端题 → 客户端契约：options 纯字符串 → A/B/C… key；
  /// answer（0 基下标数组）→ 字母 key 列表。脏数据跳过。
  Question? _mapQuestion(Map<String, dynamic> json) {
    final id = json['id'];
    final stem = json['stem'];
    final optionsRaw = json['options'];
    if (id is! String || stem is! String || optionsRaw is! List) return null;
    final options = <QuestionOption>[];
    for (var i = 0; i < optionsRaw.length; i++) {
      final text = optionsRaw[i];
      if (text is! String) return null;
      options.add(QuestionOption(key: _letter(i), text: text));
    }
    if (options.isEmpty) return null;
    final answer = <String>[];
    for (final raw in (json['answer'] as List<dynamic>? ?? const [])) {
      final index = (raw as num?)?.toInt();
      if (index == null || index < 0 || index >= options.length) return null;
      answer.add(_letter(index));
    }
    if (answer.isEmpty) return null;
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

  static String _letter(int index) =>
      String.fromCharCode('A'.codeUnitAt(0) + index);
}

/// `/bank/sets/{setId}/overview` 的 HTTP 实现。
class HttpBankSetOverviewSource implements BankSetOverviewSource {
  HttpBankSetOverviewSource({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? AppConfig.baseUrl;

  final http.Client _client;
  final String _baseUrl;

  static const Duration _timeout = Duration(seconds: 10);

  @override
  Future<BankSetOverview?> fetchOverview(String setId) async {
    final uri = Uri.parse(
      '$_baseUrl/api/v1/bank/sets/${Uri.encodeComponent(setId)}/overview',
    );
    final http.Response response;
    try {
      response = await _client.get(uri).timeout(_timeout);
    } catch (e) {
      throw BankQuestionSourceException('套卷概览请求失败：$e');
    }
    // 后端未实现该接口时为 404：按“接口待就绪”处理，不编数字。
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw BankQuestionSourceException(
        '套卷概览请求失败（HTTP ${response.statusCode}）',
      );
    }
    final dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (e) {
      throw BankQuestionSourceException('套卷概览解析失败：$e');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const BankQuestionSourceException('套卷概览格式错误');
    }
    return BankSetOverview.fromJson(decoded);
  }
}
