// 字段名必须与规格文档 §4.8 数据契约一字不差（snake_case），故忽略本 lint。
// ignore_for_file: non_constant_identifier_names
/// 做题记录与练习会话模型（规格文档第 4 章 §4.8.4 与 §4.4.2）。
///
/// `PracticeRecord` 字段名与 §4.8.4 数据契约一字不差（客户端表
/// `practice_records`，只追加）；`PracticeSession` / `ContinueSession` /
/// `AnswerResult` 按 §4.4.2 的接口行为建模。Mock 数据必须符合同一契约，
/// 不许编造契约之外的字段（§4.8.9）。
library;

import 'question.dart' show Question;

/// 单题作答记录（§4.8.4，客户端表 `practice_records`，只追加）。
class PracticeRecord {
  const PracticeRecord({
    required this.question_id,
    required this.chosen,
    required this.correct,
    required this.duration_ms,
    required this.mode,
    required this.created_at,
  });

  /// 题目 id。
  final String question_id;

  /// 本次所选，如 `["A"]` 或 `["A", "C"]`。
  final List<String> chosen;

  /// 是否答对。**Mock 恒为 `null`（不判对错，见 §4.4.2）**；接后端后为
  /// `POST /practice/answer` 返回的 `correct`。
  final bool? correct;

  /// 本题用时毫秒。
  final int duration_ms;

  /// 模式：`practice` / `exam` / `daily`。
  final String mode;

  /// 毫秒时间戳。
  final int created_at;

  factory PracticeRecord.fromJson(Map<String, dynamic> json) {
    return PracticeRecord(
      question_id: json['question_id'] as String,
      chosen: (json['chosen'] as List<dynamic>).cast<String>(),
      correct: json['correct'] as bool?,
      duration_ms: json['duration_ms'] as int,
      mode: json['mode'] as String,
      created_at: json['created_at'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'question_id': question_id,
      'chosen': chosen,
      'correct': correct,
      'duration_ms': duration_ms,
      'mode': mode,
      'created_at': created_at,
    };
  }

  @override
  String toString() => 'PracticeRecord($question_id, mode: $mode)';
}

/// 练习会话（§4.4.2 `PracticeService.startSession` 返回的本地对象）。
///
/// 答题页 A-01–A-19 的数据来源：题号进度用 `currentIndex` / `total`，
/// 答题卡 sheet 用 `answers` 本地 Map，均不调接口。
class PracticeSession {
  const PracticeSession({
    required this.id,
    required this.questions,
    required this.mode,
    required this.total,
    this.currentIndex = 0,
    this.answers = const {},
  });

  /// 会话 id，`submitAnswer` 需要携带。
  final String id;

  /// 本会话的题目列表（Mock 用 drawQuestions 的结果在本地建会话）。
  final List<Question> questions;

  /// 模式：`practice` / `exam` / `daily`。
  final String mode;

  /// 总题数。
  final int total;

  /// 当前题号（A-01–A-03 题号进度，纯本地状态）。
  final int currentIndex;

  /// 作答记录：question id → 本次所选 key 列表（A-09–A-11 答题卡，
  /// 纯本地状态；点题号跳题不调接口）。
  final Map<String, List<String>> answers;

