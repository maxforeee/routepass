/// AnswerRecordService 的测试 / 本地装配实现（F19）。
///
/// 记录仍基于 ServiceLocator.kvStore（测试为 InMemoryKvStore，生产为
/// shared_preferences），行为与 [KvAnswerRecordService] 完全一致。
library;

import '../bank/answer_record_service.dart';

class MockAnswerRecordService extends KvAnswerRecordService {
  MockAnswerRecordService();
}
