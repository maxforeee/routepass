/// KnowledgeRepository 的 Mock 实现（规格文档第 4 章 §4.5.1）。
///
/// 只返回 assets 里的样例章节/知识点；按题目反查关联知识点返回空列表。
library;

import '../../models/knowledge_point.dart';
import '../knowledge/knowledge_repo.dart';
import 'sample_data.dart';

class MockKnowledgeRepository implements KnowledgeRepository {
  @override
  Future<List<Chapter>> getChapters() async {
    final data = await SampleData.loadSampleKnowledge();
    return data.chapters;
  }

  @override
  Future<List<KnowledgePoint>> getPointsBySection(String sectionId) async {
    final data = await SampleData.loadSampleKnowledge();
    Section? section;
    for (final s in data.sections) {
      if (s.id == sectionId) section = s;
    }
    if (section == null) return <KnowledgePoint>[];
    Chapter? chapter;
    for (final c in data.chapters) {
      if (c.id == section.chapterId) chapter = c;
    }
    if (chapter == null) return <KnowledgePoint>[];
    // Mock 简化：同一章的知识点按模块归属返回。
    final String module = chapter.module;
    return data.points.where((p) => p.module == module).toList();
  }

  @override
  Future<KnowledgePoint?> getPointDetail(String id) async {
    final data = await SampleData.loadSampleKnowledge();
    for (final p in data.points) {
      if (p.id == id) return p;
    }
    return null;
  }

  @override
  Future<List<KnowledgePoint>> getPointsByQuestion(
    String questionId,
  ) async {
    // Mock：返回空列表，答题页 chips 区域隐藏。
    return <KnowledgePoint>[];
  }

  @override
  Future<KnowledgePoint?> getDailyPoint() async {
    final data = await SampleData.loadSampleKnowledge();
    if (data.points.isEmpty) return null;
    return data.points.first;
  }
}
