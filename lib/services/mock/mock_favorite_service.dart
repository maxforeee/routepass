/// FavoriteService 的 Mock 实现（规格文档第 4 章 §4.4.4）。
///
/// Mock 只在内存里切换收藏态，不持久化、不发请求。
library;

import '../bank/favorite_service.dart';

class MockFavoriteService implements FavoriteService {
  final Set<String> _ids = <String>{};

  @override
  Future<List<String>> getFavoriteIds() async {
    return _ids.toList();
  }

  @override
  Future<void> toggleFavorite(String questionId, bool on) async {
    if (on) {
      _ids.add(questionId);
    } else {
      _ids.remove(questionId);
    }
  }
}
