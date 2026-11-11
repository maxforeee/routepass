/// 知识库仓储抽象接口（规格文档第 4 章 §4.5.1）。
///
/// 服务的页面：知识库页 K-01–K-12、知识详情页 D-01–D-15、答题页关联知识点 chips。
/// 现在的实现是 Mock（样例章节/知识点）；以后真实实现走
/// `GET /knowledge/manifest`、`/knowledge/points`、`/knowledge/points/{id}`、
/// `/knowledge/points/{id}/questions`。
library;

import '../../models/knowledge_point.dart';

abstract class KnowledgeRepository {
  /// 章节列表（章→节两级，见 §4.8.3）。调用时机：进知识库页时 1 次。
  /// Mock：返回 2 个样例章节。以后：GET /knowledge/manifest + 本地 knowledge_points 聚合。
  Future<List<Chapter>> getChapters();

  /// 取一节下的知识点行。调用时机：用户点倒三角展开某一节时（同节单开手风琴，见第 3 章 §22.7）。
  /// Mock：返回该节的样例知识点。以后：GET /knowledge/points（按模块/章节分页）。
  Future<List<KnowledgePoint>> getPointsBySection(String sectionId);

  /// 知识点详情。调用时机：点知识点行进详情页时。
  /// Mock：返回样例详情（content_md 为样例文案）。以后：GET /knowledge/points/{id}（含正文）。
  Future<KnowledgePoint?> getPointDetail(String id);

  /// 按题目反查关联知识点（供答题页 chips）。Mock：返回空列表。以后：GET /knowledge/points/{id}/questions。
  Future<List<KnowledgePoint>> getPointsByQuestion(String questionId);

  /// 今日知识点（供首页 H-B7）。Mock：返回样例 1 条。以后：GET /knowledge/points?mode=daily。
  Future<KnowledgePoint?> getDailyPoint();
}
