/// FavoriteService 的 Mock 实现（规格文档第 4 章 §4.4.4）。
///
/// Mock 只在内存里切换收藏态，不持久化、不发请求；另外预置 2 条演示
/// 收藏（今天的），供首页“收藏”预览卡排版展示，等后端接通后换成真实
/// 接口数据。
library;

import '../../models/wrong_favorite.dart';
import '../bank/favorite_service.dart';

class MockFavoriteService implements FavoriteService {
  MockFavoriteService() {
    _seedDemoFavorites();
  }

  /// 题号 → 收藏条目（按收藏先后插入）。
  final Map<String, Favorite> _favorites = <String, Favorite>{};

  /// 演示用收藏样例：只引用题库里已有的样例题（SAMPLE-10 / SAMPLE-20），
  /// 不编造题目内容；时间取“今天的前 1 / 3 小时”，保证任何日期跑起来都
  /// 落在当天。这是首页预览卡的排版演示数据，待真实收藏接口接上后删除。
  void _seedDemoFavorites() {
    final now = DateTime.now();
    const seeds = <String, int>{'SAMPLE-10': 1, 'SAMPLE-20': 3};
    seeds.forEach((id, hoursAgo) {
      _favorites[id] = Favorite(
        question_id: id,
        created_at: now
            .subtract(Duration(hours: hoursAgo))
            .millisecondsSinceEpoch,
      );
    });
  }

  @override
  Future<List<String>> getFavoriteIds() async {
    return _favorites.keys.toList();
  }

  @override
  Future<List<Favorite>> getFavorites() async {
    return _favorites.values.toList();
  }

  @override
  Future<void> toggleFavorite(String questionId, bool on) async {
    if (on) {
      _favorites[questionId] = Favorite(
        question_id: questionId,
        created_at: DateTime.now().millisecondsSinceEpoch,
      );
    } else {
      _favorites.remove(questionId);
    }
  }
}
