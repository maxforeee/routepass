/// 样例数据加载器（规格文档第 4 章 §4.8.9）。
///
/// Mock 服务从 assets/data/ 下的 3 个样例 JSON 文件读数据，读一次后缓存在内存里。
/// 样例题 answer 为 []、explanation 为 ""，题干以“”开头，绝不含真实答案。
library;

import 'dart:convert';

import 'package:flutter/services.dart';

import '../../models/knowledge_point.dart';
import '../../models/question.dart';
import '../../models/toolbox.dart';

/// 样例知识库文件结构：{chapters, sections, points}。
class SampleKnowledge {
  const SampleKnowledge({
    required this.chapters,
    required this.sections,
    required this.points,
  });

  final List<Chapter> chapters;
  final List<Section> sections;
  final List<KnowledgePoint> points;
}

class SampleData {
  SampleData._();

  static List<Question>? _questions;
  static SampleKnowledge? _knowledge;
  static List<CliCommand>? _cliCommands;

  /// 3 道样例题（SAMPLE-10/20/30）。
  static Future<List<Question>> loadSampleQuestions() async {
    if (_questions != null) return _questions!;
    final raw = await rootBundle.loadString(
      'assets/data/sample_questions.json',
    );
    _questions = (jsonDecode(raw) as List<dynamic>)
        .map((e) => Question.fromJson(e as Map<String, dynamic>))
        .toList();
    return _questions!;
  }

  /// 样例章节/小节/知识点（2 章 2 节 2 条知识点）。
  static Future<SampleKnowledge> loadSampleKnowledge() async {
    if (_knowledge != null) return _knowledge!;
    final raw = await rootBundle.loadString(
      'assets/data/sample_knowledge.json',
    );
    final map = jsonDecode(raw) as Map<String, dynamic>;
    _knowledge = SampleKnowledge(
      chapters: (map['chapters'] as List<dynamic>)
          .map((e) => Chapter.fromJson(e as Map<String, dynamic>))
          .toList(),
      sections: (map['sections'] as List<dynamic>)
          .map((e) => Section.fromJson(e as Map<String, dynamic>))
          .toList(),
      points: (map['points'] as List<dynamic>)
          .map((e) => KnowledgePoint.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
    return _knowledge!;
  }

  /// 命令速查样例子集。
  static Future<List<CliCommand>> loadCliCommands() async {
    if (_cliCommands != null) return _cliCommands!;
    final raw = await rootBundle.loadString('assets/data/cli_commands.json');
    _cliCommands = (jsonDecode(raw) as List<dynamic>)
        .map((e) => CliCommand.fromJson(e as Map<String, dynamic>))
        .toList();
    return _cliCommands!;
  }
}
