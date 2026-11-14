/// 练习服务抽象接口（规格文档第 4 章 §4.4.2）+ S11 HTTP 实现。
///
/// 服务的页面：答题页 A-01–A-19（练习模式）、首页 H-B1 继续学习。
/// [HttpPracticeService] 按 S11 真实契约直连后端：
/// - `POST /api/v1/practice/sessions`：开始 / 续接会话（满 20 题由服务端结算）；
/// - `GET  /api/v1/practice/next?module=&sessionId=`：服务端按 attempts 排除已答；
/// - `POST /api/v1/practice/submit`：判分，带 sessionId 时同步会话计数；
/// - `POST /api/v1/practice/sessions/{id}/end`：结算或留断点；
/// - `GET  /api/v1/practice/records`：服务端记录列表（只读，无批量上传）；
/// - `GET  /api/v1/practice/sessions/{id}`：断点会话详情（含已答题目 id）；
/// - `GET  /api/v1/practice/progress`：裸数组模块进度（无题型分布）。
///
/// 服务端接口未上线（404）/ 未鉴权（401）/ 网络失败时一律回落 [fallback]
/// 或返回 null / 空列表，由 UI 保留本地缓存与“待接口”文案；绝不编题、
/// 编计数、编记录。
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config.dart';
import '../../models/practice.dart';
import '../../models/question.dart';
import 'question_bank_source.dart';

abstract class PracticeService {
  /// 开始一次练习会话。调用时机：从题库页/首页方块进答题页时。
  /// Mock：用 drawQuestions 的结果在本地建会话。
  Future<PracticeSession> startSession({
    required List<Question> questions,
    required String mode,
  });

  /// 提交单题作答。调用时机：用户选完选项点“下一题”或“确认”时。
  /// [sessionId] 为服务端会话 id（S11 `POST /practice/submit` 的 `sessionId`）。
  /// Mock：只在本地记一笔，不判对错，correct 字段返回 null。
  Future<AnswerResult> submitAnswer({
    required String sessionId,
    required String questionId,
    required List<String> chosen, // 如 ["A"] 或 ["A", "C"]
    required int durationMs,
    String? setId,
    String? opId,
    String? mode,
  });

  /// 抽下一道练习题（S11 `GET /practice/next`）。
  ///
  /// 服务端按 attempts 表排除本用户已答题（练习会话记录在 attempts 上），
  /// 客户端传 [sessionId] 即可，不再上传 exclude 列表。[excludedIds] 只给
  /// 本地缓存层（[CachedPracticeService]）做离线排除用。抽尽返回 null（204）。
  Future<PracticeNext?> drawNextQuestion({
    required String setId,
    String? module,
    required Set<String> excludedIds,
    String? sessionId,
  });

  /// 开始 / 续接服务端练习会话（S11 `POST /practice/sessions`）。
  ///
  /// 服务端行为：已有 in_progress 会话且 answered_count < 20 时返回该会话
  /// （续接）；answered_count >= 20 时先把旧会话结算为 completed，再新建。
  /// 接口未就绪返回 null，本地进行态由 [AnswerSessionService] 承担。
  Future<PracticeSessionInfo?> startPracticeSession({String? module}) async =>
      null;

  /// 断点会话详情（S11 `GET /practice/sessions/{id}`，含 answeredQuestionIds）。
  Future<PracticeSessionInfo?> fetchPracticeSession(String sessionId) async =>
      null;

  /// 结束会话（S11 `POST /practice/sessions/{id}/end`）。
  /// answered_count >= 20 时服务端置 completed，否则保留 in_progress 断点。
  Future<PracticeSessionInfo?> endPracticeSession(String sessionId) async =>
      null;

  /// 服务端练习记录（S11 `GET /practice/records`，分页，新的在前）。
  /// 未就绪返回空列表（本地 kv 记录仍可离线展示）。
  Future<List<PracticeRecordSummary>> fetchPracticeRecords({
    int page = 1,
    int pageSize = 20,
  }) async => const <PracticeRecordSummary>[];

  /// 模块进度（S11 `GET /practice/progress`，裸数组）。
  /// 未就绪返回空列表，前置页回落到缓存 / “待接口”。
  Future<List<PracticeModuleProgress>> fetchPracticeProgress() async =>
      const <PracticeModuleProgress>[];

  /// 取未完成练习会话（旧 `GET /practice/session` 预留）。服务端会话接口
  /// 未就绪时返回 null，本地进行态由 [AnswerSessionService] 承担。
  Future<ContinueSession?> resumeSession({required String setId}) async {
    return null;
  }

