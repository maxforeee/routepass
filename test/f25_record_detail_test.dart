/// F25 Chunk 2a：答题记录详情页（摘要 + 删除）。
///
/// 全部用 fake / 内存 kv，不发真实网络请求。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/core/kv_store.dart';
import 'package:routepass/core/theme.dart';
import 'package:routepass/models/answer_record.dart';
import 'package:routepass/models/answer_session_state.dart';
import 'package:routepass/models/practice.dart';
import 'package:routepass/models/question.dart';
import 'package:routepass/pages/bank/answer_record_detail_page.dart';
import 'package:routepass/router/app_router.dart';
import 'package:routepass/services/bank/answer_record_service.dart';
import 'package:routepass/services/bank/answer_session_service.dart';
import 'package:routepass/services/bank/practice_service.dart';
import 'package:routepass/widgets/answer_records_card.dart';

AnswerRecord _record({
  String id = 'srv-sess-1',
  String setId = 'VLAN',
  String mode = 'practice',
  String kind = 'completion',
  int target = 20,
  int answered = 20,
  int? correct = 16,
  String? serverId = 'sess-1',
}) {
  return AnswerRecord(
    id: id,
    setId: setId,
    setTitle: setId,
    mode: mode,
    kind: kind,
    targetCount: target,
    answeredCount: answered,
    totalCount: 100,
    correctCount: correct,
    durationMs: 760000,
    createdAt: 1000,
    updatedAt: 1000,
    synced: serverId != null,
    serverId: serverId,
  );
}

PracticeRecordDetail _detail({
  int answered = 20,
  int correct = 16,
  int score = 80,
  List<PracticeWeakPoint> weakPoints = const <PracticeWeakPoint>[],
}) {
  return PracticeRecordDetail(
    sessionId: 'sess-1',
    module: 'VLAN',
    status: 'completed',
    answered: answered,
    total: answered,
    correct: correct,
    score: score,
    weakPoints: weakPoints,
  );
}

class _FakePracticeService implements PracticeService {
  PracticeRecordDetail? detail;
  bool deleteResult = true;
  final List<String> detailCalls = <String>[];
  final List<String> deleteCalls = <String>[];

  @override
  Future<PracticeRecordDetail?> getRecordDetail(String sessionId) async {
    detailCalls.add(sessionId);
    return detail;
  }

  @override
  Future<bool> deleteRecord(String sessionId) async {
    deleteCalls.add(sessionId);
    return deleteResult;
  }

  @override
  Future<PracticeRecordPaper?> getRecordPaper(String sessionId) async => null;

  @override
  Future<PracticeSession> startSession({
    required List<Question> questions,
    required String mode,
  }) => throw UnimplementedError();

  @override
  Future<AnswerResult> submitAnswer({
    required String sessionId,
    required String questionId,
    required List<String> chosen,
    required int durationMs,
    String? setId,
    String? opId,
    String? mode,
  }) => throw UnimplementedError();

  @override
  Future<PracticeNext?> drawNextQuestion({
    required String setId,
    String? module,
    required Set<String> excludedIds,
    String? sessionId,
  }) async => null;

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

  @override
  Future<ContinueSession?> resumeSession({required String setId}) async => null;

  @override
  Future<ContinueSession?> getContinueSession() async => null;
}

AnswerSessionState _sessionState() {
  return const AnswerSessionState(
    setId: 'VLAN',
    setTitle: 'VLAN',
    mode: 'practice',
    targetCount: 20,
    answeredCount: 15,
    correctCount: 12,
    answeredIds: <String>['q1'],
    answers: <String, List<String>>{},
    startedAt: 1000,
    updatedAt: 2000,
    sessionId: 'sess-bp',
  );
}

/// 详情页直接作为 home（渲染类用例）。
Widget _detailHost({
  required AnswerRecord record,
  required _FakePracticeService practice,
  required KvAnswerRecordService records,
  required KvAnswerSessionService sessions,
}) {
  return MaterialApp(
    theme: AppTheme.light,
    home: AnswerRecordDetailPage(
      args: <String, Object?>{'record': record},
      practiceService: practice,
      recordService: records,
      sessionService: sessions,
    ),
  );
}

