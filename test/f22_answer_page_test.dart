// F22 Chunk A：练习模式点选项即时判分（红绿 + 解析）。
//
// 判分必须不等网络：fake 的 submitAnswer 用 Completer 扣住响应，断言在
// 服务端一个字节都没返回时红绿与解析就已经在屏上。
// 考试模式作为对照：点选项只暂存，不判分、不出解析。
//
// F22 Chunk B：判分后的上一题 / 下一题导航。回看按题目 id 还原红绿与解析，
// 前进沿历史走、只有最新一题才抽新题，连点「下一题」由 _drawing 守卫兜底，
// 「继续答题」先跳回最新再抽新；考试导航零改动。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/core/kv_store.dart';
import 'package:routepass/core/theme.dart';
import 'package:routepass/models/exam.dart';
import 'package:routepass/models/practice.dart';
import 'package:routepass/models/question.dart';
import 'package:routepass/pages/bank/answer_widgets.dart';
import 'package:routepass/pages/bank/quiz_page.dart';
import 'package:routepass/services/bank/answer_record_service.dart';
import 'package:routepass/services/bank/answer_session_service.dart';
import 'package:routepass/services/bank/exam_service.dart';
import 'package:routepass/services/bank/practice_service.dart';

Question _question(
  int index, {
  String type = 'single',
  List<String> answer = const <String>['A'],
  String explanation = '解析内容',
}) {
  return Question(
    id: 'VLAN-${index.toString().padLeft(4, '0')}',
    module: 'VLAN',
    type: type,
    stem: '题干 $index',
    options: const <QuestionOption>[
      QuestionOption(key: 'A', text: 'A 选项'),
      QuestionOption(key: 'B', text: 'B 选项'),
      QuestionOption(key: 'C', text: 'C 选项'),
      QuestionOption(key: 'D', text: 'D 选项'),
    ],
    answer: answer,
    explanation: explanation,
    knowledge_point_id: 'VLAN-01',
    difficulty: 1,
    set_no: 1,
    row_version: 1,
  );
}

bool _sameKeys(List<String> a, List<String> b) {
  final sortedA = List<String>.of(a)..sort();
  final sortedB = List<String>.of(b)..sort();
  if (sortedA.length != sortedB.length) return false;
  for (var i = 0; i < sortedA.length; i++) {
    if (sortedA[i] != sortedB[i]) return false;
  }
  return true;
}

class _PracticeFake implements PracticeService {
  _PracticeFake(
    this.questions, {
    this.failSubmit = false,
    this.submitGate,
    this.drawGate,
    this.remote,
  });

  final List<Question> questions;

  /// 提交抛错（线上 /practice/submit 未就绪 / 500）。
  final bool failSubmit;

  /// 扣住提交响应：不 complete 就永远不返回，用来证明判分不等网络。
  final Completer<void>? submitGate;

  /// 扣住第二次起的抽题响应（首抽发生在进页时，不能被扣住），
  /// 用来制造连点「下一题」时抽题仍在飞的窗口。
  final Completer<void>? drawGate;

  /// 固定返回值（Mock 形状 `correct: null, explanation: ''`）。
  final AnswerResult? remote;

  int submitCalls = 0;
  int drawCalls = 0;

  @override
  Future<PracticeRecordDetail?> getRecordDetail(String sessionId) async => null;

  @override
  Future<bool> deleteRecord(String sessionId) async => false;

  @override
  Future<PracticeRecordPaper?> getRecordPaper(String sessionId) async => null;