  /// 取未完成会话（供 H-B1 继续学习）。Mock：返回 null。
  /// 返回类型是 ContinueSession?（轻量进度指针，见 §4.3 H-B1 与 §4.9.1
  /// kv 键 home.continue），不是 PracticeSession。
  Future<ContinueSession?> getContinueSession();
}

class PracticeServiceException implements Exception {
  const PracticeServiceException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'PracticeServiceException($message)';
}

/// S11 练习接口的 HTTP 实现。
///
/// [fallback] 为接口未上线时的本地兜底（生产为 MockPracticeService：
/// 样例题、不判分）。[tokenProvider] 生产由 `main.dart` 注入
/// `authService.cachedAccessToken`，请求带 `Authorization: Bearer` 头；
/// 未登录时返回 null（不带头，服务端 401 时走兜底）。[sessionId] 全程按
/// 不透明字符串处理（VARCHAR(40)）。
class HttpPracticeService implements PracticeService {
  HttpPracticeService({
    http.Client? client,
    String? baseUrl,
    this.fallback,
    this.tokenProvider,
  }) : _client = client ?? http.Client(),
       _baseUrl = baseUrl ?? AppConfig.baseUrl;

  final http.Client _client;
  final String _baseUrl;

  /// 接口未就绪 / 请求失败时的本地兜底（不编数据，仍走既有 Mock 行为）。
  final PracticeService? fallback;

  /// 返回 access token 的回调；未登录返回 null（不带 Authorization 头）。
  final String? Function()? tokenProvider;

  static const Duration _timeout = Duration(seconds: 10);

  @override
  Future<PracticeSession> startSession({
    required List<Question> questions,
    required String mode,
  }) async {
    return PracticeSession(
      id: '',
      questions: questions,
      mode: mode,
      total: questions.length,
    );
  }

  @override
  Future<PracticeNext?> drawNextQuestion({
    required String setId,
    String? module,
    required Set<String> excludedIds,
    String? sessionId,
  }) async {
    final query = <String>[
      if (module != null && module.isNotEmpty)
        'module=${Uri.encodeQueryComponent(module)}',
      if (sessionId != null && sessionId.isNotEmpty)
        'sessionId=${Uri.encodeQueryComponent(sessionId)}',
    ].join('&');
    final uri = Uri.parse(
      '$_baseUrl/api/v1/practice/next${query.isEmpty ? '' : '?$query'}',
    );
    try {
      final response = await _client
          .get(uri, headers: _headers)
          .timeout(_timeout);
      // 204：已经抽尽，不编题。
      if (response.statusCode == 204) return null;
      if (response.statusCode != 200) {
        throw PracticeServiceException(
          '抽题失败（HTTP ${response.statusCode}）',
          statusCode: response.statusCode,
        );
      }
      final decoded = _decode(response);
      final questionJson = decoded['question'] is Map<String, dynamic>
          ? decoded['question'] as Map<String, dynamic>
          : decoded;
      final merged = <String, dynamic>{
        ...questionJson,
        for (final key in const <String>['answer', 'explanation'])
          if (questionJson[key] == null && decoded[key] != null)
            key: decoded[key],
      };
      final question = mapBankQuestionJson(merged);
      if (question == null) {
        throw const PracticeServiceException('抽题格式错误');
      }
      final serverSession = decoded['sessionId'] as String? ?? '';
      return PracticeNext(
        question: question,
        sessionId: serverSession.isNotEmpty ? serverSession : (sessionId ?? ''),
        doneCount: excludedIds.length,
      );
    } catch (_) {
      final local = fallback;
      if (local == null) rethrow;
      return local.drawNextQuestion(
        setId: setId,
        module: module,
        excludedIds: excludedIds,
        sessionId: sessionId,
      );
    }
  }

