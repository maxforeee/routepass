// 字段名必须与规格文档 §4.8 数据契约一字不差（snake_case），故忽略本 lint。
// ignore_for_file: non_constant_identifier_names
/// 搜索结果模型（规格文档第 4 章 §4.8 数据契约；全局搜索页）。
///
/// 复用已有的知识点（§4.8.2）与题目（§4.8.1）模型，字段名与数据契约
/// 一字不差。
library;

import 'package:routepass/models/knowledge_point.dart';
import 'package:routepass/models/question.dart';

/// 全局搜索结果：命中知识点 + 命中题目两部分。
class SearchResult {
  const SearchResult({required this.knowledgePoints, required this.questions});

  /// 命中的知识点列表。
  final List<KnowledgePoint> knowledgePoints;

  /// 命中的题目列表。
  final List<Question> questions;

  factory SearchResult.fromJson(Map<String, dynamic> json) {
    return SearchResult(
      knowledgePoints: (json['knowledgePoints'] as List<dynamic>)
          .map((e) => KnowledgePoint.fromJson(e as Map<String, dynamic>))
          .toList(),
      questions: (json['questions'] as List<dynamic>)
          .map((e) => Question.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'knowledgePoints': knowledgePoints.map((e) => e.toJson()).toList(),
      'questions': questions.map((e) => e.toJson()).toList(),
    };
  }

  @override
  String toString() =>
      'SearchResult(${knowledgePoints.length} kps, ${questions.length} questions)';
}
