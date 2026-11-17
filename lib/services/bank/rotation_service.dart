/// 7 天轮回练习服务（F28，F23 缺口 A12）。
///
/// 与 S11 练习（`GET /practice/next` + `POST /practice/submit`，永久排除
/// 已答题）是**两条独立流程**：轮回按服务端 7 天窗口抽整批、逐题服务端
/// 判分、整批结算。本服务只碰轮回契约：
/// - `POST /api/v1/practice/draw`：整批抽题（排除近 7 天已答，不含答案）；
/// - `POST /api/v1/sessions/{id}/answers`：单题服务端判分（写 attempts，
///   刷新 7 天窗口），opId 幂等；
/// - `POST /api/v1/sessions/{id}/submit`：结算（0 题已答时服务端删除会话，
///   返回 deleted: true）。
///
/// [HttpRotationService] 跟随 HttpStatsService 模式：Bearer 附加与 401
/// 刷新一次重放由注入的 AuthHttpClient 统一承担；任何失败（404 / 401 /
/// 断网 / 非 JSON）回落 [fallback]（生产为 MockRotationService：诚实空态，
/// 绝不编题、编解锁时间、编分数）。
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config.dart';
import '../../models/question.dart';
import '../auth/auth_service.dart';
import 'question_bank_source.dart';

/// 轮回幂等键：复用登录设备码同款 UUIDv4 生成器（不引新依赖）。
/// 每次单题作答 / 每次结算各生成一个（服务端 op_id 上限 64 字符）。
String newRotationOpId() => HttpAuthService.generateUuidV4();

/// 整批抽题结果（`POST /practice/draw`）。
class RotationDraw {
  const RotationDraw({
    required this.sessionId,
    required this.questions,
    required this.totalCount,
    required this.drawnShort,
    this.nextUnlockAt,
    this.message,
  });

  /// 服务端会话 id（`ps_YYYYMMDD_NNNN`）；无可抽题时为 null。
  final String? sessionId;

  /// 本批题目（不含答案与解析，判分只来自服务端）。
  final List<Question> questions;

  final int totalCount;

  /// 可抽题不足请求数（含完全抽不出）。
  final bool drawnShort;

  /// 最早解锁时间（仅 short / 空抽时下发）；没有就是 null，绝不编造。
  final DateTime? nextUnlockAt;

  /// 服务端说明文案（仅 short / 空抽时下发）。
  final String? message;

  /// 空抽：没有会话也没有题，UI 显示服务端文案 + 解锁时间。
  bool get isEmpty => sessionId == null || questions.isEmpty;

  @override
  String toString() =>
      'RotationDraw($sessionId, ${questions.length} 题, short: $drawnShort)';
}

/// 单题判分结果（`POST /sessions/{id}/answers`）。
class RotationAnswer {
  const RotationAnswer({
    required this.isCorrect,
    required this.answer,
    required this.explanation,
  });

  final bool isCorrect;

  /// 正确答案选项 key（服务端 0 基下标数组已转成 A/B/C…）。
  final List<String> answer;

  /// 服务端解析；null / 缺失为空串（UI 显示「解析待接口」，不编解析）。
  final String explanation;

  @override
  String toString() => 'RotationAnswer(correct: $isCorrect)';
}

/// 结算明细单题（`POST /sessions/{id}/submit` 的 `detail` 元素）。
class RotationDetailItem {
  const RotationDetailItem({
    required this.questionId,
    required this.isCorrect,
    required this.answer,
    required this.chosen,
    required this.explanation,
  });

  final String questionId;
  final bool isCorrect;

  /// 正确答案 key（服务端下标数组已转换）。
  final List<String> answer;

  /// 用户所选 key（服务端下标数组已转换）。
  final List<String> chosen;

  final String explanation;

  @override
  String toString() => 'RotationDetailItem($questionId, correct: $isCorrect)';
}

/// 结算结果（`POST /sessions/{id}/submit`）。
class RotationResult {
  const RotationResult({
    required this.correctCount,
    required this.wrongCount,
    required this.score,
    required this.detail,
    required this.deleted,
  });

  final int correctCount;
  final int wrongCount;

  /// 0–100；0 题已答被服务端删除时为 null，绝不编 0 分。
  final int? score;

  final List<RotationDetailItem> detail;

  /// true = 0 题已答，服务端已删除会话（没有可展示的成绩）。
  final bool deleted;

  @override
  String toString() =>
      'RotationResult($correctCount/$wrongCount, score: $score, '
      'deleted: $deleted)';
}

class RotationServiceException implements Exception {
  const RotationServiceException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'RotationServiceException($message)';
}

abstract class RotationService {
  /// 整批抽题。[bankId] 必须来自题库清单（`GET /bank/manifest` 的 bankId），
  /// 不许硬编码。[count] 1–50。
  Future<RotationDraw> draw({required String bankId, int count = 20});

