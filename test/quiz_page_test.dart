import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/core/kv_store.dart';
import 'package:routepass/core/theme.dart';
import 'package:routepass/models/answer_session_state.dart';
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
    explanation: '解析内容',
    knowledge_point_id: 'VLAN-01',
    difficulty: 1,
    set_no: 1,
    row_version: 1,
  );
}

class _FakePracticeService implements PracticeService {
  _FakePracticeService(this.questions, {this.failSubmit = false});

  final List<Question> questions;
  bool failSubmit;
  int submitCalls = 0;
  int startSessionCalls = 0;
  int endSessionCalls = 0;
  PracticeSessionInfo? serverSession;
  List<String> serverAnsweredIds = const <String>[];
  String? lastDrawSessionId;

  @override
  Future<PracticeNext?> drawNextQuestion({
    required String setId,
    String? module,
    required Set<String> excludedIds,
    String? sessionId,
  }) async {
    lastDrawSessionId = sessionId;
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
    if (failSubmit) throw Exception('submit failed');
    submitCalls++;
    final q = questions.firstWhere((q) => q.id == questionId);
    final correct =
        chosen.length == q.answer.length &&
        chosen.toSet().containsAll(q.answer);
    return AnswerResult(
      correct: correct,
      explanation: '解析内容',
      correctKeys: q.answer,
      opId: opId,
    );
  }

  @override
  Future<PracticeSession> startSession({
    required List<Question> questions,
    required String mode,
  }) async {
    return PracticeSession(
      id: 'S-1',
      questions: questions,
      mode: mode,
      total: questions.length,
    );
  }

  @override
  Future<ContinueSession?> resumeSession({required String setId}) async => null;

  @override
  Future<ContinueSession?> getContinueSession() async => null;

  @override
  Future<PracticeSessionInfo?> startPracticeSession({String? module}) async {
    startSessionCalls++;
    return serverSession;
  }

  @override
  Future<PracticeSessionInfo?> fetchPracticeSession(String sessionId) async {
    final info = serverSession;
    if (info == null) return null;
    return PracticeSessionInfo(
      id: info.id,
      module: info.module,
      status: info.status,
      answeredCount: info.answeredCount,
      correctCount: info.correctCount,
      startedAt: info.startedAt,
      answeredQuestionIds: serverAnsweredIds,
    );
  }

  @override
  Future<PracticeSessionInfo?> endPracticeSession(String sessionId) async {
    endSessionCalls++;
    return serverSession;
  }

  @override
  Future<List<PracticeRecordSummary>> fetchPracticeRecords({
    int page = 1,
    int pageSize = 20,
  }) async => const <PracticeRecordSummary>[];

  @override
  Future<List<PracticeModuleProgress>> fetchPracticeProgress() async =>
      const <PracticeModuleProgress>[];
}

class _FakeExamService implements ExamService {
  _FakeExamService(this.questions);

  final List<Question> questions;
  int submitCalls = 0;
  int saveCalls = 0;
  int? score = 78;

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
    return ExamResult(score: score, passed: true, detail: '');
  }

  @override
  Future<ExamSession?> getExam(String examId) async => null;

  @override
  Future<List<ExamSession>> getHistory() async => <ExamSession>[];

  ExamRecovery? recovery;

  @override
  Future<ExamRecovery?> loadExamForResume(String examId) async => recovery;
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

Future<void> _tapOption(WidgetTester tester, List<String> keys) async {
  for (final key in keys) {
    await tester.tap(find.text('$key 选项'));
    await tester.pump();
  }
}

Future<void> _confirm(WidgetTester tester) async {
  await tester.tap(find.text('确认作答'));
  await tester.pumpAndSettle();
}

