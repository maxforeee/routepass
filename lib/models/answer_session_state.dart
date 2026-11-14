/// 本地答题进行态模型（F19）。
///
/// practice 与 exam 分开持久化（kv `answer.session.<mode>.<setId>`），
/// 断点恢复 / 续答使用；与 [AnswerRecord]（历史记录）是两份数据。
library;

import 'question.dart';

/// 一次未结束答题会话的快照。
class AnswerSessionState {
  const AnswerSessionState({
    required this.setId,
    required this.setTitle,
    required this.mode,
    required this.targetCount,
    required this.answeredCount,
    required this.correctCount,
    required this.answeredIds,
    required this.answers,
    required this.startedAt,
    required this.updatedAt,
    this.examId,
    this.sessionId,
    this.snapshot,
    this.lastQuestionId,
  });

  final String setId;
  final String setTitle;

  /// `practice` | `exam`。
  final String mode;

  /// practice 目标题数；exam 卷面题数。
  final int targetCount;

  final int answeredCount;
  final int correctCount;

  /// practice：已作答题目 id（客户端兜底排除）。
  final List<String> answeredIds;

  /// exam：question id → 已选项；practice：已判分项。
  final Map<String, List<String>> answers;

  /// exam 断点续考题面（不含答案）。
  final List<Question>? snapshot;

  /// 停在哪一题。
  final String? lastQuestionId;

  final String? examId;
  final String? sessionId;
  final int startedAt;
  final int updatedAt;

  bool get isExam => mode == 'exam';

  AnswerSessionState copyWith({
    String? setId,
    String? setTitle,
    String? mode,
    int? targetCount,
    int? answeredCount,
    int? correctCount,
    List<String>? answeredIds,
    Map<String, List<String>>? answers,
    List<Question>? snapshot,
    String? lastQuestionId,
    String? examId,
    String? sessionId,
    int? startedAt,
    int? updatedAt,
  }) {
    return AnswerSessionState(
      setId: setId ?? this.setId,
      setTitle: setTitle ?? this.setTitle,
      mode: mode ?? this.mode,
      targetCount: targetCount ?? this.targetCount,
      answeredCount: answeredCount ?? this.answeredCount,
      correctCount: correctCount ?? this.correctCount,
      answeredIds: answeredIds ?? this.answeredIds,
      answers: answers ?? this.answers,
      snapshot: snapshot ?? this.snapshot,
      lastQuestionId: lastQuestionId ?? this.lastQuestionId,
      examId: examId ?? this.examId,
      sessionId: sessionId ?? this.sessionId,
      startedAt: startedAt ?? this.startedAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory AnswerSessionState.fromJson(Map<String, dynamic> json) {
    return AnswerSessionState(
      setId: json['setId'] as String? ?? '',
      setTitle: json['setTitle'] as String? ?? '',
      mode: json['mode'] as String? ?? 'practice',
      targetCount: (json['targetCount'] as num?)?.toInt() ?? 0,
      answeredCount: (json['answeredCount'] as num?)?.toInt() ?? 0,
      correctCount: (json['correctCount'] as num?)?.toInt() ?? 0,
      answeredIds: (json['answeredIds'] as List<dynamic>? ?? const [])
          .cast<String>(),
      answers: (json['answers'] as Map<String, dynamic>? ?? const {}).map(
        (k, v) => MapEntry(k, (v as List<dynamic>).cast<String>()),
      ),
      snapshot: (json['snapshot'] as List<dynamic>?)
          ?.map((e) => Question.fromJson(e as Map<String, dynamic>))
          .toList(),
      lastQuestionId: json['lastQuestionId'] as String?,
      examId: json['examId'] as String?,
      sessionId: json['sessionId'] as String?,
      startedAt: (json['startedAt'] as num?)?.toInt() ?? 0,
      updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'setId': setId,
      'setTitle': setTitle,
      'mode': mode,
      'targetCount': targetCount,
      'answeredCount': answeredCount,
      'correctCount': correctCount,
      'answeredIds': answeredIds,
      'answers': answers,
      'snapshot': snapshot?.map((q) => q.toJson()).toList(),
      'lastQuestionId': lastQuestionId,
      'examId': examId,
      'sessionId': sessionId,
      'startedAt': startedAt,
      'updatedAt': updatedAt,
    };
  }

  @override
  String toString() =>
      'AnswerSessionState($setId/$mode, $answeredCount/$targetCount)';
}
