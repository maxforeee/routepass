/// PracticeService 的 Mock 实现（规格文档第 4 章 §4.4.2）。
///
/// 本地建会话、本地记一笔，不判对错；解析卡显示占位文案。
library;

import 'dart:convert';

import '../../core/kv_store.dart';
import '../../core/modules.dart';
import '../../core/service_locator.dart';
import '../../models/practice.dart';
import '../../models/question.dart';
import '../bank/practice_service.dart';
import 'sample_data.dart';

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
    String? setId,
    String? opId,
    String? mode,
  }) async {
    // Mock 不判对错：correct 恒为 null，解析卡只显示占位文案，不编造解析内容。
    return AnswerResult(correct: null, explanation: '样例数据，解析待后端接入');
  }

  /// F19：从 3 道样例题里按模块 / 排除 id 抽下一题；抽尽返回 null。
  @override
  Future<PracticeNext?> drawNextQuestion({
    required String setId,
    String? module,
    required Set<String> excludedIds,
  }) async {
    var questions = await SampleData.loadSampleQuestions();
    final targetModule = module ?? setId;
    if (kModuleOrder.contains(targetModule)) {
      questions = questions.where((q) => q.module == targetModule).toList();
    }
    for (final q in questions) {
      if (!excludedIds.contains(q.id)) {
        return PracticeNext(
          question: q,
          sessionId: 'MOCK-PRACTICE-10',
          doneCount: excludedIds.length,
        );
      }
    }
    return null;
  }

  @override
  Future<ContinueSession?> resumeSession({required String setId}) async {
    return null;
  }

  @override
  Future<ContinueSession?> getContinueSession() async {
    // 读答题页退出时写进 kv（home.continue）的进度指针；没有或解析失败返回 null，首页 H-B1 隐藏。
    final raw = ServiceLocator.kvStore.getString(KvStore.keyHomeContinue);
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return ContinueSession.fromJson(json);
    } catch (_) {
      return null;
    }
  }
}
