/// F25 Chunk 2b：答题记录试卷页（只读逐题回顾）+ 详情页入口导航。
///
/// 全部用 fake / 内存 kv，不发真实网络请求。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/core/kv_store.dart';
import 'package:routepass/core/theme.dart';
import 'package:routepass/models/answer_record.dart';
import 'package:routepass/models/practice.dart';
import 'package:routepass/models/question.dart';
import 'package:routepass/pages/bank/answer_record_detail_page.dart';
import 'package:routepass/pages/bank/answer_record_paper_page.dart';
import 'package:routepass/pages/bank/answer_widgets.dart';
import 'package:routepass/router/app_router.dart';
import 'package:routepass/services/bank/answer_record_service.dart';
import 'package:routepass/services/bank/answer_session_service.dart';
import 'package:routepass/services/bank/practice_service.dart';

AnswerRecord _record({String? serverId = 'sess-1'}) {
  return AnswerRecord(
    id: 'srv-sess-1',
    setId: 'VLAN',
    setTitle: 'VLAN',
    mode: 'practice',
    kind: 'completion',
    targetCount: 20,
    answeredCount: 2,
    totalCount: 20,
    correctCount: 1,
    durationMs: 60000,
    createdAt: 1000,
    updatedAt: 1000,
    synced: serverId != null,
    serverId: serverId,
  );
}

Question _question({
  String id = 'VLAN-0001',
  String type = 'single',
  List<String> answer = const <String>['B'],
  String explanation = '解析一',
}) {
  return Question(
    id: id,
    module: 'VLAN',
    type: type,
    stem: '题干 $id',
    options: const <QuestionOption>[
      QuestionOption(key: 'A', text: '选项 A'),
      QuestionOption(key: 'B', text: '选项 B'),
      QuestionOption(key: 'C', text: '选项 C'),
      QuestionOption(key: 'D', text: '选项 D'),
    ],
    answer: answer,
    explanation: explanation,
    knowledge_point_id: 'kp-1',
    difficulty: 1,
    set_no: 1,
    row_version: 1,
  );
}

PracticePaperItem _item(
  Question question, {
  required List<String> chosen,
  required bool correct,
}) {
  return PracticePaperItem(
    questionId: question.id,
    question: question,
    chosen: chosen,
    correct: correct,
    explanation: question.explanation,
  );
}

PracticeRecordPaper _paper(List<PracticePaperItem> items) {
  return PracticeRecordPaper(
    sessionId: 'sess-1',
    module: 'VLAN',
    status: 'completed',
    items: items,
  );
}

class _FakePracticeService implements PracticeService {
  PracticeRecordPaper? paper;
  bool throwOnPaper = false;
  final List<String> paperCalls = <String>[];

  @override
  Future<PracticeRecordPaper?> getRecordPaper(String sessionId) async {
    paperCalls.add(sessionId);
    if (throwOnPaper) throw const PracticeServiceException('离线');
    return paper;
  }

  @override
  Future<PracticeRecordDetail?> getRecordDetail(String sessionId) async => null;

