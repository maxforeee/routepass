/// 考试服务抽象接口（规格文档第 4 章 §4.4.3）+ S11 HTTP 实现。
///
/// 服务的页面：考试页、交卷 dialog、结果页。
/// [HttpExamService] 接 S11 的三条考试接口：
/// - `POST /api/v1/exam/{session_id}/answers`：逐题暂存，只返回 `{saved: true}`，
///   不返回对错 / 答案 / 解析；同一题重复保存即覆盖（upsert）。
/// - `GET  /api/v1/exam/{session_id}`：断点恢复，卷面不含答案，已保存选项在
///   `answers` 键下（列表 `[{questionId, chosen}]`）。
/// - `POST /api/v1/exam/{session_id}/submit`：服务端按已保存选项合并 body.answers
///   判分（body 优先），重复提交返回已存结果。
///
/// 开考 / 历史不在 S11 范围内，仍委托 [local]（生产为 MockExamService）；
/// 接口未上线（404）/ 401 / 网络失败时同样回落 [local]，不编分数、不编答案。
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config.dart';
import '../../models/exam.dart';
import '../../models/question.dart';
import 'question_bank_source.dart';

abstract class ExamService {
  /// 开始考试。调用时机：点“套卷 100/200/50”或考试入口时。
  /// Mock：本地用样例题组卷，examId 为本地生成的 "MOCK-EXAM-10" 样式编号；
  /// 返回的题目不含答案（answer 为 []），与以后行为一致。
  Future<ExamSession> startExam({required int drawCount, String? setId});

  /// 考试逐题暂存（S11 `POST /exam/{sessionId}/answers`，不判分）。
  /// 同一题重复保存覆盖旧选项。接口未就绪时静默失败，本地进行态快照保证续考。
  Future<void> saveAnswer({
    required String examId,
    required String questionId,
    required List<String> chosen,
    required String opId,
  }) async {}

  /// 交卷（S11 `POST /exam/{sessionId}/submit`）。
  /// Mock：本地按空答案计分——score 一律返回 null，页面显示“样例考试，不计分”。
  /// 绝不许用 Mock 的假答案算出一个假分数。
  Future<ExamResult?> submitExam({
    required String examId,
    required Map<String, List<String>> answers,
    required int durationMs,
  });

  /// 考试详情与历史。Mock：返回空列表。
  Future<ExamSession?> getExam(String examId);
  Future<List<ExamSession>> getHistory();

  /// 断点恢复（S11 `GET /exam/{sessionId}`）：卷面 + `answers` 列表还原的
  /// 已选选项。接口未就绪返回 null，由本地 `AnswerSessionState` 快照续考。
  Future<ExamRecovery?> loadExamForResume(String examId) async => null;
}

class ExamServiceException implements Exception {
  const ExamServiceException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'ExamServiceException($message)';
}

/// S11 考试接口的 HTTP 实现；开考 / 历史 / 失败兜底委托 [local]。
class HttpExamService implements ExamService {
  HttpExamService({
    required this.local,
    http.Client? client,
    String? baseUrl,
    this.tokenProvider,
  }) : _client = client ?? http.Client(),
       _baseUrl = baseUrl ?? AppConfig.baseUrl;

  /// 开考 / 历史仍用本地实现（S11 未提供 /exam/start），请求失败时也回落它。
  final ExamService local;

  final http.Client _client;
  final String _baseUrl;

  /// 返回 access token 的回调；null 表示当前没有 Token 机制。
  final String? Function()? tokenProvider;

  static const Duration _timeout = Duration(seconds: 10);

  @override
  Future<ExamSession> startExam({required int drawCount, String? setId}) =>
      local.startExam(drawCount: drawCount, setId: setId);

  @override
  Future<List<ExamSession>> getHistory() => local.getHistory();

