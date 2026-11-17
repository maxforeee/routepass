/// 7 天轮回 Mock 兜底（F28）：诚实空态，绝不编题、编解锁时间、编分数。
///
/// 抽题返回空抽（无会话、无题、无解锁时间），UI 显示「轮回待接口」；
/// 判分 / 结算没有本地依据，直接抛 [RotationServiceException]，由 UI
/// 提示重试——不拿假判分冒充服务端结果。
library;

import '../../models/question.dart';
import '../bank/rotation_service.dart';

class MockRotationService implements RotationService {
  @override
  Future<RotationDraw> draw({required String bankId, int count = 20}) async {
    return const RotationDraw(
      sessionId: null,
      questions: <Question>[],
      totalCount: 0,
      drawnShort: true,
      message: '轮回待接口',
    );
  }

  @override
  Future<RotationAnswer> answer({
    required String sessionId,
    required String questionId,
    required List<int> chosen,
    required String opId,
  }) async {
    throw const RotationServiceException('轮回判分不可用');
  }

  @override
  Future<RotationResult> submit({
    required String sessionId,
    required String opId,
  }) async {
    throw const RotationServiceException('轮回结算不可用');
  }
}
