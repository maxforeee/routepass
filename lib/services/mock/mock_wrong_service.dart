/// WrongService 的 Mock 实现（规格文档第 4 章 §4.4.4）。
///
/// Mock 返回空列表，错题本页显示第 3 章 §22.10 的空态。
library;

import '../../models/wrong_favorite.dart';
import '../bank/wrong_service.dart';

class MockWrongService implements WrongService {
  @override
  Future<List<WrongItem>> getWrongBook({
    String? module,
    bool? masteredOnly,
  }) async {
    return <WrongItem>[];
  }

  @override
  Future<void> markMastered(String questionId) async {
    // Mock：本地内存标记，不持久化；以后：POST /wrong-book/{qid}/master。
  }

  @override
  Future<void> removeWrong(
    String questionId, {
    String reason = 'user_removed',
  }) async {
    // Mock：本地移除；以后：DELETE /wrong-book/{qid}。
  }
}
