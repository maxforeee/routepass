/// F24 考试链 chunk 3：考试回顾接服务端判分（B14）。
///
/// 卷面不含答案（answer 为空），与真实考试契约一致；回顾的红绿 / 正确答案 /
/// 解析必须来自 loadExamGrading 的判分明细。判分为空 / 拉取失败 / 尚未返回时
/// 保持原有兜底：只标已选、解析显示「解析待接口」，绝不本地猜对错。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/models/answer_record.dart';
import 'package:routepass/models/answer_session_state.dart';
import 'package:routepass/models/exam.dart';
import 'package:routepass/models/question.dart';
import 'package:routepass/pages/bank/answer_widgets.dart';
import 'package:routepass/pages/bank/quiz_page.dart';
import 'package:routepass/services/bank/answer_record_service.dart';
import 'package:routepass/services/bank/answer_session_service.dart';
import 'package:routepass/services/bank/exam_service.dart';

const List<QuestionOption> _options = <QuestionOption>[
  QuestionOption(key: 'A', text: '选项甲'),
  QuestionOption(key: 'B', text: '选项乙'),
  QuestionOption(key: 'C', text: '选项丙'),
  QuestionOption(key: 'D', text: '选项丁'),
];

ExamSnapshot _snapshot(String stem, {List<String> answer = const <String>[]}) {
  return ExamSnapshot(
    stem: stem,
    options: _options,
    answer: answer,
    analysis: '',
  );
}

class _FakeExamService implements ExamService {
  _FakeExamService({
    this.grading = const <String, ExamQuestionGrade>{},
    this.failGrading = false,
    this.gradingCompleter,
    List<ExamSnapshot>? paper,
  }) : paper = paper ?? <ExamSnapshot>[_snapshot('题干一'), _snapshot('题干二')];

  final Map<String, ExamQuestionGrade> grading;
  final bool failGrading;
  final Completer<Map<String, ExamQuestionGrade>>? gradingCompleter;
  final List<ExamSnapshot> paper;
  final List<String> gradingExamIds = <String>[];

