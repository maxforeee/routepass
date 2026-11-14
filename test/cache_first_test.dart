import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:routepass/core/local_db.dart';
import 'package:routepass/models/practice.dart';
import 'package:routepass/models/question.dart';
import 'package:routepass/models/stats.dart';
import 'package:routepass/services/bank/cached_practice_service.dart';
import 'package:routepass/services/bank/cached_question_repository.dart';
import 'package:routepass/services/bank/local_cache_service.dart';
import 'package:routepass/services/bank/practice_service.dart';
import 'package:routepass/services/bank/question_bank_source.dart';
import 'package:routepass/services/bank/question_repo.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Question _q(
  String id, {
  String module = 'VLAN',
  String type = 'single',
  List<String> answer = const <String>['A'],
}) {
  return Question(
    id: id,
    module: module,
    type: type,
    stem: '题干 $id',
    options: const <QuestionOption>[
      QuestionOption(key: 'A', text: 'A 选项'),
      QuestionOption(key: 'B', text: 'B 选项'),
      QuestionOption(key: 'C', text: 'C 选项'),
      QuestionOption(key: 'D', text: 'D 选项'),
    ],
    answer: answer,
    explanation: '解析 $id',
    knowledge_point_id: 'KP-1',
    difficulty: 1,
    set_no: 0,
    row_version: 1,
  );
}

BankSetOverview _overview({int done = 12, int total = 100}) {
  return BankSetOverview(
    setId: 'VLAN',
    total: total,
    done: done,
    remaining: total - done,
    byType: QuestionTypeStat(setId: 'VLAN', single: total - 20, multiple: 20),
  );
}

class _FakeQuestionRepository implements QuestionRepository {
  _FakeQuestionRepository({this.overview, this.fail = false});

  BankSetOverview? overview;
  bool fail;
  int overviewCalls = 0;

  @override
  Future<BankSetOverview?> getSetOverview({required String setId}) async {
    overviewCalls++;
    if (fail) throw Exception('offline');
    return overview;
  }

  @override
  Future<List<ModuleStat>> getModules() async => const <ModuleStat>[];

  @override
  Future<List<Question>> drawQuestions({
    required String mode,
    required int drawCount,
    String? module,
    String? knowledgePointId,
  }) async => const <Question>[];

  @override
  Future<Question?> getQuestionById(String id) async => null;

  @override
  Future<List<ModuleStat>> getSetModuleStats({required String setId}) async =>
      const <ModuleStat>[];
}

class _FakeOverviewSource implements BankSetOverviewSource {
  _FakeOverviewSource({this.overview, this.fail = false});

  BankSetOverview? overview;
  bool fail;
  int calls = 0;

  @override
  Future<BankSetOverview?> fetchOverview(String setId) async {
    calls++;
    if (fail) throw Exception('offline');
    return overview;
  }
}

class _FakeBankSource implements BankQuestionBankSource {
  _FakeBankSource(this.questions, {this.fail = false});

  List<Question> questions;
  bool fail;
  int calls = 0;

  @override
  Future<List<Question>> fetchQuestions({
    required String setId,
    String? module,
  }) async {
    calls++;
    if (fail) throw Exception('offline');
    return questions;
  }
}

class _FakePracticeService implements PracticeService {
  _FakePracticeService(this.questions, {this.failDraw = false});

  final List<Question> questions;
  bool failDraw;
  bool failSubmit = false;
  int drawCalls = 0;
  int submitCalls = 0;
  String submittedSetId = '';
  String submittedSessionId = '';
  String? lastDrawSessionId;

