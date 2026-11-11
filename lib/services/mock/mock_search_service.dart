/// SearchService 的 Mock 实现（规格文档第 4 章 §4.5.2）。
///
/// 只对样例数据做本地字符串过滤；空关键词返回空结果。
library;

import '../../models/search.dart';
import '../knowledge/search_service.dart';
import 'sample_data.dart';

class MockSearchService implements SearchService {
  @override
  Future<SearchResult> search(String keyword) async {
    final key = keyword.trim();
    if (key.isEmpty) {
      return SearchResult(knowledgePoints: [], questions: []);
    }
    final data = await SampleData.loadSampleKnowledge();
    final questions = await SampleData.loadSampleQuestions();
    return SearchResult(
      knowledgePoints: data.points
          .where((p) => p.title.contains(key) || p.summary.contains(key))
          .toList(),
      questions: questions.where((q) => q.stem.contains(key)).toList(),
    );
  }
}
