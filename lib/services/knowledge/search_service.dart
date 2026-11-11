/// 知识库搜索服务抽象接口（规格文档第 4 章 §4.5.2）。
///
/// 服务的页面：知识库搜索页（路由 `/knowledge/search`）。
/// 现在的实现是 Mock（对样例数据做本地过滤）；以后真实实现走
/// `GET /knowledge/search`（本地 FTS5 为兜底）。
library;

import '../../models/search.dart';

abstract class SearchService {
  /// 搜索知识点与题目。调用时机：用户在搜索框输入后防抖 300ms 发起。
  /// Mock：只对样例数据做本地字符串过滤。以后：GET /knowledge/search，本地 FTS5 为断网兜底。
  /// 返回结果分两个区（知识点区 / 题目区），与第 3 章 §22.7 的搜索分区一致。
  Future<SearchResult> search(String keyword);
}