  @override
  Future<ExamSession> startExam({required int drawCount, String? setId}) async {
    return ExamSession(
      id: 'exam-1',
      started_at: 1700000000000,
      total: paper.length,
      detail: '',
      snapshot: paper,
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
  Future<Map<String, ExamQuestionGrade>> loadExamGrading(String examId) async {
    gradingExamIds.add(examId);
    if (failGrading) throw Exception('grading unavailable');
    final completer = gradingCompleter;
    if (completer != null) return completer.future;
    return grading;
  }
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

Future<void> _pumpQuiz(WidgetTester tester, _FakeExamService exam) async {
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
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Finder _optionTile(String key) {
  return find.byWidgetPredicate((w) => w is OptionTile && w.option.key == key);
}

OptionTileState _tileState(WidgetTester tester, String key) {
  return tester.widget<OptionTile>(_optionTile(key)).state;
}

/// 解析卡在 800×600 测试视口的折叠线以下，ListView 的 children 也是懒构建，
/// 不滚进构建窗口就断言会找不到文本（与 F22 的 _scrollTo 同一约定）。
/// 页面有每秒 setState 的计时器，滚动全程用固定时长 pump，不用 pumpAndSettle。
Future<void> _scrollTo(
  WidgetTester tester,
  Finder finder, {
  double delta = 200,
}) async {
  await tester.scrollUntilVisible(
    finder,
    delta,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

/// 第一题选 A、第二题选 B，交卷并确认，停在全屏评分页（F25）。
Future<void> _answerAndSubmit(WidgetTester tester) async {
  await tester.tap(_optionTile('A'));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.text('下一题'));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(_optionTile('B'));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.text('交卷'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.tap(find.widgetWithText(FilledButton, '确认交卷'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump(const Duration(milliseconds: 600));
}

/// 点全屏评分页的「逐题回顾」进入回顾模式（落在第一题）；目标是第二题
/// 时再点一次「下一题」。页面有每秒 setState 的计时器，全程用固定时长
/// pump，不用 pumpAndSettle。
Future<void> _enterReview(WidgetTester tester, String stem) async {
  await tester.tap(find.text('逐题回顾'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump(const Duration(milliseconds: 600));
  if (stem == '题干二') {
    await tester.tap(find.text('下一题'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }
}

void main() {
  testWidgets('回顾按服务端判分标红绿并给出正确答案', (tester) async {
    final exam = _FakeExamService(grading: _grades);
    await _pumpQuiz(tester, exam);
    await _answerAndSubmit(tester);
    await _enterReview(tester, '题干一');

    expect(exam.gradingExamIds, <String>['exam-1']);
    // 卷面 answer 为空，红绿只能来自判分：选 A 错、正确项 B 绿。
    expect(_tileState(tester, 'A'), OptionTileState.wrong);
    expect(_tileState(tester, 'B'), OptionTileState.correct);
    expect(_tileState(tester, 'C'), OptionTileState.idle);
    expect(find.text('正确答案：B'), findsOneWidget);
  });

  testWidgets('回顾解析来自服务端判分', (tester) async {
    final exam = _FakeExamService(grading: _grades);
    await _pumpQuiz(tester, exam);
    await _answerAndSubmit(tester);
    await _enterReview(tester, '题干二');

    expect(_tileState(tester, 'B'), OptionTileState.correct);
    await _scrollTo(tester, find.text('服务端解析二'));
    expect(find.text('服务端解析二'), findsOneWidget);
    expect(find.text('解析待接口'), findsNothing);
  });

  testWidgets('判分为空时回顾只标已选并显示解析待接口', (tester) async {
    final exam = _FakeExamService();
    await _pumpQuiz(tester, exam);
    await _answerAndSubmit(tester);
    await _enterReview(tester, '题干一');

    expect(_tileState(tester, 'A'), OptionTileState.selected);
    expect(_tileState(tester, 'B'), OptionTileState.idle);
    await _scrollTo(tester, find.text('解析待接口'));
    expect(find.text('解析待接口'), findsOneWidget);
    expect(find.text('正确答案：B'), findsNothing);
  });

  testWidgets('判分拉取失败时回顾保持兜底', (tester) async {
    final exam = _FakeExamService(failGrading: true);
    await _pumpQuiz(tester, exam);
    await _answerAndSubmit(tester);
    await _enterReview(tester, '题干一');

    expect(_tileState(tester, 'A'), OptionTileState.selected);
    expect(_tileState(tester, 'B'), OptionTileState.idle);
    await _scrollTo(tester, find.text('解析待接口'));
    expect(find.text('解析待接口'), findsOneWidget);
    expect(find.text('正确答案：B'), findsNothing);
  });

  testWidgets('判分未返回时回顾先按兜底渲染，返回后更新', (tester) async {
    final completer = Completer<Map<String, ExamQuestionGrade>>();
    final exam = _FakeExamService(gradingCompleter: completer);
    await _pumpQuiz(tester, exam);
    await _answerAndSubmit(tester);
    await _enterReview(tester, '题干一');

    // 判分还在路上：回顾界面已可见，按只标已选兜底。
    expect(find.text('题干一'), findsOneWidget);
    expect(_tileState(tester, 'A'), OptionTileState.selected);
    await _scrollTo(tester, find.text('解析待接口'));
    expect(find.text('解析待接口'), findsOneWidget);

    completer.complete(_grades);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 解析卡还在构建窗口里，先断言解析已更新；再滚回选项区断言红绿，
    // 避免选项滚出构建窗口后取不到 widget。
    expect(find.text('服务端解析一'), findsOneWidget);
    await _scrollTo(tester, _optionTile('A'), delta: -200);
    expect(_tileState(tester, 'A'), OptionTileState.wrong);
    expect(_tileState(tester, 'B'), OptionTileState.correct);
  });

  testWidgets('服务端判分优先于卷面自带答案', (tester) async {
    final exam = _FakeExamService(
      paper: <ExamSnapshot>[
        _snapshot('题干一', answer: <String>['A']),
        _snapshot('题干二'),
      ],
      grading: _grades,
    );
    await _pumpQuiz(tester, exam);
    await _answerAndSubmit(tester);
    await _enterReview(tester, '题干一');

    // 卷面答案 A 与判分答案 B 冲突时以服务端为准。
    expect(_tileState(tester, 'A'), OptionTileState.wrong);
    expect(_tileState(tester, 'B'), OptionTileState.correct);
    expect(find.text('正确答案：B'), findsOneWidget);
  });
}
