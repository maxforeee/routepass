// 字段名必须与规格文档 §4.8 数据契约一字不差（snake_case），故忽略本 lint。
// ignore_for_file: non_constant_identifier_names
/// 考试会话与考试结果模型（规格文档第 4 章 §4.8.6 与 §4.4.3；
/// 客户端表 `exam_sessions`）。
///
/// 字段名与 §4.8.6 数据契约一字不差；Mock 数据必须符合同一契约，
/// 不许编造契约之外的字段（§4.8.9）。
library;

import 'question.dart' show QuestionOption;

/// 考试快照的单题条目（§4.8.6 `snapshot`，v3.1 D9）。
///
/// 契约形状 `{stem, options, answer, analysis}`：开考时持久化，
/// 交卷按快照判分，会话中途不混用内容版本。**Mock 的快照 `answer`
/// 一律为空数组 `[]`**。
class ExamSnapshot {
  const ExamSnapshot({
    required this.stem,
    required this.options,
    required this.answer,
    required this.analysis,
  });

  /// 题干。
  final String stem;

  /// 选项列表，每项 `{key, text}`。
  final List<QuestionOption> options;

  /// 正确答案 key 列表。**Mock 恒为空数组 `[]`**。
  final List<String> answer;

  /// 解析（对应题目契约里的 explanation 在快照中的别名）。
  final String analysis;

  factory ExamSnapshot.fromJson(Map<String, dynamic> json) {
    return ExamSnapshot(
      stem: json['stem'] as String,
      options: (json['options'] as List<dynamic>)
          .map((e) => QuestionOption.fromJson(e as Map<String, dynamic>))
          .toList(),
      answer: (json['answer'] as List<dynamic>).cast<String>(),
      analysis: json['analysis'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'stem': stem,
      'options': options.map((e) => e.toJson()).toList(),
      'answer': answer,
      'analysis': analysis,
    };
  }

  @override
  String toString() => 'ExamSnapshot(${stem.length} chars)';
}

/// 考试会话（§4.8.6，客户端表 `exam_sessions`）。
///
/// **Mock 规则：`score` 一律为 `null`（不计分，交卷按空答案处理，
/// 页面显示“样例考试，不计分”），绝不许用 Mock 的假答案算出一个假分数**
/// （§4.4.3）。
class ExamSession {
  const ExamSession({
    required this.id,
    required this.started_at,
    required this.total,
    required this.detail,
    required this.snapshot,
    this.submitted_at,
    this.duration_ms,
    this.score,
    this.passed,
    this.correct,
  });

  /// 场次 id（服务端生成；Mock 用 `"MOCK-EXAM-10"` 样式本地编号）。
  final String id;

  /// 开考时刻的毫秒时间戳。
  final int started_at;

  /// 交卷时刻的毫秒时间戳；未交卷时为 `null`。
  final int? submitted_at;

  /// 考试用时毫秒；未交卷时为 `null`。
  final int? duration_ms;

  /// 考试得分。**Mock 的 `score` 一律为 `null`（不计分）**；接后端后由
  /// 服务端按快照判分返回。
  final int? score;

  /// 是否通过；未判分时为 `null`。
  final bool? passed;

  /// 考试总题数（契约默认 100）。
  final int total;

  /// 答对题数；未判分时为 `null`。
  final int? correct;

  /// 逐题结果（契约类型：JSON 字符串）。
  final String detail;

  /// 考试快照 `{stem, options, answer, analysis}` 列表（契约类型 JSONB，
  /// 客户端表里持久化为 JSON 文本）：开考时持久化，交卷按快照判分；
  /// **Mock 的快照 `answer` 为空数组**。
  final List<ExamSnapshot> snapshot;

  factory ExamSession.fromJson(Map<String, dynamic> json) {
    return ExamSession(
      id: json['id'] as String,
      started_at: json['started_at'] as int,
      submitted_at: json['submitted_at'] as int?,
      duration_ms: json['duration_ms'] as int?,
      score: json['score'] as int?,
      passed: json['passed'] as bool?,
      total: json['total'] as int? ?? 100,
      correct: json['correct'] as int?,
      detail: json['detail'] as String,
      snapshot: (json['snapshot'] as List<dynamic>? ?? const [])
          .map((e) => ExamSnapshot.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'started_at': started_at,
      'submitted_at': submitted_at,
      'duration_ms': duration_ms,
      'score': score,
      'passed': passed,
      'total': total,
      'correct': correct,
      'detail': detail,
      'snapshot': snapshot.map((e) => e.toJson()).toList(),
    };
  }

  @override
  String toString() => 'ExamSession($id, total: $total)';
}

/// 考试结果（§4.4.3 `ExamService.submitExam` 返回 `{score, passed, detail}`）。
///
/// **Mock 规则：`score` 一律为 `null`（不计分），绝不许用 Mock 的假答案
/// 算出一个假分数**；页面显示“样例考试，不计分”。
class ExamResult {
  const ExamResult({
    required this.score,
    required this.passed,
    required this.detail,
  });

  /// 考试得分；**Mock 恒为 `null`（不计分）**。
  final int? score;

  /// 是否通过；未判分时为 `null`。
  final bool? passed;

  /// 逐题结果（契约类型：JSON 字符串）。
  final String detail;

  factory ExamResult.fromJson(Map<String, dynamic> json) {
    return ExamResult(
      score: json['score'] as int?,
      passed: json['passed'] as bool?,
      detail: json['detail'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'score': score,
      'passed': passed,
      'detail': detail,
    };
  }

  @override
  String toString() => 'ExamResult(score: $score)';
}
