/// PracticeService 的 cache-first 装饰器（F19）。
///
/// 抽题读路径：
/// 1. 先把本次会话已答 `excludedIds` 与本地 `attempts` 合并，排除已答；
///    离线抽题再并入 kv 里的近 7 天已答集（F34 A12，sync.recent_answered），
///    该集抽尽本地池时回落按套排除，允许重抽旧题；
/// 2. 本地 SQLite 题库命中即返回（断网也能继续练）；
/// 3. 本地题库为空时，用公开的 `/bank/questions` 分页拉真实题库并落库；
/// 4. 仍取不到才回退 `GET /practice/next`（当前实现为注入的 PracticeService）；
/// 5. 服务端抽到的题同样写回本地题库，下次优先本地。绝不编题。
///
/// 提交路径：仍由服务端判分（委托 [delegate]），成功后本地记一条
/// `attempts` 并把作答写入 `sync_queue`；后端同步接口就绪后 flush，
/// 读路径从不等待网络。
library;

import '../../core/kv_store.dart';
import '../../models/practice.dart';
import '../../models/question.dart';
import 'local_cache_service.dart';
import 'practice_service.dart';
import 'question_bank_source.dart';
import 'sync_http_service.dart';

class CachedPracticeService implements PracticeService {
  CachedPracticeService({
    required this.delegate,
    required this.cache,
    this.bankSource,
    this.kv,
  });

  final PracticeService delegate;
  final BankLocalCache cache;
  final BankQuestionBankSource? bankSource;

  /// F34 (A12)：离线抽题的 7 天轮回排除集来源（kv 键 sync.recent_answered，
  /// 每次 sync pull 覆盖）。只存引用，抽题时现读，不在服务内缓存副本；
  /// 为 null 或从未同步时排除集为空，本地抽题保持旧行为。
  final KvStore? kv;

  /// F27 预测性预热：前置页在后台把 setId 的整套题库拉进本地缓存，
  /// 首题抽题（drawNextQuestion 冷缓存路径）不再等网络。与抽题共用同一
  /// 数据源与缓存键；已有缓存直接短路，失败静默（抽题时照常兜底）。
  /// 纯读 + 写缓存，不创建会话、不判分、不改已答集合。
  Future<void> warmQuestionBank({required String setId, String? module}) async {
    final source = bankSource;
    if (source == null || setId.isEmpty) return;
    if (await cache.hasQuestions(setId)) return;
    try {
      final bank = await source.fetchQuestions(setId: setId, module: module);
      if (bank.isNotEmpty) {
        await cache.writeQuestions(setId: setId, questions: bank);
      }
    } catch (_) {
      // 预热失败不阻断：抽题时走原有冷缓存 / /practice/next 兜底。
    }
  }

  @override
  Future<PracticeNext?> drawNextQuestion({
    required String setId,
    String? module,
    required Set<String> excludedIds,
    String? sessionId,
  }) async {
    final localAnswered = await cache.answeredQuestionIds(setId);
    final excluded = <String>{...excludedIds, ...localAnswered};
    // F34 (A12)：离线抽题并入近 7 天已答集（语义由后端 sync.recent_answered
    // 决定：counted_for_rotation 且 7 天内）。每次抽题现读 kv；在线抽题
    // 由服务端执行同一窗口，客户端不做额外过滤。
    final store = kv;
    final recent = store == null
        ? const <String>{}
        : HttpSyncService.recentAnsweredIds(store);
    final windowExcluded = recent.isEmpty
        ? excluded
        : <String>{...excluded, ...recent};
    final session = sessionId ?? await cache.sessionId(setId) ?? '';

    var cached = await cache.nextQuestion(
      setId: setId,
      module: module,
      excludedIds: windowExcluded,
    );
    // 7 天集把本地池抽尽时回落按套排除（允许重抽旧题），不留空抽。
    if (cached == null && recent.isNotEmpty) {
      cached = await cache.nextQuestion(
        setId: setId,
        module: module,
        excludedIds: excluded,
      );
    }

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
            excludedIds: windowExcluded,
          );
          if (cached == null && recent.isNotEmpty) {
            cached = await cache.nextQuestion(
              setId: setId,
              module: module,
              excludedIds: excluded,
            );
          }
        }
      } catch (_) {
        // 公开题库拉取失败不阻断：继续走 /practice/next 兜底。
      }
    }

    if (cached != null) {
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
      sessionId: session,
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
  Future<PracticeSessionInfo?> startPracticeSession({String? module}) =>
      delegate.startPracticeSession(module: module);

  @override
  Future<PracticeSessionInfo?> fetchPracticeSession(String sessionId) =>
      delegate.fetchPracticeSession(sessionId);

  @override
  Future<PracticeSessionInfo?> endPracticeSession(String sessionId) =>
      delegate.endPracticeSession(sessionId);

  @override
  Future<List<PracticeRecordSummary>> fetchPracticeRecords({
    int page = 1,
    int pageSize = 20,
  }) => delegate.fetchPracticeRecords(page: page, pageSize: pageSize);

  @override
  Future<PracticeRecordDetail?> getRecordDetail(String sessionId) =>
      delegate.getRecordDetail(sessionId);

  @override
  Future<bool> deleteRecord(String sessionId) =>
      delegate.deleteRecord(sessionId);

  @override
  Future<PracticeRecordPaper?> getRecordPaper(String sessionId) =>
      delegate.getRecordPaper(sessionId);

  @override
  Future<List<PracticeModuleProgress>> fetchPracticeProgress() =>
      delegate.fetchPracticeProgress();

  @override
  Future<ContinueSession?> resumeSession({required String setId}) =>
      delegate.resumeSession(setId: setId);

  @override
  Future<ContinueSession?> getContinueSession() =>
      delegate.getContinueSession();
}