  factory PracticeSession.fromJson(Map<String, dynamic> json) {
    return PracticeSession(
      id: json['id'] as String,
      questions: (json['questions'] as List<dynamic>)
          .map((e) => Question.fromJson(e as Map<String, dynamic>))
          .toList(),
      mode: json['mode'] as String,
      total: json['total'] as int,
      currentIndex: json['currentIndex'] as int? ?? 0,
      answers: (json['answers'] as Map<String, dynamic>? ?? const {}).map(
        (k, v) => MapEntry(k, (v as List<dynamic>).cast<String>()),
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'questions': questions.map((e) => e.toJson()).toList(),
      'mode': mode,
      'total': total,
      'currentIndex': currentIndex,
      'answers': answers,
    };
  }

  @override
  String toString() =>
      'PracticeSession($id, mode: $mode, $currentIndex/$total)';
}

/// 继续学习进度指针（首页 H-B1，kv 键 `home.continue`）。
///
/// 契约形状 `{mode, questionId, answeredCount, totalCount}`（§4.4.2 接口
/// 返回与 §4.9.1 kv 值形状一致）：无进度时为 `null`，方块隐藏；
/// 答题会话中途退出时写入，会话完成时清除。
class ContinueSession {
  const ContinueSession({
    required this.mode,
    required this.answeredCount,
    required this.totalCount,
    this.questionId,
  });

  /// 模式：`practice` / `exam` / `daily`。
  final String mode;

  /// 待续题目的 id（可选）。
  final String? questionId;

  /// 已作答题数。
  final int answeredCount;

  /// 总题数。
  final int totalCount;

  factory ContinueSession.fromJson(Map<String, dynamic> json) {
    return ContinueSession(
      mode: json['mode'] as String,
      questionId: json['questionId'] as String?,
      answeredCount: json['answeredCount'] as int,
      totalCount: json['totalCount'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'mode': mode,
      'questionId': questionId,
      'answeredCount': answeredCount,
      'totalCount': totalCount,
    };
  }

  @override
  String toString() => 'ContinueSession($mode, $answeredCount/$totalCount)';
}

/// 练习抽题结果（F19，`GET /practice/next`）：题目 + 服务端会话 id。
class PracticeNext {
  const PracticeNext({
    required this.question,
    required this.sessionId,
    this.doneCount = 0,
  });

  final Question question;
  final String sessionId;
  final int doneCount;

  @override
  String toString() => 'PracticeNext(${question.id}, session: $sessionId)';
}

/// S11 练习会话（`POST /practice/sessions`、`GET|POST .../{id}` 的返回）。
///
/// 契约字段：`{id, kind, module, status, answeredCount, correctCount, startedAt}`；
/// `GET /practice/sessions/{id}` 另带 `answeredQuestionIds`（按作答顺序）。
/// `sessionId` 是不透明字符串（服务端 attempts.session_id 为 VARCHAR(40)），
/// 客户端不假设 UUID 格式。
class PracticeSessionInfo {
  const PracticeSessionInfo({
    required this.id,
    required this.module,
    required this.status,
    required this.answeredCount,
    required this.correctCount,
    required this.startedAt,
    this.kind = 'practice',
    this.answeredQuestionIds = const <String>[],
  });

  /// in_progress：断点可续；completed：达到 20 题后服务端已结算。
  static const String statusInProgress = 'in_progress';
  static const String statusCompleted = 'completed';

  final String id;
  final String kind;

  /// 练习模块（如 `VLAN`）；全模块练习为空串。
  final String module;

  /// `in_progress` | `completed`。
  final String status;

  final int answeredCount;
  final int correctCount;
  final int startedAt;

  /// 本会话已作答题 id（仅会话详情接口返回）。
  final List<String> answeredQuestionIds;

  bool get isCompleted => status == statusCompleted;

  factory PracticeSessionInfo.fromJson(Map<String, dynamic> json) {
    return PracticeSessionInfo(
      id: json['id'] as String? ?? '',
      kind: json['kind'] as String? ?? 'practice',
      module: json['module'] as String? ?? '',
      status: json['status'] as String? ?? statusInProgress,
      answeredCount: (json['answeredCount'] as num?)?.toInt() ?? 0,
      correctCount: (json['correctCount'] as num?)?.toInt() ?? 0,
      startedAt: (json['startedAt'] as num?)?.toInt() ?? 0,
      answeredQuestionIds:
          (json['answeredQuestionIds'] as List<dynamic>?)?.cast<String>() ??
          const <String>[],
    );
  }

