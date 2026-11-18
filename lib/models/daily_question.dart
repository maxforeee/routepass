/// 每日一练题目模型（首页 UI 方案 §11）。
///
/// 每日一练从真实全库随机抽单选题（F17），自带正确答案；与主库
/// [Question] 契约不同，所以单独建模。解析来自后端 `explanation`，
/// 可空——为空时 UI 不显示解析，不编造文案。
library;

import 'question.dart';

/// 一道每日一练题（单选，解析可空）。
class DailyQuestion {
  const DailyQuestion({
    required this.id,
    required this.stem,
    required this.options,
    required this.correctKey,
    this.explanation,
  });

  /// 题目 id（如 `"DAILY-001"`）。
  final String id;

  /// 题干。
  final String stem;

  /// 选项（A–D，复用主库的 [QuestionOption] 形状 `{key, text}`）。
  final List<QuestionOption> options;

  /// 正确选项的 key（如 `"B"`）。
  final String correctKey;

  /// 解析（后端 `explanation`；null/空串表示该题没有解析）。
  final String? explanation;

  factory DailyQuestion.fromJson(Map<String, dynamic> json) {
    return DailyQuestion(
      id: json['id'] as String,
      stem: json['stem'] as String,
      options: (json['options'] as List<dynamic>)
          .map((e) => QuestionOption.fromJson(e as Map<String, dynamic>))
          .toList(),
      correctKey: json['correctKey'] as String,
      explanation: json['explanation'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'stem': stem,
      'options': options.map((e) => e.toJson()).toList(),
      'correctKey': correctKey,
      'explanation': explanation,
    };
  }

  @override
  String toString() => 'DailyQuestion($id)';
}