/// 前置页（按钮占位）→ push 详情页，验证删除后 pop 回前置页。
Widget _pushHost({
  required AnswerRecord record,
  required _FakePracticeService practice,
  required KvAnswerRecordService records,
  required KvAnswerSessionService sessions,
}) {
  return MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => AnswerRecordDetailPage(
                  args: <String, Object?>{'record': record},
                  practiceService: practice,
                  recordService: records,
                  sessionService: sessions,
                ),
              ),
            ),
            child: const Text('前置页'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late KvStore kv;
  late KvAnswerRecordService records;
  late KvAnswerSessionService sessions;
  late _FakePracticeService practice;

  setUp(() {
    kv = InMemoryKvStore();
    records = KvAnswerRecordService(kvStore: kv);
    sessions = KvAnswerSessionService(kvStore: kv);
    practice = _FakePracticeService();
  });

  group('AnswerRecordDetailPage 摘要', () {
    testWidgets('渲染服务端真实统计：答题数 / 答对 / 正确率 / 薄弱点', (tester) async {
      practice.detail = _detail(
        weakPoints: const <PracticeWeakPoint>[
          PracticeWeakPoint(module: 'VLAN', wrong: 3, total: 12),
          PracticeWeakPoint(module: 'OSPF', wrong: 1, total: 8),
        ],
      );
      await tester.pumpWidget(
        _detailHost(
          record: _record(),
          practice: practice,
          records: records,
          sessions: sessions,
        ),
      );
      await tester.pumpAndSettle();

      expect(practice.detailCalls, <String>['sess-1']);
      expect(find.text('答题记录详情'), findsOneWidget);
      expect(find.text('答题数'), findsOneWidget);
      expect(find.text('20 题'), findsOneWidget);
      expect(find.text('16 题'), findsOneWidget);
      expect(find.text('80%'), findsOneWidget);
      expect(find.text('薄弱点'), findsOneWidget);
      expect(find.text('VLAN'), findsOneWidget);
      expect(find.text('错 3/12 题'), findsOneWidget);
      expect(find.text('OSPF'), findsOneWidget);
      expect(find.text('错 1/8 题'), findsOneWidget);
      // 详情页只有摘要，不渲染题目列表。
      expect(find.byType(ListView), findsNothing);
    });

    testWidgets('全对时显示明确的“没有薄弱点”，不虚构', (tester) async {
      practice.detail = _detail(answered: 20, correct: 20, score: 100);
      await tester.pumpWidget(
        _detailHost(
          record: _record(correct: 20),
          practice: practice,
          records: records,
          sessions: sessions,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('100%'), findsOneWidget);
      expect(find.text('本次练习没有薄弱点'), findsOneWidget);
    });

    testWidgets('离线 / 未登录：回落本地摘要，薄弱点待接口', (tester) async {
      practice.detail = null; // 服务端不可达
      await tester.pumpWidget(
        _detailHost(
          record: _record(),
          practice: practice,
          records: records,
          sessions: sessions,
        ),
      );
      await tester.pumpAndSettle();

      // 本地 correctCount 16 / answered 20 → 80%。
      expect(find.text('20 题'), findsOneWidget);
      expect(find.text('16 题'), findsOneWidget);
      expect(find.text('80%'), findsOneWidget);
      expect(find.text('薄弱点待接口'), findsOneWidget);
    });

    testWidgets('断点记录显示 已答/目标', (tester) async {
      practice.detail = null;
      await tester.pumpWidget(
        _detailHost(
          record: _record(kind: 'breakpoint', answered: 15, correct: 12),
          practice: practice,
          records: records,
          sessions: sessions,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('15/20 题'), findsOneWidget);
    });
  });

  group('AnswerRecordDetailPage 删除', () {
    testWidgets('取消确认不删除', (tester) async {
      records.upsert(_record());
      await tester.pumpWidget(
        _pushHost(
          record: _record(),
          practice: practice,
          records: records,
          sessions: sessions,
        ),
      );
      await tester.tap(find.text('前置页'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('删除记录'));
      await tester.pumpAndSettle();
      expect(find.text('删除后不可恢复，确定删除这条答题记录吗？'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(practice.deleteCalls, isEmpty);
      expect(records.recordsFor(setId: 'VLAN', mode: 'practice'), hasLength(1));
      expect(find.text('答题记录详情'), findsOneWidget);
    });

    testWidgets('确认后删服务端 + 本地，并 pop 回前置页', (tester) async {
      records.upsert(_record());
      await tester.pumpWidget(
        _pushHost(
          record: _record(),
          practice: practice,
          records: records,
          sessions: sessions,
        ),
      );
      await tester.tap(find.text('前置页'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('删除记录'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();

      expect(practice.deleteCalls, <String>['sess-1']);
      expect(records.recordsFor(setId: 'VLAN', mode: 'practice'), isEmpty);
      expect(find.text('前置页'), findsOneWidget);
      expect(find.text('答题记录详情'), findsNothing);
    });

    testWidgets('服务端删除失败（离线）仍删本地并返回', (tester) async {
      practice.deleteResult = false;
      records.upsert(_record());
      await tester.pumpWidget(
        _pushHost(
          record: _record(),
          practice: practice,
          records: records,
          sessions: sessions,
        ),
      );
      await tester.tap(find.text('前置页'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('删除记录'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();

      expect(records.recordsFor(setId: 'VLAN', mode: 'practice'), isEmpty);
      expect(find.text('前置页'), findsOneWidget);
    });

    testWidgets('断点记录删除同时清进行态，继续练习不再续答', (tester) async {
      final breakpoint = _record(
        id: 'srv-sess-bp',
        kind: 'breakpoint',
        answered: 15,
        correct: 12,
        serverId: 'sess-bp',
      );
      records.upsert(breakpoint);
      sessions.save(_sessionState());
      expect(sessions.load(setId: 'VLAN', mode: 'practice'), isNotNull);

      await tester.pumpWidget(
        _pushHost(
          record: breakpoint,
          practice: practice,
          records: records,
          sessions: sessions,
        ),
      );
      await tester.tap(find.text('前置页'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('删除记录'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();

      expect(practice.deleteCalls, <String>['sess-bp']);
      expect(records.breakpointOf(setId: 'VLAN', mode: 'practice'), isNull);
      expect(sessions.load(setId: 'VLAN', mode: 'practice'), isNull);
    });

    testWidgets('本地未同步记录（无 serverId）不请求服务端，删除只清本地', (tester) async {
      final local = _record(id: 'rec-local', serverId: null);
      records.upsert(local);
      await tester.pumpWidget(
        _pushHost(
          record: local,
          practice: practice,
          records: records,
          sessions: sessions,
        ),
      );
      await tester.tap(find.text('前置页'));
      await tester.pumpAndSettle();
      expect(practice.detailCalls, isEmpty);

      await tester.tap(find.text('删除记录'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();

      expect(practice.deleteCalls, isEmpty);
      expect(records.recordsFor(setId: 'VLAN', mode: 'practice'), isEmpty);
      expect(find.text('前置页'), findsOneWidget);
    });
  });

  group('记录行点击', () {
    testWidgets('点记录行导航到详情页路由并携带 record', (tester) async {
      final record = _record();
      String? pushedName;
      Object? pushedArgs;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          onGenerateRoute: (settings) {
            if (settings.name == AppRoutes.bankRecordDetail) {
              pushedName = settings.name;
              pushedArgs = settings.arguments;
            }
            return MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => const Scaffold(body: Text('详情占位')),
            );
          },
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 348,
                child: AnswerRecordsCard(records: <AnswerRecord>[record]),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('已完成 · 20/20 题'));
      await tester.pumpAndSettle();

      expect(pushedName, AppRoutes.bankRecordDetail);
      expect(pushedName, '/bank/record-detail');
      final args = pushedArgs! as Map<String, Object?>;
      expect(args['record'], same(record));
      expect(find.text('详情占位'), findsOneWidget);
    });

    testWidgets('断点行「继续」仍走 onContinue，不进详情', (tester) async {
      var continued = 0;
      String? pushedName;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          onGenerateRoute: (settings) {
            pushedName = settings.name;
            return MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => const Scaffold(body: Text('占位')),
            );
          },
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 348,
                child: AnswerRecordsCard(
                  records: <AnswerRecord>[
                    _record(kind: 'breakpoint', answered: 15),
                  ],
                  onContinue: () => continued++,
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('继续'));
      await tester.pumpAndSettle();
      expect(continued, 1);
      expect(pushedName, isNot(AppRoutes.bankRecordDetail));
    });
  });
}
