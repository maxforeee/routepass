// F21：答题页两个线上问题的回归测试。
//
// Bug 1：练习模式「上一题」永久禁用（只存一道题，历史被丢弃）。
// Bug 2：点「下一题」后整屏变灰——先用复刻线上抽题链的 fake 复现。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/core/kv_store.dart';
import 'package:routepass/core/theme.dart';
import 'package:routepass/models/answer_record.dart';
import 'package:routepass/models/practice.dart';
import 'package:routepass/models/question.dart';
import 'package:routepass/pages/bank/answer_widgets.dart';
import 'package:routepass/pages/bank/quiz_page.dart';
import 'package:routepass/services/bank/answer_record_service.dart';
import 'package:routepass/services/bank/answer_session_service.dart';
import 'package:routepass/services/bank/practice_service.dart';
import 'package:routepass/services/bank/question_bank_source.dart';

/// 线上题库 JSON 形状：options 是纯字符串数组，answer 是 0 基下标数组。
Map<String, dynamic> _bankJson(
  int index, {
  List<String>? options,
  List<Object> answer = const <Object>[0],
  String type = 'single',
  String? stem,
}) {
  return <String, dynamic>{
    'id': 'VLAN-${index.toString().padLeft(4, '0')}',
    'module': 'VLAN',
    'type': type,
    'stem': stem ?? '题干 $index',
    'options': options ?? <String>['A 选项', 'B 选项', 'C 选项', 'D 选项'],
    'answer': answer,
    'explanation': '解析内容 $index',
    'knowledgePointId': 'VLAN-01',
    'difficulty': 1,
  };
}

/// 复刻线上抽题链：CachedPracticeService（本地题库 + 本地 attempts 排除）
/// → HttpPracticeService /practice/next → MockPracticeService（抽尽返回 null）。
class _BankPracticeService implements PracticeService {
  _BankPracticeService(
    List<Map<String, dynamic>> raw, {
    this.nullAfterDraw,
    this.nullOnDraw,
    this.alwaysRepeatFirst = false,
    this.failDraw = false,
    this.drawDelay = Duration.zero,
  }) : questions = raw
           .map((json) => mapBankQuestionJson(json)!)
           .toList(growable: false);

  final List<Question> questions;

  /// 第 N 次抽题之后一律返回 null（Mock 只有 3 道样例题的抽尽路径）。
  final int? nullAfterDraw;

  /// 只有第 N 次抽题返回 null（抽尽一次后又恢复，例如网络/缓存恢复）。
  final int? nullOnDraw;

  /// 第二次起永远返回第一题（服务端/缓存不排除已答 id 的重复抽题）。
  final bool alwaysRepeatFirst;

  /// 首次抽题之后一律抛错（线上 /practice/next 401）。
  final bool failDraw;

  /// 抽题耗时：真机上 SQLite / HTTP 不是同步返回的。
  final Duration drawDelay;

  final Set<String> localAnswered = <String>{};
  int drawCalls = 0;
  int submitCalls = 0;
  Set<String> lastExcludedIds = <String>{};