  @override
  String toString() =>
      'PracticeSessionInfo($id, $status, $answeredCount/$correctCount)';
}

/// S11 练习记录项（`GET /practice/records` 的 `items`）。
///
/// 契约字段：`{id, module, status, answeredCount, correctCount, startedAt,
/// completedAt}`；服务端没有批量上传接口，记录由会话流程在服务端生成。
class PracticeRecordSummary {
  const PracticeRecordSummary({
    required this.id,
    required this.module,
    required this.status,
    required this.answeredCount,
    required this.correctCount,
    required this.startedAt,
    this.completedAt,
  });

  final String id;
  final String module;
  final String status;
  final int answeredCount;
  final int correctCount;
  final int startedAt;
  final int? completedAt;

  bool get isCompleted => status == PracticeSessionInfo.statusCompleted;

  factory PracticeRecordSummary.fromJson(Map<String, dynamic> json) {
    return PracticeRecordSummary(
      id: json['id'] as String? ?? '',
      module: json['module'] as String? ?? '',
      status: json['status'] as String? ?? PracticeSessionInfo.statusInProgress,
      answeredCount: (json['answeredCount'] as num?)?.toInt() ?? 0,
      correctCount: (json['correctCount'] as num?)?.toInt() ?? 0,
      startedAt: (json['startedAt'] as num?)?.toInt() ?? 0,
      completedAt: (json['completedAt'] as num?)?.toInt(),
    );
  }

  @override
  String toString() => 'PracticeRecordSummary($id, $answeredCount 题)';
}

/// S11 模块进度（`GET /practice/progress` 的裸数组元素）。
///
/// 契约字段：`{module, total, answered, remaining}`；`answered` 为该模块
/// 去重后的已作答题数，`total` 为该模块在用练习题数。**不含题型分布**。
class PracticeModuleProgress {
  const PracticeModuleProgress({
    required this.module,
    required this.total,
    required this.answered,
    required this.remaining,
  });

  final String module;
  final int total;
  final int answered;
  final int remaining;

  factory PracticeModuleProgress.fromJson(Map<String, dynamic> json) {
    return PracticeModuleProgress(
      module: json['module'] as String? ?? '',
      total: (json['total'] as num?)?.toInt() ?? 0,
      answered: (json['answered'] as num?)?.toInt() ?? 0,
      remaining: (json['remaining'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  String toString() =>
      'PracticeModuleProgress($module, $answered/$total, 剩余 $remaining)';
}

/// 单题作答结果（§4.4.2 `PracticeService.submitAnswer` 返回）。
///
/// 接后端后为 `{correct: bool, explanation: String}`；**Mock 阶段
/// `correct` 为 `null`（不判对错），解析卡显示“样例数据，解析待后端接入”**。
class AnswerResult {
  const AnswerResult({
    required this.correct,
    required this.explanation,
    this.correctKeys,
    this.opId,
  });

  /// 是否答对；Mock 恒为 `null`。
  final bool? correct;

  /// 解析文本；未接后端时显示占位文案，不许编造解析内容。
  final String explanation;

  /// F19：服务端判分返回的正确答案 key 列表（可空，旧 JSON 仍可解析）。
  final List<String>? correctKeys;

  /// F19：本次提交的幂等键（可空，旧 JSON 仍可解析）。
  final String? opId;

  factory AnswerResult.fromJson(Map<String, dynamic> json) {
    return AnswerResult(
      correct: json['correct'] as bool?,
      explanation: json['explanation'] as String? ?? '',
      correctKeys:
          (json['answer'] as List<dynamic>?)?.cast<String>() ??
          (json['correctKeys'] as List<dynamic>?)?.cast<String>(),
      opId: json['opId'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'correct': correct,
      'explanation': explanation,
      'correctKeys': correctKeys,
      'opId': opId,
    };
  }

  @override
  String toString() => 'AnswerResult(correct: $correct)';
}
