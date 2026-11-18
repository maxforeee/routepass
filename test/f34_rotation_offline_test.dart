import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/core/kv_store.dart';
import 'package:routepass/models/practice.dart';
import 'package:routepass/models/question.dart';
import 'package:routepass/services/bank/cached_practice_service.dart';
import 'package:routepass/services/bank/local_cache_service.dart';
import 'package:routepass/services/bank/practice_service.dart';
import 'package:routepass/services/bank/question_bank_source.dart';

Question _q(String id, {String module = 'VLAN'}) {
  return Question(
    id: id,
    module: module,
    type: 'single',
    stem: '题干 $id',
    options: const <QuestionOption>[
      QuestionOption(key: 'A', text: 'A 选项'),
      QuestionOption(key: 'B', text: 'B 选项'),
      QuestionOption(key: 'C', text: 'C 选项'),
      QuestionOption(key: 'D', text: 'D 选项'),
    ],
    answer: const <String>['A'],
    explanation: '解析 $id',
    knowledge_point_id: 'KP-1',
    difficulty: 1,
    set_no: 0,
    row_version: 1,
  );
}

/// 记录型 delegate：只关心抽题调用次数与收到的 excludedIds（在线路径
/// 由服务端执行 7 天窗口，客户端不得额外过滤）。其余方法给无害默认值。
class _RecordingPracticeService implements PracticeService {
  _RecordingPracticeService(this.questions);

  final List<Question> questions;
  int drawCalls = 0;
  Set<String>? lastExcludedIds;

  @override
  Future<PracticeNext?> drawNextQuestion({
    required String setId,
    String? module,
    required Set<String> excludedIds,
    String? sessionId,
  }) async {
    drawCalls++;
    lastExcludedIds = Set<String>.of(excludedIds);
    for (final q in questions) {
      if (module != null && q.module != module) continue;
      if (excludedIds.contains(q.id)) continue;
      return PracticeNext(question: q, sessionId: 'S-1', doneCount: 0);
    }
    return null;
  }

  @override
  Future<PracticeSession> startSession({
    required List<Question> questions,
    required String mode,
  }) async => PracticeSession(
    id: 'S-1',
    questions: questions,
    mode: mode,
    total: questions.length,
  );

  @override
  Future<AnswerResult> submitAnswer({
    required String sessionId,
    required String questionId,
    required List<String> chosen,
    required int durationMs,
    String? setId,
    String? opId,
    String? mode,
  }) async => const AnswerResult(
    correct: null,
    explanation: '',
    correctKeys: <String>[],
    opId: null,
  );

  @override
  Future<ContinueSession?> getContinueSession() async => null;
}

class _FakeBankSource implements BankQuestionBankSource {
  _FakeBankSource(this.questions);

  final List<Question> questions;
  int calls = 0;