  @override
  Future<PracticeNext?> drawNextQuestion({
    required String setId,
    String? module,
    required Set<String> excludedIds,
    String? sessionId,
  }) async {
    drawCalls++;
    lastExcludedIds = excludedIds;
    if (drawDelay > Duration.zero) {
      await Future<void>.delayed(drawDelay);
    }
    if (failDraw && drawCalls > 1) {
      throw Exception('GET /practice/next 401');
    }
    if (nullAfterDraw != null && drawCalls > nullAfterDraw!) return null;
    if (nullOnDraw != null && drawCalls == nullOnDraw) return null;
    if (alwaysRepeatFirst && drawCalls > 1) {
      return PracticeNext(
        question: questions.first,
        sessionId: sessionId ?? 'S-1',
        doneCount: excludedIds.length,
      );
    }
    final excluded = <String>{...excludedIds, ...localAnswered};
    for (final q in questions) {
      if (!excluded.contains(q.id)) {
        return PracticeNext(
          question: q,
          sessionId: sessionId ?? 'S-1',
          doneCount: excludedIds.length,
        );
      }
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
    localAnswered.add(questionId);
    final q = questions.firstWhere((q) => q.id == questionId);
    final correct =
        chosen.length == q.answer.length &&
        chosen.toSet().containsAll(q.answer);
    return AnswerResult(
      correct: correct,
      explanation: q.explanation,
      correctKeys: q.answer,
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

Widget _host(Widget quiz) {
  return MaterialApp(
    theme: AppTheme.light,
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () =>
                Navigator.of(context)
                    .push(MaterialPageRoute<void>(builder: (_) => quiz)),
            child: const Text('launch'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _launch(WidgetTester tester, Widget quiz) async {
  await tester.pumpWidget(_host(quiz));
  await tester.tap(find.text('launch'));
  await tester.pumpAndSettle();
}

Future<void> _tapOption(WidgetTester tester, int index) async {
  await tester.tap(find.byType(OptionTile).at(index));
  await tester.pumpAndSettle();
}

/// F22 起练习单选/判断「点选项即判分」，没有「确认作答」这一步；多选仍要
/// 确认。故按钮在就点、不在就跳过——多选用例的判分断言依旧守着这一步。
Future<void> _confirm(WidgetTester tester) async {
  final button = find.text('确认作答');
  if (button.evaluate().isEmpty) return;
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> _next(WidgetTester tester) async {
  await tester.tap(find.text('下一题'));
  await tester.pumpAndSettle();
}

/// 「整屏变灰」在测试里的等价断言：没有异常、没有 ErrorWidget、题目正文仍在。
void _expectRenders(WidgetTester tester, String stem, int optionCount) {
  expect(tester.takeException(), isNull, reason: '换题后 build/layout 抛异常');
  expect(find.byType(ErrorWidget), findsNothing, reason: '灰屏 = 失败的子树');
  expect(find.text(stem), findsOneWidget);
  expect(find.byType(OptionTile), findsNWidgets(optionCount));
  expect(find.text('确认作答'), findsOneWidget);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late KvStore kv;
  late KvAnswerRecordService records;
  late KvAnswerSessionService sessions;

  setUp(() {
    kv = InMemoryKvStore();
    records = KvAnswerRecordService(kvStore: kv);
    sessions = KvAnswerSessionService(kvStore: kv);
  });

  Widget practicePage(_BankPracticeService practice, {int target = 20}) {
    return QuizPage(
      args: <String, Object?>{
        'mode': 'practice',
        'setId': 'VLAN',
        'setTitle': 'VLAN',
        'drawCount': 100,
        'target': target,
      },
      practiceService: practice,
      recordService: records,
      sessionService: sessions,
    );
  }

  group('F21 Bug 2：点「下一题」后整屏变灰', () {
    testWidgets('(a) 线上题库形状：字符串选项 + 0 基下标答案，换题后正常渲染', (tester) async {
      final practice = _BankPracticeService(<Map<String, dynamic>>[
        for (var i = 1; i <= 6; i++) _bankJson(i),
      ]);
      await _launch(tester, practicePage(practice));
      expect(find.text('题干 1'), findsOneWidget);

      await _tapOption(tester, 0);
      await _confirm(tester);
      expect(find.text('正确答案：A'), findsOneWidget);

      await _next(tester);
      _expectRenders(tester, '题干 2', 4);
    });

    testWidgets('(b) 第二次抽题返回 null（Mock 抽尽）后不灰屏', (tester) async {
      final practice = _BankPracticeService(<Map<String, dynamic>>[
        _bankJson(1),
        _bankJson(2),
      ], nullAfterDraw: 1);
      await _launch(tester, practicePage(practice));

      await _tapOption(tester, 0);
      await _confirm(tester);
      await _next(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(ErrorWidget), findsNothing);
      expect(find.text('本题库已全部完成'), findsWidgets);
      expect(find.text('结束本轮'), findsWidgets);
    });

    testWidgets('(c) 第二次抽题返回重复 id 后不灰屏', (tester) async {
      final practice = _BankPracticeService(<Map<String, dynamic>>[
        _bankJson(1),
        _bankJson(2),
        _bankJson(3),
      ], alwaysRepeatFirst: true);
      await _launch(tester, practicePage(practice));

      await _tapOption(tester, 0);
      await _confirm(tester);
      await _next(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(ErrorWidget), findsNothing);
      expect(find.text('题干 1'), findsOneWidget);
    });

    testWidgets('(d) 选项数与题型在换题时变化（4 单选 → 2 判断 → 5 多选）', (tester) async {
      final practice = _BankPracticeService(<Map<String, dynamic>>[
        _bankJson(1),
        _bankJson(
          2,
          type: 'judge',
          options: <String>['正确', '错误'],
          answer: const <Object>[1],
        ),
        _bankJson(
          3,
          type: 'multiple',
          options: <String>['A 选项', 'B 选项', 'C 选项', 'D 选项', 'E 选项'],
          answer: const <Object>[0, 2],
        ),
        _bankJson(4),
      ]);
      await _launch(tester, practicePage(practice));

      await _tapOption(tester, 0);
      await _confirm(tester);
      await _next(tester);
      _expectRenders(tester, '题干 2', 2);

      await _tapOption(tester, 1);
      await _confirm(tester);
      await _next(tester);
      _expectRenders(tester, '题干 3', 5);

      await _tapOption(tester, 0);
      await _tapOption(tester, 2);
      await _confirm(tester);
      await _next(tester);
      _expectRenders(tester, '题干 4', 4);
    });

    testWidgets('(e) 抽题抛异常（/practice/next 401）后不灰屏、保留当前题', (tester) async {
      final practice = _BankPracticeService(<Map<String, dynamic>>[
        _bankJson(1),
        _bankJson(2),
      ], failDraw: true);
      await _launch(tester, practicePage(practice));

      await _tapOption(tester, 0);
      await _confirm(tester);
      await _next(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(ErrorWidget), findsNothing);
      expect(find.text('题干 1'), findsOneWidget);
      expect(find.text('下一题'), findsOneWidget);
      expect(find.text('抽题失败，请重试'), findsOneWidget);
      expect(find.text('正确答案：A'), findsOneWidget, reason: '失败不得清掉判分');
      expect(find.text('第 1/20 题'), findsOneWidget);
      expect(
        sessions.load(setId: 'VLAN', mode: 'practice')!.answeredCount,
        1,
        reason: '失败不得改计数',
      );
      expect(practice.drawCalls, 2);
    });

    testWidgets('(k) 抽尽一次后又抽到题：完成横幅必须撤掉，不能盖在新题上', (tester) async {
      final practice = _BankPracticeService(<Map<String, dynamic>>[
        for (var i = 1; i <= 6; i++) _bankJson(i),
      ], nullOnDraw: 2);
      await _launch(tester, practicePage(practice));

      await _tapOption(tester, 0);
      await _confirm(tester);
      await _next(tester);
      expect(find.text('本题库已全部完成'), findsWidgets);
      // snackbar 与横幅同文案，先等它退场再断言横幅本身。
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text('本题库已全部完成'), findsOneWidget);

      await _next(tester);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('题干 2'), findsOneWidget);
      expect(find.text('本题库已全部完成'), findsNothing);
      expect(find.text('确认作答'), findsOneWidget);
      expect(find.text('第 2/20 题'), findsOneWidget);
    });

    testWidgets('(f) 真实长度题干/选项 + 6 选项 + 已有答题记录，换题后正常渲染', (tester) async {
      final longOption = '这是一个很长的选项文本，' * 12;
      records.upsert(
        AnswerRecord(
          id: 'rec-old',
          setId: 'VLAN',
          setTitle: 'VLAN',
          mode: 'practice',
          kind: 'breakpoint',
          targetCount: 20,
          answeredCount: 7,
          totalCount: 100,
          correctCount: 5,
          durationMs: 60000,
          createdAt: DateTime.now().millisecondsSinceEpoch,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      final practice = _BankPracticeService(<Map<String, dynamic>>[
        for (var i = 1; i <= 2; i++)
          _bankJson(
            i,
            stem: '题干 $i：${'这是一道很长的题干，' * 30}',
            options: <String>[for (var j = 0; j < 6; j++) '$longOption$j'],
          ),
      ]);
      await _launch(tester, practicePage(practice));

      await _tapOption(tester, 0);
      await _confirm(tester);
      await _next(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(ErrorWidget), findsNothing);
      // 长题干把选项挤出视口，ListView 懒构建，只断言可见部分。
      expect(find.byType(OptionTile), findsWidgets);
      expect(find.text('第 2/20 题'), findsOneWidget);
    });

    testWidgets('(g) 抽题有真实耗时：等待期间计时器 setState、连点两次「下一题」', (tester) async {
      final practice = _BankPracticeService(<Map<String, dynamic>>[
        for (var i = 1; i <= 6; i++) _bankJson(i),
      ], drawDelay: const Duration(milliseconds: 600));
      await _launch(tester, practicePage(practice));

      await _tapOption(tester, 0);
      await _confirm(tester);

      // 两次点击都落在抽题返回之前（按钮此时仍是「下一题」）。
      await tester.tap(find.text('下一题'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('下一题'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(ErrorWidget), findsNothing);
      expect(find.byType(OptionTile), findsNWidgets(4));
      expect(find.text('确认作答'), findsOneWidget);
      expect(find.text('第 2/20 题'), findsOneWidget);
      expect(practice.drawCalls, 2, reason: '连点两次只抽一次，不许跳题');
    });

    testWidgets('(i) 选中/判分动画未结束就换题（真机手速）', (tester) async {
      final practice = _BankPracticeService(<Map<String, dynamic>>[
        _bankJson(1),
        _bankJson(2, type: 'multiple', answer: const <Object>[0, 2]),
        _bankJson(3),
      ]);
      await _launch(tester, practicePage(practice));

      await tester.tap(find.byType(OptionTile).at(0));
      await tester.pump(const Duration(milliseconds: 40));
      // F22：单选点完即判分，判分动画同样没播完就换题。
      await tester.tap(find.text('下一题'));
      await tester.pump(const Duration(milliseconds: 40));
      await tester.pumpAndSettle();
      _expectRenders(tester, '题干 2', 4);

      await tester.tap(find.byType(OptionTile).at(0));
      await tester.pump(const Duration(milliseconds: 20));
      await tester.tap(find.byType(OptionTile).at(2));
      await tester.pump(const Duration(milliseconds: 20));
      await tester.tap(find.text('确认作答'));
      await tester.pump(const Duration(milliseconds: 20));
      await tester.tap(find.text('下一题'));
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pumpAndSettle();
      _expectRenders(tester, '题干 3', 4);
    });

    testWidgets('(j) 先滚到解析底部再点「下一题」：新题必须可见，不是空白灰屏', (tester) async {
      final practice = _BankPracticeService(<Map<String, dynamic>>[
        for (var i = 1; i <= 6; i++)
          _bankJson(i, stem: '题干 $i：${'很长的题干，' * 40}'),
      ]);
      await _launch(tester, practicePage(practice));

      await _tapOption(tester, 0);
      await _confirm(tester);
      await tester.scrollUntilVisible(
        find.text('解析内容 1'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      final scrolled = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .pixels;
      expect(scrolled, greaterThan(0), reason: '先确认真的滚下去了');

      await _next(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(ErrorWidget), findsNothing);
      expect(find.text('题干 2：${'很长的题干，' * 40}'), findsOneWidget);
      expect(
        find.byType(OptionTile).hitTestable(),
        findsWidgets,
        reason: '换题后内容收缩，视口不能停在旧偏移上渲染空白',
      );
      expect(
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .pixels,
        lessThanOrEqualTo(
          tester
              .state<ScrollableState>(find.byType(Scrollable).first)
              .position
              .maxScrollExtent,
        ),
      );
    });

    testWidgets('(h) 换题后没有残留的遮罩/灰幕（ModalBarrier、Overlay 条目）', (tester) async {
      final practice = _BankPracticeService(<Map<String, dynamic>>[
        for (var i = 1; i <= 6; i++) _bankJson(i),
      ]);
      await _launch(tester, practicePage(practice));
      final barriersBefore = find.byType(ModalBarrier).evaluate().length;

      await _tapOption(tester, 0);
      await _confirm(tester);
      await _next(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.byType(ModalBarrier).evaluate().length,
        barriersBefore,
        reason: '换题不该插入新的遮罩（灰幕）',
      );
      expect(find.text('第 2/20 题'), findsOneWidget);
    });
  });

  group('F21 Bug 1：练习模式回看上一题', () {
    testWidgets('第一题「上一题」禁用；答完第二题后可回到第一题并带回判分与解析', (tester) async {
      final practice = _BankPracticeService(<Map<String, dynamic>>[
        for (var i = 1; i <= 6; i++) _bankJson(i),
      ]);
      await _launch(tester, practicePage(practice));

      TextButton previous() =>
          tester.widget<TextButton>(find.widgetWithText(TextButton, '上一题'));
      expect(previous().onPressed, isNull, reason: '第一题没有上一题');

      await _tapOption(tester, 0);
      await _confirm(tester);
      await _next(tester);
      expect(find.text('题干 2'), findsOneWidget);
      expect(previous().onPressed, isNotNull, reason: '练习模式必须能回上一题');

      await tester.tap(find.text('上一题'));
      await tester.pumpAndSettle();

      expect(find.text('题干 1'), findsOneWidget);
      expect(find.text('正确答案：A'), findsOneWidget, reason: '回看要带回判分');
      final tiles = tester
          .widgetList<OptionTile>(find.byType(OptionTile))
          .toList();
      expect(tiles[0].option.key, 'A');
      expect(tiles[0].state, OptionTileState.correct);
      expect(tiles[0].selected, isTrue);
      expect(find.text('下一题'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('解析内容 1'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('解析内容 1'), findsOneWidget);
    });

    testWidgets('回看历史后「下一题」沿历史前进，走到最新一题才抽新题', (tester) async {
      final practice = _BankPracticeService(<Map<String, dynamic>>[
        for (var i = 1; i <= 6; i++) _bankJson(i),
      ]);
      await _launch(tester, practicePage(practice));

      for (var i = 0; i < 3; i++) {
        await _tapOption(tester, 0);
        await _confirm(tester);
        if (i < 2) await _next(tester);
      }
      expect(find.text('题干 3'), findsOneWidget);
      expect(practice.drawCalls, 3);

      await tester.tap(find.text('上一题'));
      await tester.pumpAndSettle();
      expect(find.text('题干 2'), findsOneWidget);
      await tester.tap(find.text('上一题'));
      await tester.pumpAndSettle();
      expect(find.text('题干 1'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '上一题'))
            .onPressed,
        isNull,
      );

      await _next(tester);
      expect(find.text('题干 2'), findsOneWidget);
      expect(practice.drawCalls, 3, reason: '历史内前进不许抽新题');
      await _next(tester);
      expect(find.text('题干 3'), findsOneWidget);
      expect(practice.drawCalls, 3);

      await _next(tester);
      expect(find.text('题干 4'), findsOneWidget);
      expect(practice.drawCalls, 4, reason: '到最新一题后才抽新题');
    });

    testWidgets('历史导航中题号、进度与断点 lastQuestionId 跟随当前题', (tester) async {
      final practice = _BankPracticeService(<Map<String, dynamic>>[
        for (var i = 1; i <= 6; i++) _bankJson(i),
      ]);
      await _launch(tester, practicePage(practice, target: 3));

      for (var i = 0; i < 3; i++) {
        await _tapOption(tester, 0);
        await _confirm(tester);
        if (i < 2) await _next(tester);
      }
      expect(find.text('第 3/3 题'), findsOneWidget);

      await tester.tap(find.text('上一题'));
      await tester.pumpAndSettle();
      expect(find.text('第 2/3 题'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('本次 · 已答 3/3 题 · 答对 3 题'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('本次 · 已答 3/3 题 · 答对 3 题'), findsOneWidget);

      final saved = sessions.load(setId: 'VLAN', mode: 'practice');
      expect(saved, isNotNull);
      expect(saved!.lastQuestionId, 'VLAN-0002');
      expect(saved.answeredCount, 3);
    });

    testWidgets('达标后回看旧题再点「继续答题」，仍然抽新题而不是走历史', (tester) async {
      final practice = _BankPracticeService(<Map<String, dynamic>>[
        for (var i = 1; i <= 8; i++) _bankJson(i),
      ]);
      await _launch(tester, practicePage(practice, target: 3));

      for (var i = 0; i < 3; i++) {
        await _tapOption(tester, 0);
        await _confirm(tester);
        if (i < 2) await _next(tester);
      }
      expect(find.text('已完成 3 题 · 答对 3'), findsOneWidget);

      await tester.tap(find.text('上一题'));
      await tester.pumpAndSettle();
      expect(find.text('题干 2'), findsOneWidget);

      await tester.tap(find.text('继续答题'));
      await tester.pumpAndSettle();

      expect(practice.drawCalls, 4, reason: '继续答题必须抽新题');
      expect(find.text('题干 4'), findsOneWidget);
      expect(find.text('第 4/4 题'), findsOneWidget);
    });

    testWidgets('回看历史时不能改已判分的答案，也不重复计数', (tester) async {
      final practice = _BankPracticeService(<Map<String, dynamic>>[
        for (var i = 1; i <= 6; i++) _bankJson(i),
      ]);
      await _launch(tester, practicePage(practice));

      await _tapOption(tester, 0);
      await _confirm(tester);
      await _next(tester);
      await tester.tap(find.text('上一题'));
      await tester.pumpAndSettle();

      await _tapOption(tester, 1);
      expect(practice.submitCalls, 1, reason: '已判分的题不许再提交');
      final tiles = tester
          .widgetList<OptionTile>(find.byType(OptionTile))
          .toList();
      expect(tiles[1].selected, isFalse);
      expect(find.text('第 1/20 题'), findsOneWidget);
    });
  });
}
