/// F32：两个纯显示问题的回归测试。
///
/// 问题一：练习达标后「继续答题」，已答数如实超过目标（数据正确），
/// 摘要与记录行不得再显示 21/20 这种假比例——分母跟着已答数长大。
/// 问题二：考试回顾卷面不含答案（q.answer 为空），解析卡自己的
/// 「正确答案」行必须显示服务端判分答案，而不是「样例数据，无答案」；
/// 判分为空 / 样例题的占位行为保持不变，绝不编造答案。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/core/kv_store.dart';
import 'package:routepass/models/answer_record.dart';
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
import 'package:routepass/services/mock/mock_favorite_service.dart';
import 'package:routepass/widgets/answer_records_card.dart';

const List<QuestionOption> _options = <QuestionOption>[
  QuestionOption(key: 'A', text: '选项甲'),
  QuestionOption(key: 'B', text: '选项乙'),
  QuestionOption(key: 'C', text: '选项丙'),
  QuestionOption(key: 'D', text: '选项丁'),
];

Question _question(int index, {List<String> answer = const <String>['A']}) {
  return Question(
    id: 'VLAN-${index.toString().padLeft(4, '0')}',
    module: 'VLAN',
    type: 'single',
    stem: '题干 $index',
    options: _options,
    answer: answer,
    explanation: '解析内容',
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
  _PracticeFake(this.questions);

  final List<Question> questions;
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

ExamSnapshot _snapshot(String stem) {
  return ExamSnapshot(
    stem: stem,
    options: _options,
    answer: const <String>[],
    analysis: '',
  );
}

class _ExamFake implements ExamService {
  _ExamFake({this.grading = const <String, ExamQuestionGrade>{}});

  final Map<String, ExamQuestionGrade> grading;

  @override
  Future<ExamSession> startExam({required int drawCount, String? setId}) async {
    return ExamSession(
      id: 'exam-1',
      started_at: 1700000000000,
      total: 2,
      detail: '',
      snapshot: <ExamSnapshot>[_snapshot('题干一'), _snapshot('题干二')],
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
  }) async {}

  @override
  Future<ExamResult?> submitExam({
    required String examId,
    required Map<String, List<String>> answers,
    required int durationMs,
  }) async {
    return ExamResult(score: 50, passed: null, detail: '');
  }

  @override
  Future<ExamSession?> getExam(String examId) async => null;

  @override
  Future<List<ExamSession>> getHistory() async => const <ExamSession>[];

  @override
  Future<ExamRecovery?> loadExamForResume(String examId) async => null;

  @override
  Future<Map<String, ExamQuestionGrade>> loadExamGrading(String examId) async =>
      grading;
}

class _FakeSessionService implements AnswerSessionService {
  @override
  AnswerSessionState? load({required String setId, required String mode}) =>
      null;

  @override
  void save(AnswerSessionState state) {}

  @override
  void clear({required String setId, required String mode}) {}
}

class _FakeRecordService implements AnswerRecordService {
  @override
  List<AnswerRecord> recordsFor({
    required String setId,
    required String mode,
  }) => const <AnswerRecord>[];

  @override
  AnswerRecord? breakpointOf({required String setId, required String mode}) =>
      null;

  @override
  void upsert(AnswerRecord record) {}

  @override
  void remove(String id) {}

  @override
  List<AnswerRecord> pendingSync() => const <AnswerRecord>[];

  @override
  void markSynced(String id, String serverId) {}

  @override
  Future<bool> syncFromServer() async => false;
}

const Map<String, ExamQuestionGrade> _grades = <String, ExamQuestionGrade>{
  'EXAM-0': ExamQuestionGrade(
    questionId: 'EXAM-0',
    chosen: <String>['A'],
    answer: <String>['B'],
    explanation: '服务端解析一',
    correct: false,
  ),
  'EXAM-1': ExamQuestionGrade(
    questionId: 'EXAM-1',
    chosen: <String>['B'],
    answer: <String>['B'],
    explanation: '服务端解析二',
    correct: true,
  ),
};

Finder _optionTile(String key) {
  return find.byWidgetPredicate((w) => w is OptionTile && w.option.key == key);
}

/// 页面有每秒 setState 的计时器，全程用固定时长 pump，不用 pumpAndSettle
/// （与 F24 考试链测试同一约定）。
Future<void> _pump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// 解析卡 / 记录卡在 800×600 测试视口的折叠线以下，ListView 的 children
/// 懒构建，先滚进构建窗口再断言文本（与 F22 / F24 同一约定）。
Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _pumpExamQuiz(WidgetTester tester, _ExamFake exam) async {
  await tester.pumpWidget(
    MaterialApp(
      home: QuizPage(
        args: const <String, Object?>{
          'mode': 'exam',
          'setId': 'h3cne-2026-01',
          'setTitle': '套卷一',
          'drawCount': 2,
        },
        examService: exam,
        recordService: _FakeRecordService(),
        sessionService: _FakeSessionService(),
      ),
    ),
  );
  await _pump(tester);
}

/// 第一题选 A、第二题选 B，交卷并确认，停在全屏评分页（F25）。
Future<void> _answerAndSubmit(WidgetTester tester) async {
  await tester.tap(_optionTile('A'));
  await _pump(tester);
  await tester.tap(find.text('下一题'));
  await _pump(tester);
  await tester.tap(_optionTile('B'));
  await _pump(tester);
  await tester.tap(find.text('交卷'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.tap(find.widgetWithText(FilledButton, '确认交卷'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump(const Duration(milliseconds: 600));
}

/// 点全屏评分页的「逐题回顾」进入回顾模式（落在第一题）。
Future<void> _enterReview(WidgetTester tester) async {
  await tester.tap(find.text('逐题回顾'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump(const Duration(milliseconds: 600));
}

AnswerRecord _record({
  required String kind,
  required int targetCount,
  required int answeredCount,
  int? correctCount,
}) {
  return AnswerRecord(
    id: 'rec-$kind',
    setId: 'VLAN',
    setTitle: 'VLAN',
    mode: 'practice',
    kind: kind,
    targetCount: targetCount,
    answeredCount: answeredCount,
    totalCount: 20,
    correctCount: correctCount,
    durationMs: 120000,
    createdAt: 1700000000000,
    updatedAt: 1700000000000,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('F32 问题一：已答数超过目标时显示诚实比例', () {
    testWidgets('练习达标后继续答题：摘要与记录行显示 3/3 而不是 3/2', (tester) async {
      final kv = InMemoryKvStore();
      final practice = _PracticeFake(<Question>[
        _question(1),
        _question(2),
        _question(3),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: QuizPage(
            args: const <String, Object?>{
              'mode': 'practice',
              'setId': 'VLAN',
              'setTitle': 'VLAN',
              'drawCount': 100,
              'target': 2,
            },
            practiceService: practice,
            recordService: KvAnswerRecordService(kvStore: kv),
            sessionService: KvAnswerSessionService(kvStore: kv),
            favoriteService: MockFavoriteService(),
          ),
        ),
      );
      await _pump(tester);

      await tester.tap(_optionTile('B')); // 题干 1 判错
      await _pump(tester);
      await tester.tap(find.text('下一题'));
      await _pump(tester);
      await tester.tap(_optionTile('A')); // 题干 2 判对 → 达标 2/2
      await _pump(tester);
      expect(find.text('已完成 2 题 · 答对 1'), findsOneWidget);

      await tester.tap(find.text('继续答题'));
      await _pump(tester);
      expect(find.text('题干 3'), findsOneWidget);
      expect(find.text('第 3/3 题'), findsOneWidget);

      await tester.tap(_optionTile('A')); // 题干 3 判对 → 已答 3 > 目标 2
      await _pump(tester);

      expect(find.textContaining('已答 3/2'), findsNothing);
      await _scrollTo(tester, find.text('已完成 · 3/3 题'));
      expect(
        find.text('本次 · 已答 3/3 题 · 答对 2 题'),
        findsOneWidget,
        reason: '已答数如实超过目标时，分母跟着已答数长大',
      );
      expect(
        find.text('已完成 · 3/3 题'),
        findsOneWidget,
        reason: '记录行同一口径：完成记录 3/2 数据显示为 3/3',
      );
    });

    testWidgets('记录卡：完成记录 21/20 显示为 21/21，断点 15/20 不受影响', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnswerRecordsCard(
              records: <AnswerRecord>[
                _record(
                  kind: 'completion',
                  targetCount: 20,
                  answeredCount: 21,
                  correctCount: 18,
                ),
                _record(
                  kind: 'breakpoint',
                  targetCount: 20,
                  answeredCount: 15,
                  correctCount: 10,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('已完成 · 21/21 题'), findsOneWidget);
      expect(find.textContaining('21/20'), findsNothing);
      expect(
        find.text('断点 · 15/20 题'),
        findsOneWidget,
        reason: '未达标的记录分母仍是目标，行为不变',
      );
    });
  });

  group('F32 问题二：考试回顾解析卡正确答案来自判分明细', () {
    testWidgets('回顾解析卡显示判分答案 B，不再显示样例数据无答案', (tester) async {
      final exam = _ExamFake(grading: _grades);
      await _pumpExamQuiz(tester, exam);
      await _answerAndSubmit(tester);
      await _enterReview(tester);

      // 页面级绿线仍在（解析卡此时还在构建窗口外）。
      expect(find.text('正确答案：B'), findsOneWidget);

      await _scrollTo(tester, find.text('服务端解析一'));
      expect(
        find.descendant(
          of: find.byType(AnalysisCard),
          matching: find.text('正确答案：B'),
        ),
        findsOneWidget,
        reason: '卷面 answer 为空，解析卡自己的正确答案行必须用判分答案',
      );
      expect(find.text('样例数据，无答案'), findsNothing);
    });

    testWidgets('判分为空时解析卡保持样例占位，不编造答案', (tester) async {
      final exam = _ExamFake();
      await _pumpExamQuiz(tester, exam);
      await _answerAndSubmit(tester);
      await _enterReview(tester);

      await _scrollTo(tester, find.text('解析待接口'));
      expect(
        find.descendant(
          of: find.byType(AnalysisCard),
          matching: find.text('正确答案：样例数据，无答案'),
        ),
        findsOneWidget,
        reason: '没有判分依据就不编答案，兜底行为不变',
      );
      expect(find.text('正确答案：B'), findsNothing);
    });

    testWidgets('解析卡传入判分答案时优先显示它', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AnalysisCard(
                question: _question(1, answer: const <String>[]),
                result: const AnswerResult(
                  correct: false,
                  explanation: '服务端解析',
                  correctKeys: <String>['B'],
                ),
                chosen: const <String>['A'],
                sampleData: false,
                correctAnswerOverride: const <String>['B'],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('正确答案：B'), findsOneWidget);
      expect(find.text('样例数据，无答案'), findsNothing);
      expect(find.text('你的答案：A'), findsOneWidget);
    });

    testWidgets('不传判分答案：样例题保持占位文案', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AnalysisCard(
                question: _question(1, answer: const <String>[]),
                result: const AnswerResult(correct: null, explanation: '解析待接口'),
                chosen: const <String>['A'],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('正确答案：样例数据，无答案'), findsOneWidget);
    });

    testWidgets('不传判分答案：题目自带答案照常显示', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AnalysisCard(
                question: _question(1, answer: const <String>['A', 'C']),
                result: const AnswerResult(
                  correct: true,
                  explanation: '解析内容',
                  correctKeys: <String>['A', 'C'],
                ),
                chosen: const <String>['A', 'C'],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('正确答案：A、C'), findsOneWidget);
      expect(find.text('样例数据，无答案'), findsNothing);
    });
  });
}
