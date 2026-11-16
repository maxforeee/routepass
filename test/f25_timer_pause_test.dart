/// F25 chunk 1：答题页计时器离开即暂停、再进入同一会话续计。
///
/// 用时只累计页面在前台的时长：返回 / 退到后台冻结，再进入（练习断点续答、
/// 考试续考）从冻结值续计，绝不从 0 重来、也绝不把页面外的时间算进去。
/// 显示与提交的 durationSec / durationMs 用的是同一个累计值。
///
/// 计时用 `DateTime.now()`（真实墙钟），fake async 的 pump 时长不会推动它，
/// 所以这里用 `tester.runAsync` 真实等待，再用固定时长 pump 触发秒针 tick；
/// 断言给的是区间而不是精确秒数，慢机器上也不会抖。页面有每秒 setState 的
/// 计时器，全程不用 pumpAndSettle。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

const String _setId = 'h3cne-2026-01';

const List<QuestionOption> _options = <QuestionOption>[
  QuestionOption(key: 'A', text: '选项甲'),
  QuestionOption(key: 'B', text: '选项乙'),
  QuestionOption(key: 'C', text: '选项丙'),
  QuestionOption(key: 'D', text: '选项丁'),
];

const Widget _outside = MaterialApp(home: Scaffold(body: Text('页面外')));

ExamSnapshot _snapshot(String stem) {
  return ExamSnapshot(
    stem: stem,
    options: _options,
    answer: const <String>[],
    analysis: '',
  );
}

Question _question(String id, String stem) {
  return Question(
    id: id,
    module: 'm1',
    type: 'single',
    stem: stem,
    options: _options,
    answer: const <String>['A'],
    explanation: '解析一',
    knowledge_point_id: '',
    difficulty: 1,
    set_no: 0,
    row_version: 0,
  );
}

/// 跨页面实例保留进行态：暂停落盘的累计用时要能被下一次进入读到。
class _MemorySessionService implements AnswerSessionService {
  final Map<String, AnswerSessionState> states = <String, AnswerSessionState>{};

  @override
  AnswerSessionState? load({required String setId, required String mode}) =>
      states['$mode/$setId'];

  @override
  void save(AnswerSessionState state) {
    states['${state.mode}/${state.setId}'] = state;
  }

  @override
  void clear({required String setId, required String mode}) {
    states.remove('$mode/$setId');
  }
}

class _RecordingRecordService implements AnswerRecordService {
  final List<AnswerRecord> records = <AnswerRecord>[];

  @override
  List<AnswerRecord> recordsFor({
    required String setId,
    required String mode,
  }) => records.where((r) => r.setId == setId && r.mode == mode).toList();

  @override
  AnswerRecord? breakpointOf({required String setId, required String mode}) {
    for (final r in records) {
      if (r.setId == setId && r.mode == mode && r.isBreakpoint) return r;
    }
    return null;
  }

  @override
  void upsert(AnswerRecord record) => records.add(record);

  @override
  void remove(String id) => records.removeWhere((r) => r.id == id);

  @override
  List<AnswerRecord> pendingSync() => const <AnswerRecord>[];

  @override
  void markSynced(String id, String serverId) {}

  @override
  Future<void> syncFromServer() async {}
}

class _FakeExamService implements ExamService {
  final List<ExamSnapshot> paper = <ExamSnapshot>[
    _snapshot('题干一'),
    _snapshot('题干二'),
  ];

  /// 每次交卷收到的用时（页面内累计毫秒）。
  final List<int> submittedDurationMs = <int>[];
  int startCalls = 0;