  @override
  Future<AnswerResult> submitAnswer({
    required String sessionId,
    required String questionId,
    required List<String> chosen,
    required int durationMs,
    String? setId,
    String? opId,
    String? mode,
  }) async {
    final body = <String, Object?>{
      'setId': ?setId,
      'questionId': questionId,
      'chosen': chosen,
      'durationMs': durationMs,
      'opId': ?opId,
      'mode': mode ?? 'practice',
      if (sessionId.isNotEmpty) 'sessionId': sessionId,
    };
    try {
      final response = await _client
          .post(
            Uri.parse('$_baseUrl/api/v1/practice/submit'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      if (response.statusCode != 200) {
        throw PracticeServiceException(
          '提交失败（HTTP ${response.statusCode}）',
          statusCode: response.statusCode,
        );
      }
      final decoded = _decode(response);
      final answer = (decoded['answer'] as List<dynamic>?)?.cast<String>();
      return AnswerResult(
        correct: decoded['correct'] as bool?,
        explanation: decoded['explanation'] as String? ?? '',
        correctKeys: answer,
        opId: decoded['opId'] as String? ?? opId,
      );
    } catch (_) {
      final local = fallback;
      if (local == null) rethrow;
      return local.submitAnswer(
        sessionId: sessionId,
        questionId: questionId,
        chosen: chosen,
        durationMs: durationMs,
        setId: setId,
        opId: opId,
        mode: mode,
      );
    }
  }

  @override
  Future<PracticeSessionInfo?> startPracticeSession({String? module}) async {
    final data = await _send(
      'POST',
      '/api/v1/practice/sessions',
      body: <String, Object?>{
        if (module != null && module.isNotEmpty) 'module': module,
      },
    );
    return data == null ? null : PracticeSessionInfo.fromJson(data);
  }

  @override
  Future<PracticeSessionInfo?> fetchPracticeSession(String sessionId) async {
    if (sessionId.isEmpty) return null;
    final data = await _send(
      'GET',
      '/api/v1/practice/sessions/${Uri.encodeComponent(sessionId)}',
    );
    return data == null ? null : PracticeSessionInfo.fromJson(data);
  }

  @override
  Future<PracticeSessionInfo?> endPracticeSession(String sessionId) async {
    if (sessionId.isEmpty) return null;
    final data = await _send(
      'POST',
      '/api/v1/practice/sessions/${Uri.encodeComponent(sessionId)}/end',
    );
    return data == null ? null : PracticeSessionInfo.fromJson(data);
  }

  @override
  Future<List<PracticeRecordSummary>> fetchPracticeRecords({
    int page = 1,
    int pageSize = 20,
  }) async {
    final data = await _send(
      'GET',
      '/api/v1/practice/records?page=$page&pageSize=$pageSize',
    );
    if (data == null) return const <PracticeRecordSummary>[];
    final items = _itemList(data);
    return items
        .whereType<Map<String, dynamic>>()
        .map(PracticeRecordSummary.fromJson)
        .toList();
  }

  @override
  Future<List<PracticeModuleProgress>> fetchPracticeProgress() async {
    final data = await _send(
      'GET',
      '/api/v1/practice/progress',
      bareList: true,
    );
    if (data == null) return const <PracticeModuleProgress>[];
    final items = _itemList(data);
    return items
        .whereType<Map<String, dynamic>>()
        .map(PracticeModuleProgress.fromJson)
        .toList();
  }

  @override
  Future<ContinueSession?> resumeSession({required String setId}) async {
    final local = fallback;
    if (local == null) return null;
    return local.resumeSession(setId: setId);
  }

  @override
  Future<ContinueSession?> getContinueSession() async {
    final local = fallback;
    if (local == null) return null;
    return local.getContinueSession();
  }

  Map<String, String> get _headers {
    final token = tokenProvider?.call();
    return <String, String>{
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  /// S11 请求：404 / 401 / 网络失败 / 非 JSON 一律返回 null（未就绪），
  /// 由调用方保留本地行为，不抛给 UI。
  ///
  /// [bareList] 为 true 时接受裸数组（`GET /practice/progress` 的契约形状）。
  Future<Map<String, dynamic>?> _send(
    String method,
    String path, {
    Map<String, Object?>? body,
    bool bareList = false,
  }) async {
    final uri = Uri.parse('$_baseUrl$path');
    try {
      final http.Response response;
      if (method == 'POST') {
        response = await _client
            .post(
              uri,
              headers: _headers,
              body: body == null ? null : jsonEncode(body),
            )
            .timeout(_timeout);
      } else {
        response = await _client.get(uri, headers: _headers).timeout(_timeout);
      }
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) return decoded;
      if (bareList && decoded is List) {
        return <String, dynamic>{'items': decoded};
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _decode(http.Response response) {
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw const PracticeServiceException('响应格式错误');
    }
    return decoded;
  }

  /// 记录 / 进度列表：接受裸数组，也接受 `{items: [...]}` 包装。
  List<dynamic> _itemList(Map<String, dynamic> data) {
    final items = data['items'] ?? data['records'] ?? data['progress'];
    if (items is List) return items;
    return const <dynamic>[];
  }
}
