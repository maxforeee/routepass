/// 收藏服务抽象接口（规格文档第 4 章 §4.4.4）。
///
/// 服务的页面：答题页收藏按钮、收藏页。
/// 现在的实现是 Mock（空列表）；以后真实实现走
/// `GET /favorites`、`POST /favorites`、`DELETE /favorites/{qid}`。
library;

abstract class FavoriteService {
  /// Mock：返回空列表。以后：GET /favorites。
  Future<List<String>> getFavoriteIds();

  /// Mock：本地内存切换。以后：POST /favorites / DELETE /favorites/{qid}。
  /// 同时写一条 favorite 操作进本地队列。
  Future<void> toggleFavorite(String questionId, bool on);
}
