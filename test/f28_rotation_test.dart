// F28：7 天轮回前端接线（F23 缺口 A12）。
//
// 契约测试（MockClient 直连 HttpRotationService）：
// - POST /practice/draw 解析：满抽 / 空抽（next_unlock_at + message）/ 短抽；
// - POST /sessions/{id}/answers 解析（is_correct / answer 下标转 key / 解析）；
// - POST /sessions/{id}/submit 解析（含 deleted: true 的空会话删除）；
// - 失败回落 MockRotationService（诚实空态，不编题 / 不编分解锁时间）。
//
// recent_answered：SyncPullPage 解析 + HttpSyncService 落 kv + 登出清除。
//
// widget 链：前置页「7天轮回」入口 → 抽题 → 逐题服务端判分 → 结算复用
// 全屏评分页；空抽 / 清单不可用显示诚实待接口态；判分失败不涂红绿；
// 0 题退出删除空会话、>=1 题退出即结算。
//
// 回归：既有练习仍走 GET /practice/next（HTTP 层 + widget 层双断言），
// 轮回流程绝不触碰 /practice/next 与 /practice/submit。
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:routepass/core/kv_store.dart';
import 'package:routepass/core/theme.dart';
import 'package:routepass/models/bank_manifest.dart';
import 'package:routepass/models/practice.dart';
import 'package:routepass/models/question.dart';
import 'package:routepass/models/stats.dart';
import 'package:routepass/models/sync.dart';
import 'package:routepass/pages/bank/answer_widgets.dart';
import 'package:routepass/pages/bank/exam_score_page.dart';
import 'package:routepass/pages/bank/quiz_page.dart';
import 'package:routepass/pages/bank/set_detail_page.dart';
import 'package:routepass/router/app_router.dart';
import 'package:routepass/services/bank/answer_record_service.dart';
import 'package:routepass/services/bank/answer_session_service.dart';
import 'package:routepass/services/bank/bank_manifest_service.dart';
import 'package:routepass/services/bank/practice_service.dart';
import 'package:routepass/services/bank/question_repo.dart';
import 'package:routepass/services/bank/rotation_service.dart';
import 'package:routepass/services/bank/sync_http_service.dart';
import 'package:routepass/services/mock/mock_bank_manifest_service.dart';
import 'package:routepass/services/mock/mock_rotation_service.dart';

const String _base = 'http://example.test';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: const <String, String>{
    'content-type': 'application/json; charset=utf-8',
  },
);

/// /practice/draw 的题目投影：不含 answer / explanation（判分只来自服务端）。
Map<String, Object?> _drawQuestionJson(String id) => <String, Object?>{
  'id': id,
  'module': 'VLAN',
  'type': 'single',
  'difficulty': 1,
  'stem': '题干 $id',
  'options': <Map<String, Object?>>[
    <String, Object?>{'key': 'A', 'text': '选项 A'},
    <String, Object?>{'key': 'B', 'text': '选项 B'},
    <String, Object?>{'key': 'C', 'text': '选项 C'},
    <String, Object?>{'key': 'D', 'text': '选项 D'},
  ],
};

/// 轮回批次的客户端题目（无答案键、无解析——与服务端抽题一致）。
Question _rotationQuestion(int index) {
  return Question(
    id: 'VLAN-${index.toString().padLeft(4, '0')}',
    module: 'VLAN',
    type: 'single',
    stem: '题干 $index',
    options: const <QuestionOption>[
      QuestionOption(key: 'A', text: 'A 选项'),
      QuestionOption(key: 'B', text: 'B 选项'),
      QuestionOption(key: 'C', text: 'C 选项'),
      QuestionOption(key: 'D', text: 'D 选项'),
    ],
    answer: const <String>[],
    explanation: '',
    knowledge_point_id: '',
    difficulty: 1,
    set_no: 0,
    row_version: 0,
  );
}

String _keyOf(int index) => String.fromCharCode('A'.codeUnitAt(0) + index);

bool _sameIndices(List<int> a, List<int> b) {
  final sortedA = List<int>.of(a)..sort();
  final sortedB = List<int>.of(b)..sort();
  if (sortedA.length != sortedB.length) return false;
  for (var i = 0; i < sortedA.length; i++) {
    if (sortedA[i] != sortedB[i]) return false;
  }
  return true;
}

