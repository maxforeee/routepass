/// StatsService 的 Mock 实现（规格文档第 4 章 §4.2 第 6 行、§4.3 H-B11）。
///
/// Mock 全部返回 0 或空列表，不许编造学习数据。
library;

import '../../models/stats.dart';
import '../bank/stats_service.dart';

class MockStatsService implements StatsService {
  static const List<String> _modules = <String>[
    'VLAN',
    'OSPF',
    'ACL',
    'NAT',
    'SUBNET',
  ];

  @override
  Future<StatsOverview> getOverview() async {
    return StatsOverview(
      answeredTotal: 0,
      correctRate: 0.0,
      streakDays: 0,
      todayAnswered: 0,
      todayCorrect: 0,
    );
  }

  @override
  Future<List<ModuleStat>> getByModule() async {
    return _modules
        .map(
          (m) => ModuleStat(module: m, total: 0, answered: 0, correctRate: 0.0),
        )
        .toList();
  }

  @override
  Future<List<DailyStats>> getDaily() async {
    return <DailyStats>[];
  }
}
