/// 本地答题记录模型（F19）。
///
/// 本地 kv `answer.records` 的持久形状；JSON 键与字段同名（camelCase，
/// 本地模型，不走服务端 §4.8 snake_case 契约）。后端
/// `POST /practice/records` 就绪后以 [id] 作为幂等键。
library;

/// 一条答题记录：完成（completion）或断点（breakpoint）。
class AnswerRecord {
  const AnswerRecord({
    required this.id,
    required this.setId,
    required this.setTitle,
    required this.mode,
    required this.kind,
    required this.targetCount,
    required this.answeredCount,
    required this.totalCount,
    required this.durationMs,
    required this.createdAt,
    required this.updatedAt,
    this.correctCount,
    this.score,
    this.lastQuestionId,
    this.synced = false,
    this.serverId,
  });

  /// 本地唯一 id：`rec-<createdAt>-<4 位随机>`，同步幂等键。
  final String id;

  /// 练习模块代码（VLAN）或考试卷 id（h3cne-2026-01）。
  final String setId;

  /// 记录卡展示用套卷标题（'VLAN' / 'A卷'）。
  final String setTitle;

  /// `practice` | `exam`。
  final String mode;

  /// `completion` | `breakpoint`。
  final String kind;

  /// practice = 目标（默认 20）；exam = 卷面题数。
  final int targetCount;

  /// completion = 最终题数（如 35）；breakpoint = 已答（如 15）。
  final int answeredCount;

  /// 卷面总题数。
  final int totalCount;

  /// practice 累计答对；exam 交卷前为 null。
  final int? correctCount;

  /// exam 交卷得分；practice 为 null。
  final int? score;

  /// 断点：停在哪一题。
  final String? lastQuestionId;

  /// 累计用时毫秒。
  final int durationMs;

  /// 创建 / 最后更新毫秒时间戳。
  final int createdAt;
  final int updatedAt;

  /// 是否已同步服务端（本轮只落 false，保留 [AnswerRecordService.pendingSync]）。
  final bool synced;

  /// 服务端记录 id（同步后回填）。
  final String? serverId;

  bool get isCompletion => kind == 'completion';
  bool get isBreakpoint => kind == 'breakpoint';

  AnswerRecord copyWith({
    String? id,
    String? setId,
    String? setTitle,
    String? mode,
    String? kind,
    int? targetCount,
    int? answeredCount,
    int? totalCount,
    int? correctCount,
    int? score,
    String? lastQuestionId,
    int? durationMs,
    int? createdAt,
    int? updatedAt,
    bool? synced,
    String? serverId,
  }) {
    return AnswerRecord(
      id: id ?? this.id,
      setId: setId ?? this.setId,
      setTitle: setTitle ?? this.setTitle,
      mode: mode ?? this.mode,
      kind: kind ?? this.kind,
      targetCount: targetCount ?? this.targetCount,
      answeredCount: answeredCount ?? this.answeredCount,
      totalCount: totalCount ?? this.totalCount,
      correctCount: correctCount ?? this.correctCount,
      score: score ?? this.score,
      lastQuestionId: lastQuestionId ?? this.lastQuestionId,
      durationMs: durationMs ?? this.durationMs,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      synced: synced ?? this.synced,
      serverId: serverId ?? this.serverId,
    );
  }

  factory AnswerRecord.fromJson(Map<String, dynamic> json) {
    return AnswerRecord(
      id: json['id'] as String,
      setId: json['setId'] as String? ?? '',
      setTitle: json['setTitle'] as String? ?? '',
      mode: json['mode'] as String? ?? 'practice',
      kind: json['kind'] as String? ?? 'completion',
      targetCount: (json['targetCount'] as num?)?.toInt() ?? 0,
      answeredCount: (json['answeredCount'] as num?)?.toInt() ?? 0,
      totalCount: (json['totalCount'] as num?)?.toInt() ?? 0,
      correctCount: (json['correctCount'] as num?)?.toInt(),
      score: (json['score'] as num?)?.toInt(),
      lastQuestionId: json['lastQuestionId'] as String?,
      durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
      updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
      synced: json['synced'] as bool? ?? false,
      serverId: json['serverId'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'setId': setId,
      'setTitle': setTitle,
      'mode': mode,
      'kind': kind,
      'targetCount': targetCount,
      'answeredCount': answeredCount,
      'totalCount': totalCount,
      'correctCount': correctCount,
      'score': score,
      'lastQuestionId': lastQuestionId,
      'durationMs': durationMs,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'synced': synced,
      'serverId': serverId,
    };
  }

  @override
  String toString() =>
      'AnswerRecord($id, $setId/$mode/$kind, $answeredCount/$targetCount)';
}
