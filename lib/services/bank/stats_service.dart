/// 学习统计服务抽象接口（规格文档第 4 章 §4.2 第 6 行、§4.3 H-B11）。
///
/// 服务的页面：首页 H-B11、统计页、今日完成摘要。
/// 现在的实现是 Mock（全 0）；以后真实实现走
/// `GET /stats/overview`、`/stats/by-module`、`/stats/daily`。
library;

import '../../models/stats.dart';

abstract class StatsService {
  /// 统计总览。Mock：全 0。以后：GET /stats/overview。
  Future<StatsOverview> getOverview();

  /// 按模块统计。Mock：各模块全 0。以后：GET /stats/by-module。
  Future<List<ModuleStat>> getByModule();

  /// 按日统计。Mock：空列表。以后：GET /stats/daily。
  Future<List<DailyStats>> getDaily();
}
