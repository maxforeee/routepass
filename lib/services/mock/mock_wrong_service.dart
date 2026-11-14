/// WrongService 的 Mock 实现（规格文档第 4 章 §4.4.4）。
///
/// Mock 只在内存里维护错题条目，不持久化；并预置 3 条演示错题（今天的），
/// 供首页“错题本”预览卡排版展示，等后端接通后换成真实接口数据。
library;

import '../../models/wrong_favorite.dart';
import '../bank/wrong_service.dart';

class MockWrongService implements WrongService {
  MockWrongService() {
    _seedDemoItems();
  }

  final List<WrongItem> _items = <WrongItem>[];

  /// 演示用错题样例：只引用题库里已有的样例题（SAMPLE-10 / 20 / 30），
  /// 不编造题目内容；last_wrong_at 取“今天的前 1–3 小时”。凌晨 0–3 点
  /// 跑起来时“前 N 小时”会跨过 0 点落到昨天，所以夹到今天 0 点之后，
  /// 保证条目始终算“今日新增”。这是首页预览卡的排版演示数据，待真实
  /// 错题接口接上后删除。
  void _seedDemoItems() {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    const seeds = <(String, int, int)>[
      ('SAMPLE-10', 2, 1),
      ('SAMPLE-20', 1, 2),
      ('SAMPLE-30', 1, 3),
    ];
    for (final (id, count, hoursAgo) in seeds) {
      final happenedAt = now.subtract(Duration(hours: hoursAgo));
      _items.add(
        WrongItem(
          question_id: id,
          wrong_count: count,
          last_wrong_at:
              (happenedAt.isBefore(startOfDay) ? startOfDay : happenedAt)
                  .millisecondsSinceEpoch,
          mastered: false,
        ),
      );
    }
  }

  @override
  Future<List<WrongItem>> getWrongBook({
    String? module,
    bool? masteredOnly,
  }) async {
    return _items
        .where((item) => item.removed_at == null)
        .where((item) => masteredOnly == null || item.mastered == masteredOnly)
        .toList();
  }

  @override
  Future<void> markMastered(String questionId) async {
    final index = _items.indexWhere((item) => item.question_id == questionId);
    if (index < 0) return;
    final item = _items[index];
    _items[index] = WrongItem(
      question_id: item.question_id,
      wrong_count: item.wrong_count,
      last_wrong_at: item.last_wrong_at,
      mastered: true,
      removed_at: item.removed_at,
    );
  }

  @override
  Future<void> removeWrong(
    String questionId, {
    String reason = 'user_removed',
  }) async {
    _items.removeWhere((item) => item.question_id == questionId);
  }
}