/// 可控轮回服务 fake：记录调用与幂等键，判分 / 结算按服务端语义返回。
class _RotationFake implements RotationService {
  _RotationFake({
    required this.questions,
    this.emptyDraw = false,
    this.shortDraw = false,
    this.failAnswer = false,
  });

  final List<Question> questions;
  final bool emptyDraw;
  final bool shortDraw;
  final bool failAnswer;

  int drawCalls = 0;
  int answerCalls = 0;
  int submitCalls = 0;
  String? drawnBankId;
  int? drawnCount;
  String? submittedSessionId;
  final List<String> opIds = <String>[];
  final Map<String, List<int>> chosenByQuestion = <String, List<int>>{};

  /// 每题正确答案（0 基下标）；缺省 A。
  final Map<String, List<int>> correctAnswers = <String, List<int>>{};

  static const String sessionId = 'ps_20261117_0001';

  @override
  Future<RotationDraw> draw({required String bankId, int count = 20}) async {
    drawCalls++;
    drawnBankId = bankId;
    drawnCount = count;
    if (emptyDraw) {
      return RotationDraw(
        sessionId: null,
        questions: const <Question>[],
        totalCount: 0,
        drawnShort: true,
        nextUnlockAt: DateTime.parse('2026-11-18T09:00:00+08:00'),
        message: '当前题库的题都在 7 天轮回中，稍后陆续解锁',
      );
    }
    final batch = shortDraw ? questions.take(1).toList() : questions;
    return RotationDraw(
      sessionId: sessionId,
      questions: batch,
      totalCount: batch.length,
      drawnShort: shortDraw,
      nextUnlockAt: shortDraw
          ? DateTime.parse('2026-11-18T09:00:00+08:00')
          : null,
      message: shortDraw ? '可抽题不足，已抽取 ${batch.length} 道' : null,
    );
  }

  @override
  Future<RotationAnswer> answer({
    required String sessionId,
    required String questionId,
    required List<int> chosen,
    required String opId,
  }) async {
    answerCalls++;
    opIds.add(opId);
    if (failAnswer) throw const RotationServiceException('判分 500');
    chosenByQuestion[questionId] = chosen;
    final correct = correctAnswers[questionId] ?? const <int>[0];
    return RotationAnswer(
      isCorrect: _sameIndices(chosen, correct),
      answer: correct.map(_keyOf).toList(),
      explanation: '服务端解析',
    );
  }

  @override
  Future<RotationResult> submit({
    required String sessionId,
    required String opId,
  }) async {
    submitCalls++;
    submittedSessionId = sessionId;
    opIds.add(opId);
    if (chosenByQuestion.isEmpty) {
      // 服务端语义：0 题已答 → 删除会话，没有成绩。
      return const RotationResult(
        correctCount: 0,
        wrongCount: 0,
        score: null,
        detail: <RotationDetailItem>[],
        deleted: true,
      );
    }
    final detail = <RotationDetailItem>[];
    var correctCount = 0;
    for (final q in questions) {
      final chosen = chosenByQuestion[q.id];
      if (chosen == null) continue;
      final correct = correctAnswers[q.id] ?? const <int>[0];
      final isCorrect = _sameIndices(chosen, correct);
      if (isCorrect) correctCount++;
      detail.add(
        RotationDetailItem(
          questionId: q.id,
          isCorrect: isCorrect,
          answer: correct.map(_keyOf).toList(),
          chosen: chosen.map(_keyOf).toList(),
          explanation: '服务端解析',
        ),
      );
    }
    final answered = detail.length;
    return RotationResult(
      correctCount: correctCount,
      wrongCount: answered - correctCount,
      score: (correctCount * 100 / answered).round(),
      detail: detail,
      deleted: false,
    );
  }
}

/// 清单不可用（fetchManifest 抛错）：轮回必须显示「轮回待接口」。
class _BrokenManifestFake implements BankManifestService {
  @override
  Future<BankManifest> fetchManifest() async => throw Exception('manifest 500');
}

/// 前置页最小仓储 fake：动态区块全走「待接口」，不影响入口测试。
class _RepoFake implements QuestionRepository {
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

  @override
  Future<BankSetOverview?> getSetOverview({required String setId}) async =>
      null;
}