  @override
  Future<void> saveAnswer({
    required String examId,
    required String questionId,
    required List<String> chosen,
    required String opId,
  }) async {
    if (examId.isEmpty) return;
    // 只发 questionId + answer；失败静默（本地快照仍可续考）。
    await _post(
      '/api/v1/exam/${Uri.encodeComponent(examId)}/answers',
      <String, Object?>{'questionId': questionId, 'answer': chosen},
    );
  }

  @override
  Future<ExamResult?> submitExam({
    required String examId,
    required Map<String, List<String>> answers,
    required int durationMs,
  }) async {
    if (examId.isEmpty) {
      return local.submitExam(
        examId: examId,
        answers: answers,
        durationMs: durationMs,
      );
    }
    final decoded = await _post(
      '/api/v1/exam/${Uri.encodeComponent(examId)}/submit',
      <String, Object?>{'answers': answers, 'durationMs': durationMs},
    );
    if (decoded == null) {
      return local.submitExam(
        examId: examId,
        answers: answers,
        durationMs: durationMs,
      );
    }
    final detail = decoded['detail'];
    return ExamResult(
      score: (decoded['score'] as num?)?.toInt(),
      passed: decoded['passed'] as bool?,
      detail: detail is String
          ? detail
          : (detail == null ? '' : jsonEncode(detail)),
    );
  }

  @override
  Future<ExamSession?> getExam(String examId) async {
    final recovery = await loadExamForResume(examId);
    if (recovery == null) return local.getExam(examId);
    return ExamSession(
      id: recovery.id,
      started_at: recovery.startedAt,
      total: recovery.total > 0 ? recovery.total : recovery.questions.length,
      detail: '',
      snapshot: recovery.questions
          .map(
            (q) => ExamSnapshot(
              stem: q.stem,
              options: q.options,
              answer: const <String>[],
              analysis: '',
            ),
          )
          .toList(),
    );
  }

  @override
  Future<ExamRecovery?> loadExamForResume(String examId) async {
    if (examId.isEmpty) return null;
    final decoded = await _get('/api/v1/exam/${Uri.encodeComponent(examId)}');
    if (decoded == null) return null;
    final rawQuestions = decoded['questions'];
    final questions = <Question>[];
    if (rawQuestions is List) {
      for (final item in rawQuestions) {
        if (item is! Map<String, dynamic>) continue;
        final mapped = mapBankQuestionJson(item, requireAnswer: false);
        if (mapped != null) questions.add(mapped);
      }
    }
    if (questions.isEmpty) return null;
    return ExamRecovery(
      id: decoded['id'] as String? ?? examId,
      questions: questions,
      answers: _parseAnswers(decoded['answers']),
      startedAt:
          (decoded['startedAt'] as num?)?.toInt() ??
          (decoded['started_at'] as num?)?.toInt() ??
          0,
      total: (decoded['total'] as num?)?.toInt() ?? questions.length,
      lastQuestionId: decoded['lastQuestionId'] as String?,
    );
  }

  /// `answers` 是列表 `[{questionId, chosen}]`；也接受 map 形状的旧数据。
  Map<String, List<String>> _parseAnswers(Object? raw) {
    final result = <String, List<String>>{};
    if (raw is List) {
      for (final item in raw) {
        if (item is! Map<String, dynamic>) continue;
        final id = item['questionId'] as String?;
        if (id == null) continue;
        result[id] = (item['chosen'] as List<dynamic>? ?? const [])
            .cast<String>();
      }
    } else if (raw is Map<String, dynamic>) {
      raw.forEach((key, value) {
        if (value is List) result[key] = value.cast<String>();
      });
    }
    return result;
  }

  Map<String, String> get _headers {
    final token = tokenProvider?.call();
    return <String, String>{
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  Future<Map<String, dynamic>?> _get(String path) async {
    try {
      final response = await _client
          .get(Uri.parse('$_baseUrl$path'), headers: _headers)
          .timeout(_timeout);
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _post(
    String path,
    Map<String, Object?> body,
  ) async {
    try {
      final response = await _client
          .post(
            Uri.parse('$_baseUrl$path'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}
