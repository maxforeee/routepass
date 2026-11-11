/// PracticeService 的 Mock 实现（规格文档第 4 章 §4.4.2）。
///
/// 本地建会话、本地记一笔，不判对错；解析卡显示占位文案。
library;

import '../../models/practice.dart';
import '../../models/question.dart';
import '../bank/practice_service.dart';

class MockPracticeService implements PracticeService {
  @override
  Future<PracticeSession> startSession({
    required List<Question> questions,
    required String mode,
  }) async {
    return PracticeSession(
      id: 'MOCK-PRACTICE-10',
      questions: questions,
      mode: mode,
      total: questions.length,
    );
  }

  @override
  Future<AnswerResult> submitAnswer({
    required String sessionId,
    required String questionId,
    required List<String> chosen,
    required int durationMs,
  }) async {
    // Mock 不判对错：correct 恒为 null，解析卡只显示占位文案，不编造解析内容。
    return AnswerResult(
      correct: null,
      explanation: '样例数据，解析待后端接入',
    );
  }

  @override
  Future<ContinueSession?> getContinueSession() async {
    // Mock 无未完成会话，首页 H-B1 继续学习方块隐藏。
    return null;
  }
}