  @override
  Future<PracticeNext?> drawNextQuestion({
    required String setId,
    String? module,
    required Set<String> excludedIds,
    String? sessionId,
  }) async {
    drawCalls++;
    lastDrawSessionId = sessionId;
    if (failDraw) throw Exception('next failed');
    for (final q in questions) {
      if (module != null && q.module != module) continue;
      if (excludedIds.contains(q.id)) continue;
      return PracticeNext(question: q, sessionId: 'S-1', doneCount: 0);
    }
    return null;
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
    submitCalls++;
    submittedSetId = setId ?? '';
    submittedSessionId = sessionId;
    if (failSubmit) throw Exception('submit failed');
    return AnswerResult(
      correct: true,
      explanation: '解析',
      correctKeys: const <String>['A'],
      opId: opId,
    );
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
  Future<ContinueSession?> resumeSession({required String setId}) async => null;

  @override
  Future<ContinueSession?> getContinueSession() async => null;

  @override
  Future<PracticeSessionInfo?> startPracticeSession({String? module}) async =>
      null;

  @override
  Future<PracticeSessionInfo?> fetchPracticeSession(String sessionId) async =>
      null;

  @override
  Future<PracticeSessionInfo?> endPracticeSession(String sessionId) async =>
      null;

  @override
  Future<List<PracticeRecordSummary>> fetchPracticeRecords({
    int page = 1,
    int pageSize = 20,
  }) async => const <PracticeRecordSummary>[];

  @override
  Future<List<PracticeModuleProgress>> fetchPracticeProgress() async =>
      const <PracticeModuleProgress>[];
}

Future<void> _flushAsync() async {
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CachedQuestionRepository（前置页计数）', () {
    test('缓存未命中：拉服务端并写缓存，第二次直接命中', () async {
      final cache = InMemoryBankLocalCache();
      final repo = _FakeQuestionRepository(overview: _overview(done: 12));
      final cached = CachedQuestionRepository(
        delegate: repo,
        cache: cache,
        backgroundRefresh: false,
      );

      final first = await cached.getSetOverview(setId: 'VLAN');
      expect(first?.done, 12);
      expect(repo.overviewCalls, 1);
      expect((await cache.readOverview('VLAN'))?.done, 12);

      final second = await cached.getSetOverview(setId: 'VLAN');
      expect(second?.done, 12);
      expect(repo.overviewCalls, 1);
    });

    test('缓存命中：不发网络请求', () async {
      final cache = InMemoryBankLocalCache();
      await cache.writeOverview(_overview(done: 33));
      final repo = _FakeQuestionRepository(fail: true);
      final cached = CachedQuestionRepository(
        delegate: repo,
        cache: cache,
        backgroundRefresh: false,
      );

      final value = await cached.getSetOverview(setId: 'VLAN');
      expect(value?.done, 33);
      expect(value?.remaining, 67);
      expect(value?.byType?.single, 80);
      expect(repo.overviewCalls, 0);
    });

    test('缓存命中 + 离线：后台刷新失败也保留缓存值', () async {
      final cache = InMemoryBankLocalCache();
      await cache.writeOverview(_overview(done: 7));
      final source = _FakeOverviewSource(fail: true);
      final cached = CachedQuestionRepository(
        delegate: _FakeQuestionRepository(),
        cache: cache,
        overviewSource: source,
      );

      final value = await cached.getSetOverview(setId: 'VLAN');
      expect(value?.done, 7);
      await _flushAsync();
      expect((await cache.readOverview('VLAN'))?.done, 7);
    });

    test('无缓存 + 离线：返回 null，不编数字', () async {
      final cache = InMemoryBankLocalCache();
      final cached = CachedQuestionRepository(
        delegate: _FakeQuestionRepository(fail: true),
        cache: cache,
        backgroundRefresh: false,
      );

      expect(await cached.getSetOverview(setId: 'VLAN'), isNull);
      expect(await cache.readOverview('VLAN'), isNull);
    });

    test('概览接口未就绪（null）不覆盖缓存', () async {
      final cache = InMemoryBankLocalCache();
      await cache.writeOverview(_overview(done: 5));
      final source = _FakeOverviewSource();
      final cached = CachedQuestionRepository(
        delegate: _FakeQuestionRepository(),
        cache: cache,
        overviewSource: source,
      );

      expect((await cached.getSetOverview(setId: 'VLAN'))?.done, 5);
      await _flushAsync();
      expect((await cache.readOverview('VLAN'))?.done, 5);
      expect(source.calls, 1);
    });

    test('缓存命中后后台刷新成功：缓存更新，本次仍返回旧值', () async {
      final cache = InMemoryBankLocalCache();
      await cache.writeOverview(_overview(done: 7));
      final source = _FakeOverviewSource(overview: _overview(done: 70));
      final cached = CachedQuestionRepository(
        delegate: _FakeQuestionRepository(),
        cache: cache,
        overviewSource: source,
      );

      expect((await cached.getSetOverview(setId: 'VLAN'))?.done, 7);
      await _flushAsync();
      expect((await cache.readOverview('VLAN'))?.done, 70);

      final next = await cached.getSetOverview(setId: 'VLAN');
      expect(next?.done, 70);
    });
  });

  group('CachedPracticeService（逐题抽题）', () {
    test('本地命中：不调用服务端抽题，且排除已答', () async {
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
      final delegate = _FakePracticeService(const <Question>[]);
      final service = CachedPracticeService(delegate: delegate, cache: cache);

      final next = await service.drawNextQuestion(
        setId: 'VLAN',
        excludedIds: const <String>{},
      );
      expect(next?.question.id, 'VLAN-2');
      expect(delegate.drawCalls, 0);
    });

    test('本地为空：从公开题库拉取并落库，再本地抽题', () async {
      final cache = InMemoryBankLocalCache();
      final source = _FakeBankSource(<Question>[_q('VLAN-1'), _q('VLAN-2')]);
      final delegate = _FakePracticeService(const <Question>[], failDraw: true);
      final service = CachedPracticeService(
        delegate: delegate,
        cache: cache,
        bankSource: source,
      );

      final next = await service.drawNextQuestion(
        setId: 'VLAN',
        excludedIds: const <String>{},
      );
      expect(next?.question.id, 'VLAN-1');
      expect(source.calls, 1);
      expect(delegate.drawCalls, 0);
      expect(await cache.hasQuestions('VLAN'), isTrue);

      final second = await service.drawNextQuestion(
        setId: 'VLAN',
        excludedIds: const <String>{'VLAN-1'},
      );
      expect(second?.question.id, 'VLAN-2');
      expect(source.calls, 1, reason: '已有本地题库不重复拉取');
    });

    test('题库拉取失败：回退服务端抽题，结果写回本地', () async {
      final cache = InMemoryBankLocalCache();
      final source = _FakeBankSource(const <Question>[], fail: true);
      final delegate = _FakePracticeService(<Question>[_q('VLAN-9')]);
      final service = CachedPracticeService(
        delegate: delegate,
        cache: cache,
        bankSource: source,
      );

      final next = await service.drawNextQuestion(
        setId: 'VLAN',
        excludedIds: const <String>{},
      );
      expect(next?.question.id, 'VLAN-9');
      expect(next?.sessionId, 'S-1');
      expect(delegate.drawCalls, 1);
      expect(await cache.hasQuestions('VLAN'), isTrue);
    });

    test('S11 sessionId：本地题库抽题沿用，回退时透传给 /practice/next', () async {
      final cache = InMemoryBankLocalCache();
      final delegate = _FakePracticeService(<Question>[_q('VLAN-9')]);
      final service = CachedPracticeService(delegate: delegate, cache: cache);
      await cache.writeQuestions(
        setId: 'VLAN',
        questions: <Question>[_q('VLAN-1')],
      );

      final cachedNext = await service.drawNextQuestion(
        setId: 'VLAN',
        excludedIds: const <String>{},
        sessionId: 'sess-passed',
      );
      expect(cachedNext?.question.id, 'VLAN-1');
      expect(cachedNext?.sessionId, 'sess-passed');
      expect(delegate.drawCalls, 0);

      final fallbackNext = await service.drawNextQuestion(
        setId: 'OSPF',
        excludedIds: const <String>{},
        sessionId: 'sess-passed',
      );
      expect(fallbackNext?.question.id, 'VLAN-9');
      expect(delegate.lastDrawSessionId, 'sess-passed');
    });

    test('本地抽尽：回退服务端；服务端也没有则返回 null（不编题）', () async {
      final cache = InMemoryBankLocalCache();
      await cache.writeQuestions(
        setId: 'VLAN',
        questions: <Question>[_q('VLAN-1')],
      );
      await cache.recordAttempt(
        setId: 'VLAN',
        questionId: 'VLAN-1',
        chosen: const <String>['A'],
        correct: false,
      );
      final delegate = _FakePracticeService(<Question>[]);
      final service = CachedPracticeService(delegate: delegate, cache: cache);

      expect(
        await service.drawNextQuestion(
          setId: 'VLAN',
          excludedIds: const <String>{},
        ),
        isNull,
      );
      expect(delegate.drawCalls, 1);
    });

    test('缓存与服务端都失败：抛异常，不返回假题', () async {
      final cache = InMemoryBankLocalCache();
      final delegate = _FakePracticeService(const <Question>[], failDraw: true);
      final service = CachedPracticeService(delegate: delegate, cache: cache);

      await expectLater(
        service.drawNextQuestion(setId: 'VLAN', excludedIds: const <String>{}),
        throwsA(isA<Exception>()),
      );
    });

    test('服务端会话 id 缓存后，本地抽题沿用它', () async {
      final cache = InMemoryBankLocalCache();
      await cache.writeQuestions(
        setId: 'VLAN',
        questions: <Question>[_q('VLAN-1')],
      );
      await cache.setSessionId('VLAN', 'S-7');
      final service = CachedPracticeService(
        delegate: _FakePracticeService(const <Question>[]),
        cache: cache,
      );

      final next = await service.drawNextQuestion(
        setId: 'VLAN',
        excludedIds: const <String>{},
      );
      expect(next?.question.id, 'VLAN-1');
      expect(next?.sessionId, 'S-7');
    });
  });

  group('CachedPracticeService（作答与同步队列）', () {
    test('判分成功：本地记 attempts + 入同步队列，flush 前一直 pending', () async {
      final cache = InMemoryBankLocalCache();
      final delegate = _FakePracticeService(const <Question>[]);
      final service = CachedPracticeService(delegate: delegate, cache: cache);

      final result = await service.submitAnswer(
        sessionId: 'S-1',
        questionId: 'VLAN-1',
        chosen: const <String>['A'],
        durationMs: 1200,
        setId: 'VLAN',
        opId: 'op-1',
        mode: 'practice',
      );
      expect(result.correct, isTrue);
      expect(delegate.submitCalls, 1);

      final attempt = cache.attemptFor('VLAN', 'VLAN-1');
      expect(attempt?.chosen, <String>['A']);
      expect(attempt?.correct, isTrue);
      expect(await cache.answeredQuestionIds('VLAN'), contains('VLAN-1'));

      final pending = await cache.pendingSync();
      expect(pending.length, 1);
      expect(pending.single.opId, 'op-1');
      expect(pending.single.kind, LocalSyncOp.kindPracticeAnswer);
      expect(pending.single.payload['questionId'], 'VLAN-1');

      await cache.markSyncOpSynced('op-1');
      expect(await cache.pendingSync(), isEmpty);
    });

    test('提交失败：不写 attempts、不入队（保持既有行为）', () async {
      final cache = InMemoryBankLocalCache();
      final delegate = _FakePracticeService(const <Question>[])
        ..failSubmit = true;
      final service = CachedPracticeService(delegate: delegate, cache: cache);

      await expectLater(
        service.submitAnswer(
          sessionId: 'S-1',
          questionId: 'VLAN-1',
          chosen: const <String>['A'],
          durationMs: 1200,
          setId: 'VLAN',
        ),
        throwsA(isA<Exception>()),
      );
      expect(cache.attemptFor('VLAN', 'VLAN-1'), isNull);
      expect(await cache.pendingSync(), isEmpty);
    });

    test('没有 setId（错题本 / 每日一练）不写本地题库队列', () async {
      final cache = InMemoryBankLocalCache();
      final service = CachedPracticeService(
        delegate: _FakePracticeService(const <Question>[]),
        cache: cache,
      );

      await service.submitAnswer(
        sessionId: 'S-1',
        questionId: 'VLAN-1',
        chosen: const <String>['A'],
        durationMs: 10,
      );
      expect(await cache.pendingSync(), isEmpty);
      expect(await cache.answeredQuestionIds(''), isEmpty);
    });
  });

  group('SqliteBankLocalCache（真实 SQLite）', () {
    late SqfliteLocalDatabase db;
    late SqliteBankLocalCache cache;

    setUpAll(sqfliteFfiInit);

    setUp(() {
      db = SqfliteLocalDatabase(
        dbPath: inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      );
      cache = SqliteBankLocalCache(db);
    });

    tearDown(() => db.close());

    test('overview 读写（含 byType）', () async {
      expect(await cache.readOverview('VLAN'), isNull);
      await cache.writeOverview(_overview(done: 42));
      final value = await cache.readOverview('VLAN');
      expect(value?.done, 42);
      expect(value?.remaining, 58);
      expect(value?.byType?.single, 80);
      expect(value?.byType?.multiple, 20);
    });

    test('overview 无题型分布（S11 progress）读写后 byType 仍为 null', () async {
      await cache.writeOverview(
        const BankSetOverview(
          setId: 'OSPF',
          total: 100,
          done: 12,
          remaining: 88,
        ),
      );
      final value = await cache.readOverview('OSPF');
      expect(value?.done, 12);
      expect(value?.remaining, 88);
      expect(value?.byType, isNull, reason: '不能把未知题型写成 0');
    });

    test('题库读取：module 过滤 + 排除已答', () async {
      await cache.writeQuestions(
        setId: 'VLAN',
        questions: <Question>[
          _q('VLAN-1'),
          _q('OSPF-1', module: 'OSPF'),
        ],
      );
      expect(await cache.hasQuestions('VLAN'), isTrue);
      expect(
        (await cache.nextQuestion(
          setId: 'VLAN',
          excludedIds: const <String>{},
        ))?.id,
        'VLAN-1',
      );
      expect(
        await cache.nextQuestion(
          setId: 'VLAN',
          module: 'ACL',
          excludedIds: const <String>{},
        ),
        isNull,
      );
      await cache.recordAttempt(
        setId: 'VLAN',
        questionId: 'VLAN-1',
        chosen: const <String>['A'],
        correct: true,
      );
      expect(await cache.answeredQuestionIds('VLAN'), <String>{'VLAN-1'});
      expect(
        (await cache.nextQuestion(
          setId: 'VLAN',
          excludedIds: await cache.answeredQuestionIds('VLAN'),
        ))?.id,
        'OSPF-1',
      );
    });

    test('作答与同步队列持久化，标记后不再返回', () async {
      await cache.recordAttempt(
        setId: 'VLAN',
        questionId: 'VLAN-1',
        chosen: const <String>['A', 'C'],
        correct: false,
      );
      await cache.enqueueSync(
        LocalSyncOp(
          opId: 'op-1',
          kind: LocalSyncOp.kindPracticeAnswer,
          payload: const <String, Object?>{'questionId': 'VLAN-1'},
          createdAt: 100,
        ),
      );
      await cache.enqueueSync(
        LocalSyncOp(
          opId: 'op-1',
          kind: LocalSyncOp.kindPracticeAnswer,
          payload: const <String, Object?>{'questionId': 'VLAN-1'},
          createdAt: 100,
        ),
      );

      final pending = await cache.pendingSync();
      expect(pending.length, 1, reason: 'op_id 幂等');
      expect(pending.single.payload['questionId'], 'VLAN-1');

      await cache.markSyncOpSynced('op-1');
      expect(await cache.pendingSync(), isEmpty);
    });

    test('会话 id 读写', () async {
      expect(await cache.sessionId('VLAN'), isNull);
      await cache.setSessionId('VLAN', 'S-9');
      expect(await cache.sessionId('VLAN'), 'S-9');
      await cache.setSessionId('VLAN', 'S-10');
      expect(await cache.sessionId('VLAN'), 'S-10');
    });
  });

  group('HTTP 题库/概览数据源', () {
    Map<String, dynamic> apiQuestion(int i) => <String, dynamic>{
      'id': 'VLAN-${i.toString().padLeft(4, '0')}',
      'module': 'VLAN',
      'type': 'single',
      'difficulty': 2,
      'stem': '题干 $i',
      'options': <String>['A 选项', 'B 选项', 'C 选项', 'D 选项'],
      'answer': <int>[1],
      'explanation': '解析 $i',
      'knowledgePointId': 'KP-VLAN-01',
      'relatedKnowledgeIds': <String>[],
      'rowVersion': 3,
    };

    test('分页拉取 + 字段映射（options/answer/知识点）', () async {
      final requested = <String>[];
      final client = MockClient((request) async {
        requested.add(request.url.toString());
        final page = int.parse(request.url.queryParameters['page'] ?? '1');
        expect(request.url.queryParameters['module'], 'VLAN');
        final all = <Map<String, dynamic>>[
          for (var i = 1; i <= 21; i++) apiQuestion(i),
        ];
        final slice = all.skip((page - 1) * 20).take(20).toList();
        return http.Response(
          jsonEncode(<String, Object?>{
            'questions': slice,
            'page': page,
            'pageSize': 20,
            'total': all.length,
          }),
          200,
          headers: const <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      });
      final source = HttpBankQuestionBankSource(
        client: client,
        baseUrl: 'http://example.test',
      );

      final questions = await source.fetchQuestions(
        setId: 'VLAN',
        module: 'VLAN',
      );
      expect(questions.length, 21);
      expect(requested.length, 2);
      final first = questions.first;
      expect(first.id, 'VLAN-0001');
      expect(first.module, 'VLAN');
      expect(first.options.map((o) => o.key), <String>['A', 'B', 'C', 'D']);
      expect(first.answer, <String>['B']);
      expect(first.knowledge_point_id, 'KP-VLAN-01');
      expect(first.row_version, 3);
      expect(first.explanation, '解析 1');
    });

    test('overview 404 = 接口未就绪，返回 null', () async {
      final source = HttpBankSetOverviewSource(
        client: MockClient(
          (_) async => http.Response('{"detail":"Not Found"}', 404),
        ),
        baseUrl: 'http://example.test',
      );
      expect(await source.fetchOverview('VLAN'), isNull);
    });

    test('overview 200 解析为 BankSetOverview', () async {
      final source = HttpBankSetOverviewSource(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode(<String, Object?>{
              'setId': 'VLAN',
              'total': 100,
              'done': 30,
              'remaining': 70,
              'byType': <String, Object?>{'single': 80, 'multiple': 20},
            }),
            200,
          ),
        ),
        baseUrl: 'http://example.test',
      );
      final value = await source.fetchOverview('VLAN');
      expect(value?.done, 30);
      expect(value?.remaining, 70);
      expect(value?.byType?.single, 80);
    });
  });
}
