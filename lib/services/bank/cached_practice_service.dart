/// PracticeService 的 cache-first 装饰器（F19）。
///
/// 抽题读路径：
/// 1. 先把本次会话已答 `excludedIds` 与本地 `attempts` 合并，排除已答；
/// 2. 本地 SQLite 题库命中即返回（断网也能继续练）；
/// 3. 本地题库为空时，用公开的 `/bank/questions` 分页拉真实题库并落库；
/// 4. 仍取不到才回退 `GET /practice/next`（当前实现为注入的 PracticeService）；
/// 5. 服务端抽到的题同样写回本地题库，下次优先本地。绝不编题。
///
/// 提交路径：仍由服务端判分（委托 [delegate]），成功后本地记一条
/// `attempts` 并把作答写入 `sync_queue`；后端同步接口就绪后 flush，
/// 读路径从不等待网络。
library;

import '../../models/practice.dart';
import '../../models/question.dart';
import 'local_cache_service.dart';
import 'practice_service.dart';
import 'question_bank_source.dart';

class CachedPracticeService implements PracticeService {
  CachedPracticeService({
    required this.delegate,
    required this.cache,
    this.bankSource,
  });

  final PracticeService delegate;
  final BankLocalCache cache;
  final BankQuestionBankSource? bankSource;

  @override
  Future<PracticeNext?> drawNextQuestion({
    required String setId,
    String? module,
    required Set<String> excludedIds,
  }) async {
    final localAnswered = await cache.answeredQuestionIds(setId);
    final excluded = <String>{...excludedIds, ...localAnswered};

    var cached = await cache.nextQuestion(
      setId: setId,
      module: module,
      excludedIds: excluded,
    );

    // 本地题库为空（首次使用 / 换设备）才拉公开题库；已缓存但抽尽时
    // 不再重复拉取，交给 /practice/next 兜底。
    final source = bankSource;
    if (cached == null && source != null && !await cache.hasQuestions(setId)) {
      try {
        final bank = await source.fetchQuestions(setId: setId, module: module);
        if (bank.isNotEmpty) {
          await cache.writeQuestions(setId: setId, questions: bank);
          cached = await cache.nextQuestion(
            setId: setId,
            module: module,
            excludedIds: excluded,
          );
        }
      } catch (_) {
        // 公开题库拉取失败不阻断：继续走 /practice/next 兜底。
      }
    }

    if (cached != null) {
      final session = await cache.sessionId(setId) ?? '';
      return PracticeNext(
        question: cached,
        sessionId: session,
        doneCount: excluded.length,
      );
    }

    final next = await delegate.drawNextQuestion(
      setId: setId,
      module: module,
      excludedIds: excluded,
    );
    if (next != null) {
      await cache.writeQuestions(
        setId: setId,
        questions: <Question>[next.question],
      );
      if (next.sessionId.isNotEmpty) {
        await cache.setSessionId(setId, next.sessionId);
      }
    }
    return next;
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
    final result = await delegate.submitAnswer(
      sessionId: sessionId,
      questionId: questionId,
      chosen: chosen,
      durationMs: durationMs,
      setId: setId,
      opId: opId,
      mode: mode,
    );

    // 判分成功才落本地作答；提交失败不写（与 F19 既有行为一致）。
    final localSetId = setId;
    if (localSetId != null && localSetId.isNotEmpty) {
      await cache.recordAttempt(
        setId: localSetId,
        questionId: questionId,
        chosen: chosen,
        correct: result.correct,
      );
      final createdAt = DateTime.now().millisecondsSinceEpoch;
      final localOpId = opId != null && opId.isNotEmpty
          ? opId
          : 'answer-$localSetId-$questionId-$createdAt';
      await cache.enqueueSync(
        LocalSyncOp(
          opId: localOpId,
          kind: LocalSyncOp.kindPracticeAnswer,
          createdAt: createdAt,
          payload: <String, Object?>{
            'setId': localSetId,
            'questionId': questionId,
            'chosen': chosen,
            'correct': result.correct,
            'durationMs': durationMs,
            'mode': mode ?? 'practice',
            'sessionId': sessionId,
          },
        ),
      );
    }
    return result;
  }

  @override
  Future<PracticeSession> startSession({
    required List<Question> questions,
    required String mode,
  }) => delegate.startSession(questions: questions, mode: mode);

  @override
  Future<ContinueSession?> resumeSession({required String setId}) =>
      delegate.resumeSession(setId: setId);

  @override
  Future<ContinueSession?> getContinueSession() =>
      delegate.getContinueSession();
}