/// 既有练习服务探针：轮回流程里 drawNextQuestion / submitAnswer 必须 0 次。
class _PracticeSpy implements PracticeService {
  int drawCalls = 0;
  int submitCalls = 0;

  @override
  Future<PracticeNext?> drawNextQuestion({
    required String setId,
    String? module,
    required Set<String> excludedIds,
    String? sessionId,
  }) async {
    drawCalls++;
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
    throw StateError('轮回流程不得调用 /practice/submit');
  }

  @override
  Future<PracticeSession> startSession({
    required List<Question> questions,
    required String mode,
  }) async => PracticeSession(
    id: '',
    questions: questions,
    mode: mode,
    total: questions.length,
  );

  // 轮回流程不会用到以下接口：与 PracticeService 默认实现一致的无害桩，
  // 不抛错不断言，避免测试误报。
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
  Future<PracticeRecordDetail?> getRecordDetail(String sessionId) async => null;

  @override
  Future<bool> deleteRecord(String sessionId) async => false;

  @override
  Future<PracticeRecordPaper?> getRecordPaper(String sessionId) async => null;

  @override
  Future<List<PracticeModuleProgress>> fetchPracticeProgress() async =>
      const <PracticeModuleProgress>[];

  @override
  Future<ContinueSession?> resumeSession({required String setId}) async => null;

  @override
  Future<ContinueSession?> getContinueSession() async => null;
}