Future<void> _next(WidgetTester tester) async {
  await tester.tap(find.text('下一题'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('QuizPage practice', () {
    late KvStore kv;
    late KvAnswerRecordService records;
    late KvAnswerSessionService sessions;

    setUp(() {
      kv = InMemoryKvStore();
      records = KvAnswerRecordService(kvStore: kv);
      sessions = KvAnswerSessionService(kvStore: kv);
    });

    Widget practicePage(_FakePracticeService practice, {int target = 20}) {
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

    testWidgets('单选判分后正确项着色、显示正确答案与解析', (tester) async {
      final practice = _FakePracticeService(<Question>[
        for (var i = 1; i <= 10; i++) _question(i),
      ]);
      await _launch(tester, practicePage(practice));

      expect(find.text('第 1/20 题'), findsOneWidget);
      await _tapOption(tester, <String>['A']);
      await _confirm(tester);

      expect(find.text('正确答案：A'), findsOneWidget);
      final tiles = tester
          .widgetList<OptionTile>(find.byType(OptionTile))
          .toList();
      expect(tiles[0].state, OptionTileState.correct);
      expect(tiles[1].state, OptionTileState.idle);
      expect(find.text('下一题'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('解析内容'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('解析内容'), findsOneWidget);
    });

    testWidgets('多选判分后 A/C 正确、B 未选中', (tester) async {
      final practice = _FakePracticeService(<Question>[
        _question(1, type: 'multiple', answer: const <String>['A', 'C']),
        for (var i = 2; i <= 10; i++) _question(i),
      ]);
      await _launch(tester, practicePage(practice));

      await _tapOption(tester, <String>['A', 'C']);
      await _confirm(tester);

      final tiles = tester
          .widgetList<OptionTile>(find.byType(OptionTile))
          .toList();
      expect(tiles[0].state, OptionTileState.correct);
      expect(tiles[1].state, OptionTileState.idle);
      expect(tiles[2].state, OptionTileState.correct);
      expect(find.text('正确答案：A、C'), findsOneWidget);
    });

    testWidgets('答满 20 写 completion；继续到 35 只更新同一条且无断点', (tester) async {
      final practice = _FakePracticeService(<Question>[
        for (var i = 1; i <= 40; i++) _question(i),
      ]);
      await _launch(tester, practicePage(practice));

      for (var i = 0; i < 35; i++) {
        await _tapOption(tester, <String>['A']);
        await _confirm(tester);
        if (i == 19) {
          expect(find.text('已完成 20 题 · 答对 20'), findsOneWidget);
          expect(
            records
                .recordsFor(setId: 'VLAN', mode: 'practice')
                .single
                .answeredCount,
            20,
          );
          await tester.tap(find.text('继续答题'));
          await tester.pumpAndSettle();
          continue;
        }
        if (i < 34) await _next(tester);
      }

      final list = records.recordsFor(setId: 'VLAN', mode: 'practice');
      expect(list.length, 1);
      expect(list.single.kind, 'completion');
      expect(list.single.answeredCount, 35);
      expect(list.single.correctCount, 35);
      expect(records.breakpointOf(setId: 'VLAN', mode: 'practice'), isNull);
    });

    testWidgets('答 15 题退出写 breakpoint，重进恢复到第 16 题', (tester) async {
      final practice = _FakePracticeService(<Question>[
        for (var i = 1; i <= 40; i++) _question(i),
      ]);
      await _launch(tester, practicePage(practice));

      for (var i = 0; i < 15; i++) {
        await _tapOption(tester, <String>['A']);
        await _confirm(tester);
        if (i < 14) await _next(tester);
      }

      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('退出并保留进度'));
      await tester.pumpAndSettle();

      final bp = records.breakpointOf(setId: 'VLAN', mode: 'practice');
      expect(bp, isNotNull);
      expect(bp!.answeredCount, 15);

      await _launch(tester, practicePage(practice));
      expect(find.text('第 16/20 题'), findsOneWidget);
      expect(find.text('题干 16'), findsOneWidget);
    });

    testWidgets('断点续答到目标后回收旧断点，记录只留一条完成', (tester) async {
      final practice = _FakePracticeService(<Question>[
        for (var i = 1; i <= 40; i++) _question(i),
      ]);
      await _launch(tester, practicePage(practice));

      for (var i = 0; i < 15; i++) {
        await _tapOption(tester, <String>['A']);
        await _confirm(tester);
        if (i < 14) await _next(tester);
      }
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('退出并保留进度'));
      await tester.pumpAndSettle();
      expect(records.breakpointOf(setId: 'VLAN', mode: 'practice'), isNotNull);

      await _launch(tester, practicePage(practice));
      expect(find.text('第 16/20 题'), findsOneWidget);
      for (var i = 0; i < 5; i++) {
        await _tapOption(tester, <String>['A']);
        await _confirm(tester);
        if (i < 4) await _next(tester);
      }

      final list = records.recordsFor(setId: 'VLAN', mode: 'practice');
      expect(list.length, 1, reason: '旧断点必须被完成记录回收');
      expect(list.single.kind, 'completion');
      expect(list.single.answeredCount, 20);
      expect(records.breakpointOf(setId: 'VLAN', mode: 'practice'), isNull);
    });

    testWidgets('提交失败不本地判分、不写记录', (tester) async {
      final practice = _FakePracticeService(<Question>[
        for (var i = 1; i <= 10; i++) _question(i),
      ], failSubmit: true);
      await _launch(tester, practicePage(practice));

      await _tapOption(tester, <String>['A']);
      await _confirm(tester);

      expect(find.text('提交失败，请重试'), findsOneWidget);
      expect(find.text('正确答案：A'), findsNothing);
      expect(find.text('确认作答'), findsOneWidget);
      expect(records.recordsFor(setId: 'VLAN', mode: 'practice'), isEmpty);
    });

    testWidgets('S11 会话：进页开/续会话，抽题与交卷带 sessionId，退出结束会话', (tester) async {
      final practice = _FakePracticeService(<Question>[
        for (var i = 1; i <= 10; i++) _question(i),
      ]);
      practice.serverSession = PracticeSessionInfo(
        id: 'sess-abc',
        module: 'VLAN',
        status: PracticeSessionInfo.statusInProgress,
        answeredCount: 0,
        correctCount: 0,
        startedAt: DateTime.now().millisecondsSinceEpoch,
      );
      await _launch(tester, practicePage(practice));

      expect(practice.startSessionCalls, 1, reason: 'POST /practice/sessions');
      expect(
        practice.lastDrawSessionId,
        'sess-abc',
        reason: '/practice/next 带会话',
      );

      await _tapOption(tester, <String>['A']);
      await _confirm(tester);
      expect(find.text('正确答案：A'), findsOneWidget);

      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('退出并保留进度'));
      await tester.pumpAndSettle();

      expect(practice.endSessionCalls, 1, reason: 'POST /sessions/{id}/end');
    });

    testWidgets('S11 续接：服务端 in_progress 会话的 answeredQuestionIds 恢复已答', (
      tester,
    ) async {
      final practice = _FakePracticeService(<Question>[
        for (var i = 1; i <= 10; i++) _question(i),
      ]);
      practice.serverSession = PracticeSessionInfo(
        id: 'sess-resume',
        module: 'VLAN',
        status: PracticeSessionInfo.statusInProgress,
        answeredCount: 2,
        correctCount: 1,
        startedAt: DateTime.now().millisecondsSinceEpoch,
      );
      practice.serverAnsweredIds = <String>['VLAN-0001', 'VLAN-0002'];
      await _launch(tester, practicePage(practice));

      expect(find.text('第 3/20 题'), findsOneWidget);
      expect(find.text('题干 3'), findsOneWidget);
    });
  });

  group('QuizPage exam', () {
    late KvStore kv;
    late KvAnswerRecordService records;
    late KvAnswerSessionService sessions;

    setUp(() {
      kv = InMemoryKvStore();
      records = KvAnswerRecordService(kvStore: kv);
      sessions = KvAnswerSessionService(kvStore: kv);
    });

    Widget examPage(_FakeExamService exam) {
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

    testWidgets('S11 考试恢复：本地无卷面时用 GET /exam/{id} 的 answers 列表还原', (
      tester,
    ) async {
      final questions = <Question>[for (var i = 1; i <= 3; i++) _question(i)];
      final exam = _FakeExamService(questions);
      exam.recovery = ExamRecovery(
        id: 'EX-9',
        questions: questions
            .map(
              (q) => Question(
                id: q.id,
                module: q.module,
                type: q.type,
                stem: q.stem,
                options: q.options,
                answer: const <String>[],
                explanation: '',
                knowledge_point_id: q.knowledge_point_id,
                difficulty: q.difficulty,
                set_no: q.set_no,
                row_version: q.row_version,
              ),
            )
            .toList(),
        answers: <String, List<String>>{
          'VLAN-0001': <String>['B'],
        },
        startedAt: DateTime.now().millisecondsSinceEpoch,
        total: 3,
      );
      sessions.save(
        AnswerSessionState(
          setId: 'h3cne-2026-01',
          setTitle: 'A卷',
          mode: 'exam',
          examId: 'EX-9',
          targetCount: 3,
          answeredCount: 0,
          correctCount: 0,
          answeredIds: const <String>[],
          answers: const <String, List<String>>{},
          startedAt: DateTime.now().millisecondsSinceEpoch,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );

      await _launch(tester, examPage(exam));

      expect(find.text('第 1/3 题'), findsOneWidget);
      final tiles = tester
          .widgetList<OptionTile>(find.byType(OptionTile))
          .toList();
      expect(tiles[1].state, OptionTileState.selected, reason: '恢复已保存选项 B');
    });

    testWidgets('作答只暂存，不判分、不显示解析；交卷写 completion', (tester) async {
      final exam = _FakeExamService(<Question>[
        for (var i = 1; i <= 3; i++) _question(i),
      ]);
      await _launch(tester, examPage(exam));

      expect(find.text('第 1/3 题'), findsOneWidget);
      await _tapOption(tester, <String>['A']);

      expect(exam.submitCalls, 0);
      expect(exam.saveCalls, 1);
      expect(find.text('解析'), findsNothing);
      expect(find.text('正确答案：A'), findsNothing);

      await tester.tap(find.text('下一题'));
      await tester.pumpAndSettle();
      await _tapOption(tester, <String>['A']);
      await tester.tap(find.text('下一题'));
      await tester.pumpAndSettle();
      await _tapOption(tester, <String>['A']);

      expect(find.text('交卷'), findsOneWidget);
      await tester.tap(find.text('交卷'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '确认交卷'));
      await tester.pumpAndSettle();

      expect(exam.submitCalls, 1);
      expect(find.text('78 分'), findsOneWidget);
      final list = records.recordsFor(setId: 'h3cne-2026-01', mode: 'exam');
      expect(list.length, 1);
      expect(list.single.kind, 'completion');
      expect(list.single.score, 78);
      expect(list.single.answeredCount, 3);
      expect(sessions.load(setId: 'h3cne-2026-01', mode: 'exam'), isNull);
    });

    testWidgets('未交卷退出写 breakpoint，重进恢复 answers 与位置', (tester) async {
      final exam = _FakeExamService(<Question>[
        for (var i = 1; i <= 3; i++) _question(i),
      ]);
      await _launch(tester, examPage(exam));

      await _tapOption(tester, <String>['A']);
      await tester.tap(find.text('下一题'));
      await tester.pumpAndSettle();
      await _tapOption(tester, <String>['A']);

      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('退出并保留进度'));
      await tester.pumpAndSettle();

      final bp = records.breakpointOf(setId: 'h3cne-2026-01', mode: 'exam');
      expect(bp, isNotNull);
      expect(bp!.answeredCount, 2);
      expect(exam.submitCalls, 0);

      await _launch(tester, examPage(exam));
      expect(find.text('第 2/3 题'), findsOneWidget);
      final tiles = tester
          .widgetList<OptionTile>(find.byType(OptionTile))
          .toList();
      expect(tiles[0].state, OptionTileState.selected);
    });
  });
}