  @override
  Future<ExamSession> startExam({required int drawCount, String? setId}) async {
    startCalls++;
    return ExamSession(
      id: 'exam-1',
      started_at: DateTime.now().millisecondsSinceEpoch,
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
    submittedDurationMs.add(durationMs);
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
      const <String, ExamQuestionGrade>{};
}

class _FakePracticeService implements PracticeService {
  final List<Question> questions = <Question>[
    _question('q1', '练习题一'),
    _question('q2', '练习题二'),
  ];

  /// 每次单题提交收到的用时（页面内累计毫秒）。
  final List<int> submittedDurationMs = <int>[];
  int _drawn = 0;

  @override
  Future<PracticeRecordDetail?> getRecordDetail(String sessionId) async => null;

  @override
  Future<bool> deleteRecord(String sessionId) async => false;

  @override
  Future<PracticeRecordPaper?> getRecordPaper(String sessionId) async => null;

  @override
  Future<PracticeSession> startSession({
    required List<Question> questions,
    required String mode,
  }) async {
    return PracticeSession(
      id: 'sess-1',
      questions: questions,
      mode: mode,
      total: questions.length,
    );
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
    submittedDurationMs.add(durationMs);
    return AnswerResult(
      correct: true,
      explanation: '解析一',
      correctKeys: const <String>['A'],
      opId: opId ?? 'op-1',
    );
  }

  @override
  Future<PracticeNext?> drawNextQuestion({
    required String setId,
    String? module,
    required Set<String> excludedIds,
    String? sessionId,
  }) async {
    if (_drawn >= questions.length) return null;
    final question = questions[_drawn++];
    return PracticeNext(
      question: question,
      sessionId: 'sess-1',
      doneCount: excludedIds.length,
    );
  }

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

Future<void> _pumpExam(
  WidgetTester tester,
  _FakeExamService exam,
  _MemorySessionService sessions,
  _RecordingRecordService records,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: QuizPage(
        args: const <String, Object?>{
          'mode': 'exam',
          'setId': _setId,
          'setTitle': '套卷一',
          'drawCount': 2,
        },
        examService: exam,
        recordService: records,
        sessionService: sessions,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _pumpPractice(
  WidgetTester tester,
  _FakePracticeService practice,
  _MemorySessionService sessions,
  _RecordingRecordService records,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: QuizPage(
        args: const <String, Object?>{
          'mode': 'practice',
          'setId': _setId,
          'setTitle': '套卷一',
          'drawCount': 20,
          'target': 20,
        },
        practiceService: practice,
        recordService: records,
        sessionService: sessions,
        favoriteService: MockFavoriteService(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Finder _optionTile(String key) {
  return find.byWidgetPredicate((w) => w is OptionTile && w.option.key == key);
}

/// 真实等待一段时间（`DateTime.now()` 是墙钟，fake pump 推不动它），再 pump
/// 一秒触发计时器 tick 重建。页面内 / 页面外 / 后台都用它，区别只在于此时
/// 页面计时器该不该走。
Future<void> _realTime(WidgetTester tester, Duration duration) async {
  await tester.runAsync(() async {
    await Future<void>.delayed(duration);
  });
  await tester.pump(const Duration(seconds: 1));
}

/// 头部「答对 n · mm:ss」；分隔符用 . 匹配，不依赖具体的点号字形。
final RegExp _elapsedPattern = RegExp(r'^答对 \d+ . (\d{2}):(\d{2})$');

/// 头部计时文本里的秒数。
int _elapsedSeconds(WidgetTester tester) {
  for (final widget in tester.widgetList<Text>(find.byType(Text))) {
    final match = _elapsedPattern.firstMatch(widget.data ?? '');
    if (match == null) continue;
    return int.parse(match.group(1)!) * 60 + int.parse(match.group(2)!);
  }
  throw StateError('头部计时文本未找到');
}

Future<void> _leavePage(WidgetTester tester) async {
  await tester.pumpWidget(_outside);
  await tester.pump();
}

/// 第一题选 A → 下一题 → 第二题选 B → 交卷并确认，停在结果 sheet。
Future<void> _submitExam(WidgetTester tester) async {
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

void main() {
  testWidgets('考试：离开页面冻结用时，再进入同一会话从冻结值续计', (tester) async {
    final exam = _FakeExamService();
    final sessions = _MemorySessionService();
    final records = _RecordingRecordService();

    await _pumpExam(tester, exam, sessions, records);
    await _realTime(tester, const Duration(milliseconds: 1200));
    expect(_elapsedSeconds(tester), greaterThanOrEqualTo(1));

    await tester.tap(_optionTile('A'));
    await tester.pump(const Duration(milliseconds: 300));

    // 离开页面，并在页面外待 3 秒。
    await _leavePage(tester);
    await _realTime(tester, const Duration(seconds: 3));

    await _pumpExam(tester, exam, sessions, records);
    expect(exam.startCalls, 1, reason: '续考同一会话，不是重新开考');
    // 续计冻结值（约 1 秒），不是 0、也不是含页面外 3 秒的墙钟（约 4 秒）。
    expect(_elapsedSeconds(tester), greaterThanOrEqualTo(1));
    expect(_elapsedSeconds(tester), lessThanOrEqualTo(2));

    // 回来之后继续往前走。
    await _realTime(tester, const Duration(milliseconds: 1200));
    expect(_elapsedSeconds(tester), greaterThanOrEqualTo(2));
    expect(_elapsedSeconds(tester), lessThanOrEqualTo(3));
  });

  testWidgets('考试：交卷用时不含页面外的时间', (tester) async {
    final exam = _FakeExamService();
    final sessions = _MemorySessionService();
    final records = _RecordingRecordService();

    await _pumpExam(tester, exam, sessions, records);
    await _realTime(tester, const Duration(milliseconds: 1200));
    await tester.tap(_optionTile('A'));
    await tester.pump(const Duration(milliseconds: 300));

    await _leavePage(tester);
    await _realTime(tester, const Duration(seconds: 4));

    await _pumpExam(tester, exam, sessions, records);
    await _submitExam(tester);

    expect(exam.submittedDurationMs, hasLength(1));
    // 页面内约 1~2 秒；页面外的 4 秒绝不能算进去（旧实现约 5~6 秒）。
    expect(exam.submittedDurationMs.single, greaterThan(0));
    expect(exam.submittedDurationMs.single, lessThan(3500));

    final completion = records.records.firstWhere(
      (r) => r.mode == 'exam' && r.kind == 'completion',
    );
    expect(completion.durationMs, greaterThan(0));
    expect(completion.durationMs, lessThan(3500));
  });

  testWidgets('练习：离开页面再进入从冻结值续计', (tester) async {
    final practice = _FakePracticeService();
    final sessions = _MemorySessionService();
    final records = _RecordingRecordService();

    await _pumpPractice(tester, practice, sessions, records);
    await _realTime(tester, const Duration(milliseconds: 1200));
    expect(_elapsedSeconds(tester), greaterThanOrEqualTo(1));

    await _leavePage(tester);
    await _realTime(tester, const Duration(seconds: 3));

    await _pumpPractice(tester, practice, sessions, records);
    expect(_elapsedSeconds(tester), greaterThanOrEqualTo(1));
    expect(_elapsedSeconds(tester), lessThanOrEqualTo(2));
  });

  testWidgets('练习：退到后台冻结用时，单题 durationSec 不含后台时间', (tester) async {
    final practice = _FakePracticeService();
    final sessions = _MemorySessionService();
    final records = _RecordingRecordService();

    await _pumpPractice(tester, practice, sessions, records);
    await _realTime(tester, const Duration(milliseconds: 1200));
    expect(_elapsedSeconds(tester), greaterThanOrEqualTo(1));

    // 退到后台 3 秒再回前台：页面还在，计时必须停走。
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    await _realTime(tester, const Duration(seconds: 3));
    // 回前台完整序列 paused → hidden → inactive → resumed；框架禁止 paused 直跳 inactive/resumed。
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    // pump 一秒让秒针 tick 触发重建：读到的才是回前台后的显示值。
    await tester.pump(const Duration(seconds: 1));
    expect(_elapsedSeconds(tester), greaterThanOrEqualTo(1));
    expect(_elapsedSeconds(tester), lessThanOrEqualTo(2));

    await tester.tap(_optionTile('A'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(practice.submittedDurationMs, hasLength(1));
    // 单题用时同样扣掉后台的 3 秒（旧实现约 4 秒）。
    expect(practice.submittedDurationMs.single, greaterThan(0));
    expect(practice.submittedDurationMs.single, lessThan(3000));
  });

  testWidgets('考试：交卷结算后离开页面不会把已清掉的会话写回来', (tester) async {
    final exam = _FakeExamService();
    final sessions = _MemorySessionService();
    final records = _RecordingRecordService();

    await _pumpExam(tester, exam, sessions, records);
    await tester.tap(_optionTile('A'));
    await tester.pump(const Duration(milliseconds: 300));
    await _submitExam(tester);
    expect(sessions.load(setId: _setId, mode: 'exam'), isNull);

    await _leavePage(tester);
    expect(sessions.load(setId: _setId, mode: 'exam'), isNull);
  });
}
