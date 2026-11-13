/// 每日一练题目模型（首页 UI 方案 §11）。
///
/// 每日一练走单独的题库：主库 300 道题的 [Question] 按契约把 Mock 的
/// `answer` 留空、`explanation` 留空，判不了对错；每日一练是固定知识点题，
/// 自带一个正确答案且不带解析，所以单独建模，不复用主库题目。
library;

import 'question.dart';

/// 一道每日一练题（单选，无解析）。
class DailyQuestion {
  const DailyQuestion({
    required this.id,
    required this.stem,
    required this.options,
    required this.correctKey,
  });

  /// 题目 id（如 `"DAILY-001"`）。
  final String id;

  /// 题干。
  final String stem;

  /// 选项（A–D，复用主库的 [QuestionOption] 形状 `{key, text}`）。
  final List<QuestionOption> options;

  /// 正确选项的 key（如 `"B"`）。
  final String correctKey;

  factory DailyQuestion.fromJson(Map<String, dynamic> json) {
    return DailyQuestion(
      id: json['id'] as String,
      stem: json['stem'] as String,
      options: (json['options'] as List<dynamic>)
          .map((e) => QuestionOption.fromJson(e as Map<String, dynamic>))
          .toList(),
      correctKey: json['correctKey'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'stem': stem,
      'options': options.map((e) => e.toJson()).toList(),
      'correctKey': correctKey,
    };
  }

  @override
  String toString() => 'DailyQuestion($id)';
}
