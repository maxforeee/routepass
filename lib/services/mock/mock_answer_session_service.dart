/// AnswerSessionService 的测试 / 本地装配实现（F19）。
///
/// 进行态仍基于 ServiceLocator.kvStore（测试为 InMemoryKvStore，生产为
/// shared_preferences），行为与 [KvAnswerSessionService] 完全一致。
library;

import '../bank/answer_session_service.dart';

class MockAnswerSessionService extends KvAnswerSessionService {
  MockAnswerSessionService();
}