Widget _host(Widget page) {
  return MaterialApp(
    theme: AppTheme.light,
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () =>
                Navigator.of(context)
                    .push(MaterialPageRoute<void>(builder: (_) => page)),
            child: const Text('launch'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _launch(WidgetTester tester, Widget page) async {
  await tester.pumpWidget(_host(page));
  await tester.tap(find.text('launch'));
  await tester.pumpAndSettle();
}

List<OptionTileState> _states(WidgetTester tester) => tester
    .widgetList<OptionTile>(find.byType(OptionTile))
    .map((t) => t.state)
    .toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HttpRotationService.draw（真实契约解析）', () {
    test('满抽：session_id / 题目（无答案）/ total_count，请求带 bank_id 与 Bearer', () async {
      Map<String, dynamic>? sentBody;
      String? auth;
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/v1/practice/draw');
        sentBody = jsonDecode(request.body) as Map<String, dynamic>;
        auth = request.headers['Authorization'];
        return _json(<String, Object?>{
          'session_id': 'ps_20261117_0001',
          'bank_id': 'bank_test',
          'questions': <Map<String, Object?>>[
            _drawQuestionJson('VLAN-0001'),
            _drawQuestionJson('VLAN-0002'),
          ],
          'total_count': 2,
          'drawn_short': false,
        });
      });
      final service = HttpRotationService(
        client: client,
        baseUrl: _base,
        tokenProvider: () => 'tok',
      );
      final draw = await service.draw(bankId: 'bank_test');
      expect(sentBody!['bank_id'], 'bank_test');
      expect(sentBody!['count'], 20);
      expect(auth, 'Bearer tok');
      expect(draw.sessionId, 'ps_20261117_0001');
      expect(draw.questions, hasLength(2));
      expect(draw.questions.first.id, 'VLAN-0001');
      // 抽题不含答案：判分只来自服务端，客户端不得本地猜对错。
      expect(draw.questions.first.answer, isEmpty);
      expect(draw.totalCount, 2);
      expect(draw.drawnShort, isFalse);
      expect(draw.isEmpty, isFalse);
      expect(draw.nextUnlockAt, isNull);
      expect(draw.message, isNull);
    });

    test('空抽：session_id null + next_unlock_at + 服务端文案', () async {
      final client = MockClient((request) async {
        return _json(<String, Object?>{
          'session_id': null,
          'bank_id': 'bank_test',
          'questions': <Map<String, Object?>>[],
          'total_count': 0,
          'drawn_short': true,
          'next_unlock_at': '2026-11-18T09:00:00+08:00',
          'message': '当前题库的题都在 7 天轮回中，稍后陆续解锁',
        });
      });
      final service = HttpRotationService(client: client, baseUrl: _base);
      final draw = await service.draw(bankId: 'bank_test');
      expect(draw.isEmpty, isTrue);
      expect(draw.sessionId, isNull);
      expect(draw.questions, isEmpty);
      expect(draw.drawnShort, isTrue);
      expect(draw.nextUnlockAt, DateTime.parse('2026-11-18T09:00:00+08:00'));
      expect(draw.message, '当前题库的题都在 7 天轮回中，稍后陆续解锁');
    });

    test('短抽：有多少题跑多少题，保留服务端 message 与解锁时间', () async {
      final client = MockClient((request) async {
        return _json(<String, Object?>{
          'session_id': 'ps_20261117_0002',
          'bank_id': 'bank_test',
          'questions': <Map<String, Object?>>[_drawQuestionJson('VLAN-0001')],
          'total_count': 1,
          'drawn_short': true,
          'next_unlock_at': '2026-11-18T09:00:00+08:00',
          'message': '可抽题不足，已抽取 1 道',
        });
      });
      final service = HttpRotationService(client: client, baseUrl: _base);
      final draw = await service.draw(bankId: 'bank_test');
      expect(draw.isEmpty, isFalse);
      expect(draw.questions, hasLength(1));
      expect(draw.drawnShort, isTrue);
      expect(draw.message, '可抽题不足，已抽取 1 道');
      expect(draw.nextUnlockAt, isNotNull);
    });

    test('失败回落 Mock：诚实空态（轮回待接口），不编题不编解锁时间', () async {
      final client = MockClient(
        (request) async => _json(<String, Object?>{}, 404),
      );
      final service = HttpRotationService(
        client: client,
        baseUrl: _base,
        fallback: MockRotationService(),
      );
      final draw = await service.draw(bankId: 'bank_test');
      expect(draw.isEmpty, isTrue);
      expect(draw.message, '轮回待接口');
      expect(draw.nextUnlockAt, isNull);
      expect(draw.questions, isEmpty);
      // 判分 / 结算没有本地依据：Mock 抛诚实异常，由 UI 提示重试。
      expect(
        () => service.answer(
          sessionId: 'ps_1',
          questionId: 'VLAN-0001',
          chosen: const <int>[0],
          opId: 'op-1',
        ),
        throwsA(isA<RotationServiceException>()),
      );
    });
  });

  group('HttpRotationService.answer / submit（真实契约解析）', () {
    test(
      '单题判分：is_correct / answer 下标转 key / explanation，camelCase 上传',
      () async {
        Map<String, dynamic>? sentBody;
        final client = MockClient((request) async {
          expect(request.url.path, '/api/v1/sessions/ps_20261117_0001/answers');
          sentBody = jsonDecode(request.body) as Map<String, dynamic>;
          return _json(<String, Object?>{
            'is_correct': false,
            'answer': <int>[1],
            'explanation': '正确答案是 B',
          });
        });
        final service = HttpRotationService(client: client, baseUrl: _base);
        final result = await service.answer(
          sessionId: 'ps_20261117_0001',
          questionId: 'VLAN-0001',
          chosen: const <int>[0],
          opId: 'op-1',
        );
        expect(sentBody!['questionId'], 'VLAN-0001');
        expect(sentBody!['answer'], <int>[0]);
        expect(sentBody!['opId'], 'op-1');
        expect(result.isCorrect, isFalse);
        expect(result.answer, <String>['B']);
        expect(result.explanation, '正确答案是 B');
      },
    );

    test('结算：correct_count / wrong_count / score / detail 下标转 key', () async {
      Map<String, dynamic>? sentBody;
      final client = MockClient((request) async {
        expect(request.url.path, '/api/v1/sessions/ps_20261117_0001/submit');
        sentBody = jsonDecode(request.body) as Map<String, dynamic>;
        return _json(<String, Object?>{
          'correct_count': 1,
          'wrong_count': 1,
          'score': 50,
          'detail': <Map<String, Object?>>[
            <String, Object?>{
              'question_id': 'VLAN-0001',
              'is_correct': true,
              'answer': <int>[0],
              'chosen': <int>[0],
              'explanation': '解析一',
            },
            <String, Object?>{
              'question_id': 'VLAN-0002',
              'is_correct': false,
              'answer': <int>[1],
              'chosen': <int>[2],
              'explanation': null,
            },
          ],
          'deleted': false,
        });
      });
      final service = HttpRotationService(client: client, baseUrl: _base);
      final result = await service.submit(
        sessionId: 'ps_20261117_0001',
        opId: 'op-2',
      );
      expect(sentBody!['opId'], 'op-2');
      expect(result.correctCount, 1);
      expect(result.wrongCount, 1);
      expect(result.score, 50);
      expect(result.deleted, isFalse);
      expect(result.detail, hasLength(2));
      expect(result.detail.first.answer, <String>['A']);
      expect(result.detail.first.chosen, <String>['A']);
      expect(result.detail.last.answer, <String>['B']);
      expect(result.detail.last.chosen, <String>['C']);
      expect(result.detail.last.explanation, '');
    });

    test('0 题已答：deleted true + score null + 空明细，不编 0 分', () async {
      final client = MockClient((request) async {
        return _json(<String, Object?>{
          'correct_count': 0,
          'wrong_count': 0,
          'score': null,
          'detail': <Map<String, Object?>>[],
          'deleted': true,
        });
      });
      final service = HttpRotationService(client: client, baseUrl: _base);
      final result = await service.submit(sessionId: 'ps_1', opId: 'op-3');
      expect(result.deleted, isTrue);
      expect(result.score, isNull);
      expect(result.detail, isEmpty);
    });
  });

  group('recent_answered（离线 7 天视图）', () {
    test('SyncPullPage 解析扁平 questionId 数组；缺失字段为空列表', () {
      final page = SyncPullPage.fromJson(<String, dynamic>{
        'changes': <dynamic>[],
        'nextCursor': 0,
        'watermark': 5,
        'hasMore': false,
        'baselineRequired': false,
        'recent_answered': <String>['VLAN-0001', 'OSPF-0002'],
      });
      expect(page.recentAnswered, <String>['VLAN-0001', 'OSPF-0002']);
      final legacy = SyncPullPage.fromJson(<String, dynamic>{
        'changes': <dynamic>[],
        'nextCursor': 0,
        'watermark': 5,
        'hasMore': false,
        'baselineRequired': false,
      });
      expect(legacy.recentAnswered, isEmpty);
    });

    test('pull 落 kv sync.recent_answered，可读出排除集；登出清除', () async {
      final kv = InMemoryKvStore();
      final client = MockClient((request) async {
        if (request.url.path == '/api/v1/sync/pull') {
          return _json(<String, Object?>{
            'changes': <dynamic>[],
            'nextCursor': 0,
            'watermark': 5,
            'hasMore': false,
            'serverTime': '2026-11-17T10:00:00+08:00',
            'baselineRequired': false,
            'recent_answered': <String>['VLAN-0001', 'OSPF-0002'],
          });
        }
        return _json(<String, Object?>{}, 404);
      });
      final sync = HttpSyncService(
        client: client,
        baseUrl: _base,
        tokenProvider: () => 'tok',
        kvStore: kv,
      );
      await sync.pullIncremental();
      expect(kv.getStringList(KvStore.keySyncRecentAnswered), <String>[
        'VLAN-0001',
        'OSPF-0002',
      ]);
      expect(HttpSyncService.recentAnsweredIds(kv), <String>{
        'VLAN-0001',
        'OSPF-0002',
      });
      // getSyncStatus 的小页 pull 同样刷新集合。
      await sync.getSyncStatus();
      expect(HttpSyncService.recentAnsweredIds(kv), <String>{
        'VLAN-0001',
        'OSPF-0002',
      });
      kv.clearAccountData();
      expect(kv.getStringList(KvStore.keySyncRecentAnswered), isNull);
      expect(HttpSyncService.recentAnsweredIds(kv), isEmpty);
    });
  });

  group('回归：既有练习流程不碰轮回端点', () {
    test(
      'HttpPracticeService.drawNextQuestion 仍走 GET /practice/next',
      () async {
        final paths = <String>[];
        final client = MockClient((request) async {
          paths.add(request.url.path);
          if (request.url.path == '/api/v1/practice/next') {
            return _json(<String, Object?>{
              'sessionId': 'S-1',
              'question': <String, Object?>{
                ..._drawQuestionJson('VLAN-0001'),
                'answer': <int>[0],
                'explanation': '解析',
              },
            });
          }
          return _json(<String, Object?>{}, 404);
        });
        final service = HttpPracticeService(
          client: client,
          baseUrl: _base,
          tokenProvider: () => 'tok',
        );
        final next = await service.drawNextQuestion(
          setId: 'VLAN',
          excludedIds: const <String>{},
        );
        expect(next, isNotNull);
        expect(next!.question.id, 'VLAN-0001');
        expect(paths, <String>['/api/v1/practice/next']);
        expect(paths.any((p) => p.contains('/draw')), isFalse);
      },
    );
  });

  group('轮回 widget 链（注入 fake，不注册 ServiceLocator）', () {
    late KvStore kv;
    late KvAnswerRecordService records;
    late KvAnswerSessionService sessions;

    setUp(() {
      kv = InMemoryKvStore();
      records = KvAnswerRecordService(kvStore: kv);
      sessions = KvAnswerSessionService(kvStore: kv);
    });

    Widget rotationPage(
      _RotationFake rotation, {
      BankManifestService? manifest,
      PracticeService? practiceSpy,
    }) {
      return QuizPage(
        args: <String, Object?>{
          'mode': 'rotation',
          'setId': '',
          'setTitle': '7天轮回',
          'drawCount': 20,
          'target': 20,
        },
        rotationService: rotation,
        manifestService: manifest ?? MockBankManifestService(),
        practiceService: practiceSpy,
        recordService: records,
        sessionService: sessions,
      );
    }

    testWidgets('入口 → 抽题 → 逐题判分 → 结算评分页（练习服务 0 调用）', (tester) async {
      final rotation = _RotationFake(
        questions: <Question>[_rotationQuestion(1), _rotationQuestion(2)],
      );
      final spy = _PracticeSpy();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          routes: <String, WidgetBuilder>{
            AppRoutes.bankAnswer: (context) => QuizPage(
              args:
                  ModalRoute.of(context)!.settings.arguments!
                      as Map<String, Object?>,
              rotationService: rotation,
              manifestService: MockBankManifestService(),
              practiceService: spy,
              recordService: records,
              sessionService: sessions,
            ),
          },
          home: SetDetailPage(
            args: <String, Object?>{
              'mode': 'practice',
              'setId': 'H3CNE',
              'setTitle': 'H3CNE',
              'drawCount': 100,
            },
            manifestService: MockBankManifestService(),
            questionRepository: _RepoFake(),
            recordService: records,
            sessionService: sessions,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 前置页（练习模式）出现「7天轮回」入口，滚进视口再点。
      await tester.scrollUntilVisible(
        find.text('7天轮回'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('7天轮回'));
      await tester.pumpAndSettle();

      // 抽题：bankId 来自清单（不硬编码），count 20，服务端会话 id。
      expect(rotation.drawCalls, 1);
      expect(rotation.drawnBankId, 'bank_default');
      expect(rotation.drawnCount, 20);
      expect(find.text('题干 1'), findsOneWidget);
      expect(find.text('第 1/2 题'), findsOneWidget);

      // 第 1 题选 A（fake 正确答案 A）：服务端判分 → 绿。
      await tester.tap(find.byType(OptionTile).at(0));
      await tester.pumpAndSettle();
      expect(_states(tester).first, OptionTileState.correct);
      expect(find.textContaining('答对 1 ·'), findsOneWidget);

      // 下一题 → 第 2 题选 B（正确答案 A）：错项红 + 正确项绿。
      await tester.tap(find.text('下一题'));
      await tester.pumpAndSettle();
      expect(find.text('题干 2'), findsOneWidget);
      expect(find.text('第 2/2 题'), findsOneWidget);
      await tester.tap(find.byType(OptionTile).at(1));
      await tester.pumpAndSettle();
      final states = _states(tester);
      expect(states[0], OptionTileState.correct);
      expect(states[1], OptionTileState.wrong);

      // 完成本轮 → 服务端结算 → 复用全屏评分页（标题 / 得分 / 错题数）。
      expect(find.text('完成本轮'), findsOneWidget);
      await tester.tap(find.text('完成本轮'));
      await tester.pumpAndSettle();
      expect(find.byType(ExamScorePage), findsOneWidget);
      expect(find.text('7天轮回结果'), findsOneWidget);
      expect(find.text('50 分'), findsOneWidget);
      expect(find.text('答错 1 题'), findsOneWidget);
      expect(rotation.submitCalls, 1);
      expect(rotation.submittedSessionId, _RotationFake.sessionId);
      expect(rotation.answerCalls, 2);

      // 幂等键：每次作答 / 结算各一个 UUIDv4，互不相同。
      expect(rotation.opIds, hasLength(3));
      expect(rotation.opIds.toSet(), hasLength(3));
      final uuid = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      );
      for (final opId in rotation.opIds) {
        expect(uuid.hasMatch(opId), isTrue, reason: opId);
      }

      // 回归：轮回全程没有触碰既有练习服务。
      expect(spy.drawCalls, 0);
      expect(spy.submitCalls, 0);

      // 评分页退出 → 离开答题流程，回到前置页。
      await tester.tap(find.text('退出'));
      await tester.pumpAndSettle();
      expect(find.byType(QuizPage), findsNothing);
      expect(find.byType(SetDetailPage), findsOneWidget);
    });

    testWidgets('空抽：服务端文案 + 解锁时间，无题不白屏', (tester) async {
      final rotation = _RotationFake(
        questions: const <Question>[],
        emptyDraw: true,
      );
      await _launch(tester, rotationPage(rotation));
      expect(find.text('当前题库的题都在 7 天轮回中，稍后陆续解锁'), findsOneWidget);
      expect(find.textContaining('下次解锁：'), findsOneWidget);
      expect(find.byType(OptionTile), findsNothing);
      expect(find.text('返回'), findsOneWidget);
      expect(rotation.answerCalls, 0);
      expect(rotation.submitCalls, 0);
    });

    testWidgets('清单不可用：轮回待接口，不抽题不编时间', (tester) async {
      final rotation = _RotationFake(
        questions: <Question>[_rotationQuestion(1)],
      );
      await _launch(
        tester,
        rotationPage(rotation, manifest: _BrokenManifestFake()),
      );
      expect(find.text('轮回待接口'), findsOneWidget);
      expect(find.textContaining('下次解锁：'), findsNothing);
      expect(find.byType(OptionTile), findsNothing);
      expect(rotation.drawCalls, 0);
    });

    testWidgets('短抽：用抽到的题继续，服务端文案提示', (tester) async {
      final rotation = _RotationFake(
        questions: <Question>[_rotationQuestion(1), _rotationQuestion(2)],
        shortDraw: true,
      );
      await _launch(tester, rotationPage(rotation));
      expect(find.text('可抽题不足，已抽取 1 道'), findsOneWidget);
      expect(find.text('第 1/1 题'), findsOneWidget);
      await tester.tap(find.byType(OptionTile).at(0));
      await tester.pumpAndSettle();
      expect(find.text('完成本轮'), findsOneWidget);
    });

    testWidgets('判分失败：只提示重试，不涂红绿不编判分', (tester) async {
      final rotation = _RotationFake(
        questions: <Question>[_rotationQuestion(1)],
        failAnswer: true,
      );
      await _launch(tester, rotationPage(rotation));
      await tester.tap(find.byType(OptionTile).at(0));
      await tester.pumpAndSettle();
      expect(find.text('提交失败，请重试'), findsOneWidget);
      // 没有服务端判分依据：只标已选，绝不涂红绿。
      expect(_states(tester).first, OptionTileState.selected);
      expect(find.textContaining('正确答案：'), findsNothing);
      expect(find.text('下一题'), findsNothing);
    });

    testWidgets('0 题退出：服务端删除空会话，直接离开', (tester) async {
      final rotation = _RotationFake(
        questions: <Question>[_rotationQuestion(1)],
      );
      await _launch(tester, rotationPage(rotation));
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      expect(rotation.submitCalls, 1);
      expect(find.byType(QuizPage), findsNothing);
      expect(find.byType(ExamScorePage), findsNothing);
    });

    testWidgets('>=1 题退出：即结算并展示服务端得分', (tester) async {
      final rotation = _RotationFake(
        questions: <Question>[_rotationQuestion(1), _rotationQuestion(2)],
      );
      await _launch(tester, rotationPage(rotation));
      await tester.tap(find.byType(OptionTile).at(0));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      expect(rotation.submitCalls, 1);
      expect(find.byType(ExamScorePage), findsOneWidget);
      expect(find.text('7天轮回结果'), findsOneWidget);
      expect(find.text('100 分'), findsOneWidget);
    });
  });
}