  @override
  Future<PracticeNext?> drawNextQuestion({
    required String setId,
    String? module,
    required Set<String> excludedIds,
    String? sessionId,
  }) async {
    drawCalls++;
    if (drawGate != null && drawCalls > 1) await drawGate!.future;
    for (final q in questions) {
      if (!excludedIds.contains(q.id)) {
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
    if (submitGate != null) await submitGate!.future;
    if (failSubmit) throw Exception('POST /practice/submit 500');
    if (remote != null) return remote!;
    final q = questions.firstWhere((q) => q.id == questionId);
    return AnswerResult(
      correct: q.answer.isEmpty ? null : _sameKeys(chosen, q.answer),
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

class _ExamFake implements ExamService {
  _ExamFake(this.questions);

  final List<Question> questions;
  int submitCalls = 0;
  int saveCalls = 0;

  @override
  Future<ExamSession> startExam({required int drawCount, String? setId}) async {
    return ExamSession(
      id: 'E-1',
      started_at: DateTime.now().millisecondsSinceEpoch,
      total: questions.length,
      detail: '',
      snapshot: questions
          .map(
            (q) => ExamSnapshot(
              stem: q.stem,
              options: q.options,
              answer: q.answer,
              analysis: q.explanation,
            ),
          )
          .toList(),
    );
  }

  @override
  Future<ExamStart> startExamPaper({
    required int drawCount,
    String? setId,
  }) async {
    return examStartFromSession(
      await startExam(drawCount: drawCount, setId: setId),
    );
  }

  @override
  Future<void> saveAnswer({
    required String examId,
    required String questionId,
    required List<String> chosen,
    required String opId,
  }) async {
    saveCalls++;
  }

  @override
  Future<ExamResult?> submitExam({
    required String examId,
    required Map<String, List<String>> answers,
    required int durationMs,
  }) async {
    submitCalls++;
    return ExamResult(score: 60, passed: true, detail: '');
  }

  @override
  Future<ExamSession?> getExam(String examId) async => null;

  @override
  Future<List<ExamSession>> getHistory() async => <ExamSession>[];

  @override
  Future<ExamRecovery?> loadExamForResume(String examId) async => null;

  @override
  Future<Map<String, ExamQuestionGrade>> loadExamGrading(String examId) async =>
      const <String, ExamQuestionGrade>{};
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

List<OptionTileState> _states(WidgetTester tester) => tester
    .widgetList<OptionTile>(find.byType(OptionTile))
    .map((t) => t.state)
    .toList();

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
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

  Widget practicePage(_PracticeFake practice, {int target = 20}) {
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

  Widget examPage(_ExamFake exam) {
    return QuizPage(
      args: <String, Object?>{
        'mode': 'exam',
        'setId': 'h3cne-2026-01',
        'setTitle': 'A卷',
        'drawCount': 3,
      },
      examService: exam,
      recordService: records,
      sessionService: sessions,
    );
  }

  group('F22 练习：点选项即时判分', () {
    testWidgets('点错项：所选项红、正确项绿、下方出解析，全程不等提交返回', (tester) async {
      final gate = Completer<void>();
      final practice = _PracticeFake(<Question>[
        _question(1, explanation: 'VLAN 1 是默认 VLAN，不能删除'),
        _question(2),
      ], submitGate: gate);
      await _launch(tester, practicePage(practice));

      await _tapOption(tester, 1); // 选 B，正确答案是 A

      expect(practice.submitCalls, 1, reason: '提交已发出但被扣住');
      expect(_states(tester), <OptionTileState>[
        OptionTileState.correct,
        OptionTileState.wrong,
        OptionTileState.idle,
        OptionTileState.idle,
      ], reason: '服务端还没返回，红绿就必须已经出来');
      expect(find.text('确认作答'), findsNothing, reason: '单选不再需要确认作答');
      expect(find.text('下一题'), findsOneWidget);

      await _scrollTo(tester, find.text('VLAN 1 是默认 VLAN，不能删除'));
      expect(find.text('VLAN 1 是默认 VLAN，不能删除'), findsOneWidget);
      expect(find.text('你的答案：B'), findsOneWidget);

      gate.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('点对项：所选项绿、其余不着色、下方仍出解析', (tester) async {
      final gate = Completer<void>();
      final practice = _PracticeFake(<Question>[
        _question(1, explanation: 'Access 口只属于一个 VLAN'),
        _question(2),
      ], submitGate: gate);
      await _launch(tester, practicePage(practice));

      await _tapOption(tester, 0); // 选 A，正确

      expect(_states(tester), <OptionTileState>[
        OptionTileState.correct,
        OptionTileState.idle,
        OptionTileState.idle,
        OptionTileState.idle,
      ]);
      expect(find.text('下一题'), findsOneWidget);
      await _scrollTo(tester, find.text('Access 口只属于一个 VLAN'));
      expect(find.text('Access 口只属于一个 VLAN'), findsOneWidget);
      expect(find.text('你的答案：A'), findsOneWidget);
      expect(find.text('本次 · 已答 1/20 题 · 答对 1 题'), findsOneWidget);

      gate.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('题目解析为空：显示「解析待接口」，不编造解析文本', (tester) async {
      final practice = _PracticeFake(<Question>[
        _question(1, explanation: ''),
        _question(2),
      ], remote: const AnswerResult(correct: null, explanation: ''));
      await _launch(tester, practicePage(practice));

      await _tapOption(tester, 1);

      expect(_states(tester)[1], OptionTileState.wrong);
      expect(_states(tester)[0], OptionTileState.correct);
      await _scrollTo(tester, find.text('解析待接口'));
      expect(find.text('解析待接口'), findsOneWidget);
    });

    testWidgets('服务端解析为空但题目有解析：用题目解析，红绿不被 Mock 结果抹掉', (tester) async {
      final practice = _PracticeFake(<Question>[
        _question(1, explanation: 'Trunk 口允许多个 VLAN 通过'),
        _question(2),
      ], remote: const AnswerResult(correct: null, explanation: ''));
      await _launch(tester, practicePage(practice));

      await _tapOption(tester, 0);
      await tester.pumpAndSettle();

      expect(
        _states(tester).first,
        OptionTileState.correct,
        reason: 'correct: null 的返回不得把已判好的绿抹成已选',
      );
      await _scrollTo(tester, find.text('Trunk 口允许多个 VLAN 通过'));
      expect(find.text('Trunk 口允许多个 VLAN 通过'), findsOneWidget);
      expect(find.text('解析待接口'), findsNothing);
    });

    testWidgets('服务端返回解析时以服务端为准', (tester) async {
      final practice = _PracticeFake(<Question>[
        _question(1, explanation: '题目自带解析'),
        _question(2),
      ], remote: const AnswerResult(correct: true, explanation: '服务端解析'));
      await _launch(tester, practicePage(practice));

      await _tapOption(tester, 0);
      await _scrollTo(tester, find.text('服务端解析'));
      expect(find.text('服务端解析'), findsOneWidget);
      expect(find.text('题目自带解析'), findsNothing);
    });

    testWidgets('没有答案键：只标已选不涂红，解析区仍显示「解析待接口」', (tester) async {
      final practice = _PracticeFake(<Question>[
        _question(1, answer: const <String>[], explanation: ''),
        _question(2),
      ]);
      await _launch(tester, practicePage(practice));

      await _tapOption(tester, 1);

      expect(
        _states(tester),
        isNot(contains(OptionTileState.wrong)),
        reason: '没有判分依据就不能说用户答错',
      );
      expect(_states(tester)[1], OptionTileState.selected);
      expect(find.text('下一题'), findsOneWidget);
      await _scrollTo(tester, find.text('解析待接口'));
      expect(find.text('解析待接口'), findsOneWidget);
    });

    testWidgets('多选不即时判分：选完点「确认作答」才出红绿与解析', (tester) async {
      final practice = _PracticeFake(<Question>[
        _question(
          1,
          type: 'multiple',
          answer: const <String>['A', 'C'],
          explanation: 'A、C 都是 Trunk 允许通过的 VLAN',
        ),
        _question(2),
      ]);
      await _launch(tester, practicePage(practice));

      await _tapOption(tester, 0);
      expect(practice.submitCalls, 0, reason: '多选没选完不许判分');
      expect(_states(tester).first, OptionTileState.selected);
      expect(find.text('解析'), findsNothing);
      expect(find.text('确认作答'), findsOneWidget);

      await _tapOption(tester, 2);
      expect(practice.submitCalls, 0);
      expect(find.text('解析'), findsNothing);

      await tester.tap(find.text('确认作答'));
      await tester.pumpAndSettle();

      expect(practice.submitCalls, 1);
      expect(_states(tester), <OptionTileState>[
        OptionTileState.correct,
        OptionTileState.idle,
        OptionTileState.correct,
        OptionTileState.idle,
      ]);
      await _scrollTo(tester, find.text('A、C 都是 Trunk 允许通过的 VLAN'));
      expect(find.text('A、C 都是 Trunk 允许通过的 VLAN'), findsOneWidget);
    });

    testWidgets('提交失败：已显示的红绿与解析保留，只提示重试', (tester) async {
      final practice = _PracticeFake(<Question>[
        _question(1, explanation: '解析不因提交失败消失'),
        _question(2),
      ], failSubmit: true);
      await _launch(tester, practicePage(practice));

      await _tapOption(tester, 1);

      expect(find.text('提交失败，请重试'), findsOneWidget);
      expect(_states(tester)[1], OptionTileState.wrong);
      expect(_states(tester)[0], OptionTileState.correct);
      expect(find.text('下一题'), findsOneWidget);
      await _scrollTo(tester, find.text('解析不因提交失败消失'));
      expect(find.text('解析不因提交失败消失'), findsOneWidget);
    });

    testWidgets('提交未返回也能点「下一题」：新题不判分，旧题判分不丢', (tester) async {
      final gate = Completer<void>();
      final practice = _PracticeFake(<Question>[
        _question(1),
        _question(2),
      ], submitGate: gate);
      await _launch(tester, practicePage(practice));

      await _tapOption(tester, 1);
      await tester.tap(find.text('下一题'));
      await tester.pumpAndSettle();

      expect(find.text('题干 2'), findsOneWidget);
      expect(find.text('第 2/20 题'), findsOneWidget);
      expect(_states(tester), everyElement(OptionTileState.idle));
      expect(find.text('确认作答'), findsOneWidget);
      expect(find.text('解析'), findsNothing);

      gate.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('上一题'));
      await tester.pumpAndSettle();
      expect(_states(tester)[1], OptionTileState.wrong, reason: '旧题判分要带回来');
      expect(_states(tester)[0], OptionTileState.correct);
    });

    testWidgets('已判分的题再点别的选项：答案不变、不重复提交、不重复计数', (tester) async {
      final practice = _PracticeFake(<Question>[_question(1), _question(2)]);
      await _launch(tester, practicePage(practice));

      await _tapOption(tester, 1);
      await _tapOption(tester, 0);

      expect(practice.submitCalls, 1);
      expect(_states(tester)[1], OptionTileState.wrong);
      expect(_states(tester)[0], OptionTileState.correct);
      expect(
        tester
            .widgetList<OptionTile>(find.byType(OptionTile))
            .map((t) => t.selected)
            .toList(),
        <bool>[false, true, false, false],
      );
      expect(find.text('本次 · 已答 1/20 题 · 答对 0 题'), findsOneWidget);
    });

    testWidgets('判断题同样点选项即判分', (tester) async {
      final practice = _PracticeFake(<Question>[
        _question(
          1,
          type: 'judge',
          answer: const <String>['B'],
          explanation: '默认 VLAN 可以删除，但要先改端口归属',
        ),
        _question(2),
      ]);
      await _launch(tester, practicePage(practice));

      await _tapOption(tester, 0);

      expect(_states(tester)[0], OptionTileState.wrong);
      expect(_states(tester)[1], OptionTileState.correct);
      expect(find.text('下一题'), findsOneWidget);
      await _scrollTo(tester, find.text('默认 VLAN 可以删除，但要先改端口归属'));
      expect(find.text('默认 VLAN 可以删除，但要先改端口归属'), findsOneWidget);
    });
  });

  group('F22 练习：判分后上一题 / 下一题导航', () {
    testWidgets('回上一题：红绿与解析按题目 id 还原，题号退回，不重复提交不重复计数', (tester) async {
      final practice = _PracticeFake(<Question>[
        _question(1, explanation: 'VLAN 1 是默认 VLAN，不能删除'),
        _question(2),
      ]);
      await _launch(tester, practicePage(practice));

      await _tapOption(tester, 1); // 题干 1 选 B，判错
      await tester.tap(find.text('下一题'));
      await tester.pumpAndSettle();
      expect(find.text('题干 2'), findsOneWidget);
      expect(practice.drawCalls, 2);

      await tester.tap(find.text('上一题'));
      await tester.pumpAndSettle();

      expect(find.text('题干 1'), findsOneWidget);
      expect(find.text('第 1/20 题'), findsOneWidget, reason: '题号跟着历史位置退回');
      expect(_states(tester), <OptionTileState>[
        OptionTileState.correct,
        OptionTileState.wrong,
        OptionTileState.idle,
        OptionTileState.idle,
      ], reason: '回看必须带回红绿判分');
      expect(find.text('本次 · 已答 1/20 题 · 答对 0 题'), findsOneWidget);
      expect(practice.submitCalls, 1, reason: '回看不得重新提交');
      expect(practice.drawCalls, 2, reason: '回看不得抽新题');

      await _tapOption(tester, 0); // 已判分，改不了答案
      expect(practice.submitCalls, 1);
      expect(_states(tester)[1], OptionTileState.wrong);

      await _scrollTo(tester, find.text('VLAN 1 是默认 VLAN，不能删除'));
      expect(
        find.text('VLAN 1 是默认 VLAN，不能删除'),
        findsOneWidget,
        reason: '解析也要带回来',
      );
      expect(find.text('你的答案：B'), findsOneWidget);
    });

    testWidgets('前进沿历史回到已判分的题：不抽新题，红绿与解析仍在', (tester) async {
      final practice = _PracticeFake(<Question>[
        _question(1, explanation: '第一题解析'),
        _question(2, explanation: '第二题解析'),
        _question(3),
      ]);
      await _launch(tester, practicePage(practice));

      await _tapOption(tester, 1); // 题干 1 判错
      await tester.tap(find.text('下一题'));
      await tester.pumpAndSettle();
      await _tapOption(tester, 0); // 题干 2 判对
      expect(practice.drawCalls, 2);

      await tester.tap(find.text('上一题'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('下一题'));
      await tester.pumpAndSettle();

      expect(find.text('题干 2'), findsOneWidget);
      expect(find.text('第 2/20 题'), findsOneWidget);
      expect(practice.drawCalls, 2, reason: '沿历史前进不得抽新题');
      expect(practice.submitCalls, 2, reason: '沿历史前进不得重新提交');
      expect(_states(tester), <OptionTileState>[
        OptionTileState.correct,
        OptionTileState.idle,
        OptionTileState.idle,
        OptionTileState.idle,
      ]);
      expect(find.text('下一题'), findsOneWidget);
      await _scrollTo(tester, find.text('第二题解析'));
      expect(find.text('第二题解析'), findsOneWidget);
      expect(find.text('你的答案：A'), findsOneWidget);
    });

    testWidgets('只有走到最新一题才抽新题：题号跟着历史位置走', (tester) async {
      final practice = _PracticeFake(<Question>[
        _question(1),
        _question(2),
        _question(3),
      ]);
      await _launch(tester, practicePage(practice));

      await _tapOption(tester, 0);
      await tester.tap(find.text('下一题'));
      await tester.pumpAndSettle();
      expect(find.text('第 2/20 题'), findsOneWidget);
      expect(practice.drawCalls, 2);

      await tester.tap(find.text('上一题'));
      await tester.pumpAndSettle();
      expect(find.text('第 1/20 题'), findsOneWidget);

      await tester.tap(find.text('下一题'));
      await tester.pumpAndSettle();
      expect(practice.drawCalls, 2, reason: '历史里还有下一题，不许抽新');
      expect(find.text('题干 2'), findsOneWidget);
      expect(find.text('确认作答'), findsOneWidget, reason: '历史里的未判分题保持未判分');

      await _tapOption(tester, 0); // 判分后才轮到抽新题
      await tester.tap(find.text('下一题'));
      await tester.pumpAndSettle();
      expect(practice.drawCalls, 3);
      expect(find.text('题干 3'), findsOneWidget);
      expect(find.text('第 3/20 题'), findsOneWidget);
      expect(_states(tester), everyElement(OptionTileState.idle));
    });

    testWidgets('连点「下一题」：抽题期间只抽一次不跳题，判分提交在飞也不受影响', (tester) async {
      final submitGate = Completer<void>();
      final drawGate = Completer<void>();
      final practice = _PracticeFake(
        <Question>[_question(1), _question(2), _question(3)],
        submitGate: submitGate,
        drawGate: drawGate,
      );
      await _launch(tester, practicePage(practice));

      await _tapOption(tester, 1); // 题干 1 判分，提交被扣住
      expect(practice.submitCalls, 1);

      await tester.tap(find.text('下一题'));
      await tester.pump();
      await tester.tap(find.text('下一题'));
      await tester.pump();
      expect(practice.drawCalls, 2, reason: '第二次点击必须被 _drawing 守卫挡住');

      drawGate.complete();
      await tester.pumpAndSettle();
      expect(find.text('题干 2'), findsOneWidget, reason: '跳过题干 2 直达题干 3 就是跳题');
      expect(find.text('第 2/20 题'), findsOneWidget);
      expect(practice.drawCalls, 2);
      expect(_states(tester), everyElement(OptionTileState.idle));

      submitGate.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('上一题'));
      await tester.pumpAndSettle();
      expect(find.text('题干 1'), findsOneWidget);
      expect(
        _states(tester)[1],
        OptionTileState.wrong,
        reason: '后台提交返回后，旧题判分仍要带回来',
      );
      expect(_states(tester)[0], OptionTileState.correct);
    });

    testWidgets('达标后回看旧题点「继续答题」：先跳回最新一题再抽新题', (tester) async {
      final practice = _PracticeFake(<Question>[
        _question(1),
        _question(2),
        _question(3),
      ]);
      await _launch(tester, practicePage(practice, target: 2));

      await _tapOption(tester, 1); // 题干 1 判错
      await tester.tap(find.text('下一题'));
      await tester.pumpAndSettle();
      await _tapOption(tester, 0); // 题干 2 判对 → 达标
      expect(find.text('已完成 2 题 · 答对 1'), findsOneWidget);

      await tester.tap(find.text('上一题'));
      await tester.pumpAndSettle();
      expect(find.text('题干 1'), findsOneWidget);
      expect(find.text('继续答题'), findsOneWidget);

      await tester.tap(find.text('继续答题'));
      await tester.pumpAndSettle();

      expect(
        find.text('题干 3'),
        findsOneWidget,
        reason: '继续答题必须抽新题，而不是沿历史走到题干 2',
      );
      expect(find.text('第 3/3 题'), findsOneWidget, reason: '达标后分母跟着累计题数长大');
      expect(practice.drawCalls, 3);
      expect(find.text('继续答题'), findsNothing);
      expect(find.text('确认作答'), findsOneWidget);
      expect(_states(tester), everyElement(OptionTileState.idle));
    });
  });

  group('F22 考试：行为零改动', () {
    testWidgets('点选项只暂存：不判分、不出解析，交卷后才判', (tester) async {
      final exam = _ExamFake(<Question>[
        for (var i = 1; i <= 3; i++) _question(i),
      ]);
      await _launch(tester, examPage(exam));

      await _tapOption(tester, 1); // 选 B，卷面正确答案是 A

      expect(exam.saveCalls, 1);
      expect(exam.submitCalls, 0);
      expect(_states(tester), <OptionTileState>[
        OptionTileState.idle,
        OptionTileState.selected,
        OptionTileState.idle,
        OptionTileState.idle,
      ], reason: '考试不许即时涂红绿');
      expect(find.text('解析'), findsNothing);
      expect(find.text('解析内容'), findsNothing);
      expect(find.text('下一题'), findsOneWidget);

      await tester.tap(find.text('下一题'));
      await tester.pumpAndSettle();
      await _tapOption(tester, 0);
      await tester.tap(find.text('下一题'));
      await tester.pumpAndSettle();
      await _tapOption(tester, 0);
      await tester.tap(find.text('交卷'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '确认交卷'));
      await tester.pumpAndSettle();
      expect(exam.submitCalls, 1);

      await tester.tap(find.text('题干 1'));
      await tester.pumpAndSettle();
      expect(_states(tester), <OptionTileState>[
        OptionTileState.correct,
        OptionTileState.wrong,
        OptionTileState.idle,
        OptionTileState.idle,
      ], reason: '交卷后回顾才判分');
      await _scrollTo(tester, find.text('解析内容'));
      expect(find.text('解析内容'), findsOneWidget);
    });

    testWidgets('卷面无答案：点选项不涂红（P1-4 守卫仍在）', (tester) async {
      final exam = _ExamFake(<Question>[
        for (var i = 1; i <= 3; i++) _question(i, answer: const <String>[]),
      ]);
      await _launch(tester, examPage(exam));

      await _tapOption(tester, 1);

      expect(_states(tester), isNot(contains(OptionTileState.wrong)));
      expect(_states(tester)[1], OptionTileState.selected);
      expect(find.text('解析'), findsNothing);
      expect(find.textContaining('正确答案：'), findsNothing);
    });

    testWidgets('考试导航零改动：上一题只还原已选选项，不判分不出解析', (tester) async {
      final exam = _ExamFake(<Question>[
        for (var i = 1; i <= 3; i++) _question(i),
      ]);
      await _launch(tester, examPage(exam));

      await _tapOption(tester, 1);
      await tester.tap(find.text('下一题'));
      await tester.pumpAndSettle();
      expect(find.text('第 2/3 题'), findsOneWidget);

      await tester.tap(find.text('上一题'));
      await tester.pumpAndSettle();
      expect(find.text('第 1/3 题'), findsOneWidget);
      expect(_states(tester), <OptionTileState>[
        OptionTileState.idle,
        OptionTileState.selected,
        OptionTileState.idle,
        OptionTileState.idle,
      ], reason: '考试回看只标已选，不许涂红绿');
      expect(find.text('解析'), findsNothing);
      expect(find.text('下一题'), findsOneWidget);

      await tester.tap(find.text('下一题'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('下一题'));
      await tester.pumpAndSettle();
      expect(find.text('第 3/3 题'), findsOneWidget);
      expect(find.text('交卷'), findsOneWidget);
      expect(exam.submitCalls, 0, reason: '导航不得触发交卷');
    });
  });
}
