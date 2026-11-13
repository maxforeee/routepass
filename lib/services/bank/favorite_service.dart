/// 收藏服务抽象接口（规格文档第 4 章 §4.4.4）。
///
/// 服务的页面：答题页收藏按钮、收藏页、首页收藏预览卡。
/// 现在的实现是 Mock（带演示样例）；以后真实实现走
/// `GET /favorites`、`POST /favorites`、`DELETE /favorites/{qid}`。
library;

import '../../models/wrong_favorite.dart';

abstract class FavoriteService {
  /// 收藏题号列表（答题页判断收藏态用，不含时间戳）。
  Future<List<String>> getFavoriteIds();

  /// 带收藏时间的收藏条目列表（收藏页 / 首页今日预览算日期用）。
  ///
  /// 以后：GET /favorites（返回 §4.8.5 的 `favorites` 条目）。
  Future<List<Favorite>> getFavorites();

  /// Mock：本地内存切换。以后：POST /favorites / DELETE /favorites/{qid}。
  /// 同时写一条 favorite 操作进本地队列。
  Future<void> toggleFavorite(String questionId, bool on);
}