  @override
  Future<List<Question>> fetchQuestions({
    required String setId,
    String? module,
  }) async {
    calls++;
    return questions;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('F34 A12：离线抽题并入 7 天轮回排除集', () {
    test('离线抽题跳过 recent_answered 里的题', () async {
      final cache = InMemoryBankLocalCache();
      await cache.writeQuestions(
        setId: 'VLAN',
        questions: <Question>[_q('VLAN-1'), _q('VLAN-2')],
      );
      final kv = InMemoryKvStore();
      kv.setStringList(KvStore.keySyncRecentAnswered, <String>['VLAN-1']);
      final delegate = _RecordingPracticeService(const <Question>[]);
      final service = CachedPracticeService(
        delegate: delegate,
        cache: cache,
        kv: kv,
      );

      final next = await service.drawNextQuestion(
        setId: 'VLAN',
        excludedIds: const <String>{},
      );
      expect(next?.question.id, 'VLAN-2');
      expect(delegate.drawCalls, 0, reason: '本地命中不走服务端');
    });

    test('从未同步（空集）：保持旧行为', () async {
      final cache = InMemoryBankLocalCache();
      await cache.writeQuestions(
        setId: 'VLAN',
        questions: <Question>[_q('VLAN-1'), _q('VLAN-2')],
      );
      final delegate = _RecordingPracticeService(const <Question>[]);
      final service = CachedPracticeService(
        delegate: delegate,
        cache: cache,
        kv: InMemoryKvStore(),
      );

      final next = await service.drawNextQuestion(
        setId: 'VLAN',
        excludedIds: const <String>{},
      );
      expect(next?.question.id, 'VLAN-1');
    });

    test('未注入 kv：保持旧行为', () async {
      final cache = InMemoryBankLocalCache();
      await cache.writeQuestions(
        setId: 'VLAN',
        questions: <Question>[_q('VLAN-1'), _q('VLAN-2')],
      );
      final service = CachedPracticeService(
        delegate: _RecordingPracticeService(const <Question>[]),
        cache: cache,
      );

      final next = await service.drawNextQuestion(
        setId: 'VLAN',
        excludedIds: const <String>{},
      );
      expect(next?.question.id, 'VLAN-1');
    });

    test('7 天集覆盖整个本地池：回落按套排除，重抽旧题而不是空抽', () async {
      final cache = InMemoryBankLocalCache();
      await cache.writeQuestions(
        setId: 'VLAN',
        questions: <Question>[_q('VLAN-1'), _q('VLAN-2')],
      );
      final kv = InMemoryKvStore();
      kv.setStringList(KvStore.keySyncRecentAnswered, <String>[
        'VLAN-1',
        'VLAN-2',
      ]);
      final delegate = _RecordingPracticeService(const <Question>[]);
      final service = CachedPracticeService(
        delegate: delegate,
        cache: cache,
        kv: kv,
      );

      final next = await service.drawNextQuestion(
        setId: 'VLAN',
        excludedIds: const <String>{},
      );
      expect(next, isNotNull, reason: '不能把用户留在空抽上');
      expect(next?.question.id, 'VLAN-1');
      expect(delegate.drawCalls, 0, reason: '回落在本地完成，不惊动服务端');
    });

    test('回落仍尊重按套排除：本地已答的题不重抽', () async {
      final cache = InMemoryBankLocalCache();
      await cache.writeQuestions(
        setId: 'VLAN',
        questions: <Question>[_q('VLAN-1'), _q('VLAN-2')],
      );
      await cache.recordAttempt(
        setId: 'VLAN',
        questionId: 'VLAN-1',
        chosen: const <String>['A'],
        correct: true,
      );
      final kv = InMemoryKvStore();
      kv.setStringList(KvStore.keySyncRecentAnswered, <String>[
        'VLAN-1',
        'VLAN-2',
      ]);
      final service = CachedPracticeService(
        delegate: _RecordingPracticeService(const <Question>[]),
        cache: cache,
        kv: kv,
      );

      final next = await service.drawNextQuestion(
        setId: 'VLAN',
        excludedIds: const <String>{},
      );
      expect(next?.question.id, 'VLAN-2');
    });

    test('按套排除与 7 天集取并集', () async {
      final cache = InMemoryBankLocalCache();
      await cache.writeQuestions(
        setId: 'VLAN',
        questions: <Question>[_q('VLAN-1'), _q('VLAN-2'), _q('VLAN-3')],
      );
      await cache.recordAttempt(
        setId: 'VLAN',
        questionId: 'VLAN-1',
        chosen: const <String>['A'],
        correct: false,
      );
      final kv = InMemoryKvStore();
      kv.setStringList(KvStore.keySyncRecentAnswered, <String>['VLAN-2']);
      final service = CachedPracticeService(
        delegate: _RecordingPracticeService(const <Question>[]),
        cache: cache,
        kv: kv,
      );

      final next = await service.drawNextQuestion(
        setId: 'VLAN',
        excludedIds: const <String>{},
      );
      expect(next?.question.id, 'VLAN-3');
    });

    test('每次抽题现读 kv：同步刷新后立即生效', () async {
      final cache = InMemoryBankLocalCache();
      await cache.writeQuestions(
        setId: 'VLAN',
        questions: <Question>[_q('VLAN-1'), _q('VLAN-2'), _q('VLAN-3')],
      );
      final kv = InMemoryKvStore();
      final service = CachedPracticeService(
        delegate: _RecordingPracticeService(const <Question>[]),
        cache: cache,
        kv: kv,
      );

      final first = await service.drawNextQuestion(
        setId: 'VLAN',
        excludedIds: const <String>{},
      );
      expect(first?.question.id, 'VLAN-1');

      // 模拟一次 sync pull 覆盖 kv 里的 7 天集。
      kv.setStringList(KvStore.keySyncRecentAnswered, <String>[
        'VLAN-1',
        'VLAN-2',
      ]);
      final second = await service.drawNextQuestion(
        setId: 'VLAN',
        excludedIds: const <String>{'VLAN-1'},
      );
      expect(second?.question.id, 'VLAN-3', reason: '服务内不得缓存旧副本');
    });

    test('在线兜底路径不做客户端窗口过滤', () async {
      final cache = InMemoryBankLocalCache();
      final kv = InMemoryKvStore();
      kv.setStringList(KvStore.keySyncRecentAnswered, <String>[
        'VLAN-9',
        'OTHER-1',
      ]);
      final delegate = _RecordingPracticeService(<Question>[_q('VLAN-9')]);
      final service = CachedPracticeService(
        delegate: delegate,
        cache: cache,
        kv: kv,
      );

      final next = await service.drawNextQuestion(
        setId: 'VLAN',
        excludedIds: const <String>{'SESS-1'},
      );
      expect(delegate.drawCalls, 1);
      expect(
        delegate.lastExcludedIds,
        <String>{'SESS-1'},
        reason: '7 天窗口由服务端执行，客户端只传按套排除',
      );
      expect(next?.question.id, 'VLAN-9', reason: '服务端抽到的题照常采纳');
    });

    test('冷缓存拉取后同样执行 7 天排除', () async {
      final cache = InMemoryBankLocalCache();
      final source = _FakeBankSource(<Question>[_q('VLAN-1'), _q('VLAN-2')]);
      final kv = InMemoryKvStore();
      kv.setStringList(KvStore.keySyncRecentAnswered, <String>['VLAN-1']);
      final delegate = _RecordingPracticeService(const <Question>[]);
      final service = CachedPracticeService(
        delegate: delegate,
        cache: cache,
        bankSource: source,
        kv: kv,
      );

      final next = await service.drawNextQuestion(
        setId: 'VLAN',
        excludedIds: const <String>{},
      );
      expect(next?.question.id, 'VLAN-2');
      expect(source.calls, 1);
      expect(delegate.drawCalls, 0);
    });

    test('冷缓存拉取后整池被 7 天集覆盖：回落按套排除', () async {
      final cache = InMemoryBankLocalCache();
      final source = _FakeBankSource(<Question>[_q('VLAN-1'), _q('VLAN-2')]);
      final kv = InMemoryKvStore();
      kv.setStringList(KvStore.keySyncRecentAnswered, <String>[
        'VLAN-1',
        'VLAN-2',
      ]);
      final delegate = _RecordingPracticeService(const <Question>[]);
      final service = CachedPracticeService(
        delegate: delegate,
        cache: cache,
        bankSource: source,
        kv: kv,
      );

      final next = await service.drawNextQuestion(
        setId: 'VLAN',
        excludedIds: const <String>{},
      );
      expect(next, isNotNull);
      expect(next?.question.id, 'VLAN-1');
      expect(delegate.drawCalls, 0);
    });
  });
}
