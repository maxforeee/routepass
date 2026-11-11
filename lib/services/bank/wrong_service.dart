/// 错题本服务抽象接口（规格文档第 4 章 §4.4.4）。
///
/// 服务的页面：首页 H-B6、错题本页。
/// 现在的实现是 Mock（空列表）；以后真实实现走
/// `GET /wrong-book`、`POST /wrong-book/{qid}/master`、`DELETE /wrong-book/{qid}`。
library;

import '../../models/wrong_favorite.dart';

abstract class WrongService {
  /// Mock：返回空列表，错题本页显示第 3 章 §22.10 的空态。以后：GET /wrong-book。
  Future<List<WrongItem>> getWrongBook({String? module, bool? masteredOnly});

  /// 用户在错题本点“已掌握”。Mock：本地内存标记，不持久化到同步队列以外的地方；
  /// 同时写一条 wrong_master 操作进本地队列。以后：POST /wrong-book/{qid}/master。
  /// 注意：wrong_add（又做错）必须把 mastered 置 false（v3.1 第 8 章，见 §4.8.7）。
  Future<void> markMastered(String questionId);

  /// 用户点“移除”。Mock：本地移除。以后：DELETE /wrong-book/{qid}。
  /// 只允许用户显式移除与题库更新失效两种触发（v3.1 第 8 章 wrong_remove 触发条件表）。
  Future<void> removeWrong(String questionId, {String reason = 'user_removed'});
}