  @override
  Future<bool> deleteRecord(String sessionId) async => false;

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

Widget _paperHost({
  required AnswerRecord record,
  required _FakePracticeService practice,
  String? sessionId,
}) {
  return MaterialApp(
    theme: AppTheme.light,
    home: AnswerRecordPaperPage(
      args: <String, Object?>{
        'record': record,
        'sessionId': sessionId ?? record.serverId ?? '',
      },
      practiceService: practice,
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

  group('AnswerRecordPaperPage 渲染', () {
    testWidgets('逐题渲染：题目 / 判分配色 / 你的答案 / 正确答案 / 解析', (tester) async {
      // ListView(children:) 仍是懒构建：默认 800×600 视口下第 2 题落在
      // viewport + cacheExtent 之外，永不构建，find.text('第 2 题') 命中 0。
      // 本用例同时断言两题（8 个 OptionTile、两处「正确答案：B」），两卡总高
      // 超过构建窗口，单靠滚动无法让它们同处窗口。放大视口让整卷一次构建
      // （与 home/bank 测试同一做法），下方断言保持不变。
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final q1 = _question();
      final q2 = _question(id: 'VLAN-0002', explanation: '解析二');
      practice.paper = _paper(<PracticePaperItem>[
        _item(q1, chosen: <String>['B'], correct: true),
        _item(q2, chosen: <String>['A'], correct: false),
      ]);
      await tester.pumpWidget(
        _paperHost(record: _record(), practice: practice),
      );
      await tester.pumpAndSettle();

      expect(practice.paperCalls, <String>['sess-1']);
      expect(find.text('试卷回顾'), findsOneWidget);
      expect(find.text('共 2 题 · 答对 1 题'), findsOneWidget);
      expect(find.text('第 1 题'), findsOneWidget);
      expect(find.text('第 2 题'), findsOneWidget);
      expect(find.text('题干 VLAN-0001'), findsOneWidget);
      expect(find.text('题干 VLAN-0002'), findsOneWidget);
      // 对错标记。
      expect(find.text('答对'), findsOneWidget);
      expect(find.text('答错'), findsOneWidget);
      // 你的答案 / 正确答案 / 解析（AnalysisCard，真实数据不带样例标注）。
      expect(find.text('你的答案：B'), findsOneWidget);
      expect(find.text('你的答案：A'), findsOneWidget);
      expect(find.text('正确答案：B'), findsNWidgets(2));
      expect(find.text('解析一'), findsOneWidget);
      expect(find.text('解析二'), findsOneWidget);
      expect(find.text('样例数据'), findsNothing);

      // 选项判分配色：正确答案标绿；用户错选标红；其余不着色。
      final tiles = tester
          .widgetList<OptionTile>(find.byType(OptionTile))
          .toList();
      expect(tiles, hasLength(8));
      // 第 1 题：选 B 且 B 正确。
      expect(tiles[1].selected, isTrue);
      expect(tiles[1].state, OptionTileState.correct);
      expect(tiles[0].state, OptionTileState.idle);
      // 第 2 题：错选 A 标红，正确答案 B 标绿。
      expect(tiles[4].selected, isTrue);
      expect(tiles[4].state, OptionTileState.wrong);
      expect(tiles[5].state, OptionTileState.correct);
      expect(tiles[5].selected, isFalse);
    });

    testWidgets('只读：点选项不改变作答', (tester) async {
      practice.paper = _paper(<PracticePaperItem>[
        _item(_question(), chosen: <String>['A'], correct: false),
      ]);
      await tester.pumpWidget(
        _paperHost(record: _record(), practice: practice),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('选项 C'));
      await tester.pumpAndSettle();

      expect(find.text('你的答案：A'), findsOneWidget);
      expect(find.text('你的答案：C'), findsNothing);
      expect(find.text('答错'), findsOneWidget);
    });

    testWidgets('空试卷显示空态，不虚构题目', (tester) async {
      practice.paper = _paper(const <PracticePaperItem>[]);
      await tester.pumpWidget(
        _paperHost(record: _record(), practice: practice),
      );
      await tester.pumpAndSettle();

      expect(find.text('这条记录没有已作答的题目'), findsOneWidget);
      expect(find.byType(OptionTile), findsNothing);
      expect(find.text('第 1 题'), findsNothing);
    });
  });

  group('AnswerRecordPaperPage 容错', () {
    testWidgets('离线 / 未登录：显示重试，重试成功后渲染', (tester) async {
      practice.paper = null; // 服务端不可达
      await tester.pumpWidget(
        _paperHost(record: _record(), practice: practice),
      );
      await tester.pumpAndSettle();

      expect(find.text('试卷加载失败'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);

      practice.paper = _paper(<PracticePaperItem>[
        _item(_question(), chosen: <String>['B'], correct: true),
      ]);
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();

      expect(practice.paperCalls, <String>['sess-1', 'sess-1']);
      expect(find.text('试卷加载失败'), findsNothing);
      expect(find.text('题干 VLAN-0001'), findsOneWidget);
      expect(find.text('答对'), findsOneWidget);
    });

    testWidgets('服务抛异常不崩溃，显示重试态', (tester) async {
      practice.throwOnPaper = true;
      await tester.pumpWidget(
        _paperHost(record: _record(), practice: practice),
      );
      await tester.pumpAndSettle();

      expect(find.text('试卷加载失败'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
    });

    testWidgets('本地未同步记录（无 serverId）不请求服务端', (tester) async {
      await tester.pumpWidget(
        _paperHost(record: _record(serverId: null), practice: practice),
      );
      await tester.pumpAndSettle();

      expect(practice.paperCalls, isEmpty);
      expect(find.text('暂无试卷'), findsOneWidget);
      expect(find.text('重试'), findsNothing);
    });
  });

  group('详情页入口', () {
    testWidgets('点「查看试卷」导航到试卷路由并携带 record 与 sessionId', (tester) async {
      final record = _record();
      String? pushedName;
      Object? pushedArgs;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          onGenerateRoute: (settings) {
            if (settings.name == AppRoutes.bankRecordPaper) {
              pushedName = settings.name;
              pushedArgs = settings.arguments;
            }
            return MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => const Scaffold(body: Text('试卷占位')),
            );
          },
          home: AnswerRecordDetailPage(
            args: <String, Object?>{'record': record},
            practiceService: practice,
            recordService: records,
            sessionService: sessions,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('查看试卷'));
      await tester.pumpAndSettle();

      expect(pushedName, AppRoutes.bankRecordPaper);
      expect(pushedName, '/bank/record-paper');
      final args = pushedArgs! as Map<String, Object?>;
      expect(args['record'], same(record));
      expect(args['sessionId'], 'sess-1');
      expect(find.text('试卷占位'), findsOneWidget);
    });
  });
}