  /// 单题服务端判分。[chosen] 是 0 基下标数组；[opId] 幂等键。
  Future<RotationAnswer> answer({
    required String sessionId,
    required String questionId,
    required List<int> chosen,
    required String opId,
  });

  /// 结算本批。0 题已答时服务端删除会话（deleted: true, score: null）。
  Future<RotationResult> submit({
    required String sessionId,
    required String opId,
  });
}

/// 轮回接口的 HTTP 实现（跟随 HttpStatsService 模式）。
class HttpRotationService implements RotationService {
  HttpRotationService({
    http.Client? client,
    String? baseUrl,
    this.fallback,
    this.tokenProvider,
  }) : _client = client ?? http.Client(),
       _baseUrl = baseUrl ?? AppConfig.baseUrl;

  final http.Client _client;
  final String _baseUrl;

  /// 接口未就绪 / 请求失败时的本地兜底（不编数据）。
  final RotationService? fallback;

  /// 返回 access token 的回调；未登录返回 null（不带 Authorization 头）。
  final String? Function()? tokenProvider;

  static const Duration _timeout = Duration(seconds: 10);

  @override
  Future<RotationDraw> draw({required String bankId, int count = 20}) async {
    final data = await _post('/api/v1/practice/draw', <String, Object?>{
      'bank_id': bankId,
      'count': count,
    });
    if (data == null) {
      final local = fallback;
      if (local == null) {
        throw const RotationServiceException('轮回抽题不可用');
      }
      return local.draw(bankId: bankId, count: count);
    }
    final questions = <Question>[];
    final rawQuestions = data['questions'];
    if (rawQuestions is List) {
      for (final raw in rawQuestions) {
        if (raw is! Map<String, dynamic>) continue;
        // 抽题不含答案：requireAnswer=false，判分只来自服务端。
        final mapped = mapBankQuestionJson(raw, requireAnswer: false);
        if (mapped != null) questions.add(mapped);
      }
    }
    final rawUnlock = data['next_unlock_at'];
    return RotationDraw(
      sessionId: data['session_id'] as String?,
      questions: questions,
      totalCount: (data['total_count'] as num?)?.toInt() ?? questions.length,
      drawnShort: data['drawn_short'] == true,
      nextUnlockAt: rawUnlock is String ? DateTime.tryParse(rawUnlock) : null,
      message: data['message'] as String?,
    );
  }

  @override
  Future<RotationAnswer> answer({
    required String sessionId,
    required String questionId,
    required List<int> chosen,
    required String opId,
  }) async {
    final data = await _post(
      '/api/v1/sessions/${Uri.encodeComponent(sessionId)}/answers',
      <String, Object?>{
        'questionId': questionId,
        'answer': chosen,
        'opId': opId,
      },
    );
    if (data == null) {
      final local = fallback;
      if (local == null) {
        throw const RotationServiceException('轮回判分不可用');
      }
      return local.answer(
        sessionId: sessionId,
        questionId: questionId,
        chosen: chosen,
        opId: opId,
      );
    }
    return RotationAnswer(
      isCorrect: data['is_correct'] == true,
      answer: bankAnswerKeys(data['answer']) ?? const <String>[],
      explanation: data['explanation'] as String? ?? '',
    );
  }

  @override
  Future<RotationResult> submit({
    required String sessionId,
    required String opId,
  }) async {
    final data = await _post(
      '/api/v1/sessions/${Uri.encodeComponent(sessionId)}/submit',
      <String, Object?>{'opId': opId},
    );
    if (data == null) {
      final local = fallback;
      if (local == null) {
        throw const RotationServiceException('轮回结算不可用');
      }
      return local.submit(sessionId: sessionId, opId: opId);
    }
    final detail = <RotationDetailItem>[];
    final rawDetail = data['detail'];
    if (rawDetail is List) {
      for (final raw in rawDetail) {
        if (raw is! Map<String, dynamic>) continue;
        detail.add(
          RotationDetailItem(
            questionId: raw['question_id'] as String? ?? '',
            isCorrect: raw['is_correct'] == true,
            answer: bankAnswerKeys(raw['answer']) ?? const <String>[],
            chosen: bankAnswerKeys(raw['chosen']) ?? const <String>[],
            explanation: raw['explanation'] as String? ?? '',
          ),
        );
      }
    }
    return RotationResult(
      correctCount: (data['correct_count'] as num?)?.toInt() ?? 0,
      wrongCount: (data['wrong_count'] as num?)?.toInt() ?? 0,
      score: (data['score'] as num?)?.toInt(),
      detail: detail,
      deleted: data['deleted'] == true,
    );
  }

  Map<String, String> get _headers {
    final token = tokenProvider?.call();
    return <String, String>{
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  /// 请求：404 / 401 / 网络失败 / 非 JSON 一律返回 null（未就绪），
  /// 由调用方回落兜底，不抛给 UI。
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
