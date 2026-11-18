/// F33：答题页被其它路由盖住（页面仍活在栈里，不 dispose）时计时器暂停，
/// pop 回来从冻结值续计——与 F25 的 dispose / 退后台暂停同一套累计语义，
/// 绝不从 0 重来，单题 durationSec 同样不含被盖住的时间。
///
/// 计时用 `DateTime.now()`（真实墙钟），fake async 的 pump 时长推不动它，
/// 所以沿用 f25_timer_pause_test 的办法：`tester.runAsync` 真实等待，再
/// pump 一秒触发秒针 tick；断言给区间而不是精确秒数。页面有每秒 setState
/// 的计时器，全程不用 pumpAndSettle。被盖住的页面可能 offstage，读计时
/// 文本一律 skipOffstage: false。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/core/route_observer.dart';
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
  Future<bool> syncFromServer() async => false;
}

class _FakeExamService implements ExamService {
  final List<ExamSnapshot> paper = <ExamSnapshot>[
    _snapshot('题干一'),
    _snapshot('题干二'),
  ];

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
      navigatorObservers: <NavigatorObserver>[appRouteObserver],
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
      navigatorObservers: <NavigatorObserver>[appRouteObserver],
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
/// 一秒触发计时器 tick 重建。
Future<void> _realTime(WidgetTester tester, Duration duration) async {
  await tester.runAsync(() async {
    await Future<void>.delayed(duration);
  });
  await tester.pump(const Duration(seconds: 1));
}

/// 头部「答对 n · mm:ss」；分隔符用 . 匹配，不依赖具体的点号字形。被盖住
/// 的答题页可能 offstage，skipOffstage: false 才读得到。
final RegExp _elapsedPattern = RegExp(r'^答对 \d+ . (\d{2}):(\d{2})$');

int _elapsedSeconds(WidgetTester tester) {
  for (final widget in tester.widgetList<Text>(
    find.byType(Text, skipOffstage: false),
  )) {
    final match = _elapsedPattern.firstMatch(widget.data ?? '');
    if (match == null) continue;
    return int.parse(match.group(1)!) * 60 + int.parse(match.group(2)!);
  }
  throw StateError('头部计时文本未找到');
}

/// 在答题页所在栈里 push 一个盖住它的路由（页面不 dispose）。导航器在
/// 盖住之前取好——盖住之后 QuizPage 可能 offstage，finder 默认找不到。
NavigatorState _quizNavigator(WidgetTester tester) {
  return Navigator.of(tester.element(find.byType(QuizPage)));
}

Future<void> _pushCover(WidgetTester tester, NavigatorState nav) async {
  nav.push(
    MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('覆盖页'))),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _popCover(WidgetTester tester, NavigatorState nav) async {
  nav.pop();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _leavePage(WidgetTester tester) async {
  await tester.pumpWidget(_outside);
  await tester.pump();
}

void main() {
  testWidgets('考试：被其它路由盖住冻结用时并落盘，pop 回来从冻结值续计', (tester) async {
    final exam = _FakeExamService();
    final sessions = _MemorySessionService();
    final records = _RecordingRecordService();

    await _pumpExam(tester, exam, sessions, records);
    await _realTime(tester, const Duration(milliseconds: 1200));
    final before = _elapsedSeconds(tester);
    expect(before, greaterThanOrEqualTo(1));

    // 先答一题触发首次会话落盘（同 f25 考试测试）：全新会话未持久化前，
    // 暂停路径不会保存空快照，后面 sessions.load 会是 null。
    await tester.tap(_optionTile('A'));
    await tester.pump(const Duration(milliseconds: 300));

    // 盖住答题页：页面还在栈里（没有 dispose），计时必须停走。
    final nav = _quizNavigator(tester);
    await _pushCover(tester, nav);
    final frozen = _elapsedSeconds(tester);
    expect(frozen, greaterThanOrEqualTo(before));
    expect(frozen, lessThanOrEqualTo(before + 1));
    // 与退后台同一条暂停路径：累计用时已冻结落盘。
    final saved = sessions.load(setId: _setId, mode: 'exam');
    expect(saved, isNotNull);
    expect(saved!.elapsedMs, greaterThanOrEqualTo(1000));
    expect(saved.elapsedMs, lessThan(2500));

    // 被盖住 3 秒：显示值一动不动，落盘值也不含这 3 秒。
    await _realTime(tester, const Duration(seconds: 3));
    expect(_elapsedSeconds(tester), frozen);
    expect(
      sessions.load(setId: _setId, mode: 'exam')!.elapsedMs,
      lessThan(2500),
    );

    // pop 回来：从冻结值续计，不是 0、也不是含被盖 3 秒的墙钟。
    await _popCover(tester, nav);
    expect(_elapsedSeconds(tester), greaterThanOrEqualTo(frozen));
    expect(_elapsedSeconds(tester), lessThanOrEqualTo(frozen + 1));

    // 回来之后继续往前走。
    await _realTime(tester, const Duration(milliseconds: 1200));
    expect(_elapsedSeconds(tester), greaterThanOrEqualTo(frozen + 1));
    expect(_elapsedSeconds(tester), lessThanOrEqualTo(frozen + 2));
  });

  testWidgets('练习：被盖住的时间不计入单题 durationSec', (tester) async {
    final practice = _FakePracticeService();
    final sessions = _MemorySessionService();
    final records = _RecordingRecordService();

    await _pumpPractice(tester, practice, sessions, records);
    await _realTime(tester, const Duration(milliseconds: 1200));
    expect(_elapsedSeconds(tester), greaterThanOrEqualTo(1));

    // 盖住 3 秒再 pop 回来：页面一直在栈里，单题起点要后移这 3 秒。
    final nav = _quizNavigator(tester);
    await _pushCover(tester, nav);
    await _realTime(tester, const Duration(seconds: 3));
    await _popCover(tester, nav);

    await tester.tap(_optionTile('A'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(practice.submittedDurationMs, hasLength(1));
    // 页面内约 1~2 秒；被盖住的 3 秒绝不能算进去（旧实现约 4 秒+）。
    expect(practice.submittedDurationMs.single, greaterThan(0));
    expect(practice.submittedDurationMs.single, lessThan(3000));
  });

  testWidgets('考试：盖住-pop-再盖住不重复暂停、不丢用时、不从 0 重来', (tester) async {
    final exam = _FakeExamService();
    final sessions = _MemorySessionService();
    final records = _RecordingRecordService();

    await _pumpExam(tester, exam, sessions, records);
    await _realTime(tester, const Duration(milliseconds: 1200));

    final nav = _quizNavigator(tester);
    // 第一次盖住 1.5 秒 → pop → 页面内再走 1.2 秒。
    await _pushCover(tester, nav);
    await _realTime(tester, const Duration(milliseconds: 1500));
    await _popCover(tester, nav);
    await _realTime(tester, const Duration(milliseconds: 1200));

    // 第二次盖住：冻结值应是两段页面内时间之和（约 2.4 秒），不含两次被盖。
    await _pushCover(tester, nav);
    await _realTime(tester, const Duration(milliseconds: 1500));
    final frozen = _elapsedSeconds(tester);
    expect(frozen, greaterThanOrEqualTo(2));
    expect(frozen, lessThanOrEqualTo(3));

    // 再 pop 回来继续走：累计值接着长，仍不含任何被盖时间（墙钟已约 6.6 秒）。
    await _popCover(tester, nav);
    await _realTime(tester, const Duration(milliseconds: 1200));
    expect(_elapsedSeconds(tester), greaterThanOrEqualTo(frozen + 1));
    expect(_elapsedSeconds(tester), lessThanOrEqualTo(4));
  });

  testWidgets('回归：注册观察者后 dispose 冻结落盘、再进入同一会话续计不变', (tester) async {
    final exam = _FakeExamService();
    final sessions = _MemorySessionService();
    final records = _RecordingRecordService();

    await _pumpExam(tester, exam, sessions, records);
    await _realTime(tester, const Duration(milliseconds: 1200));
    expect(_elapsedSeconds(tester), greaterThanOrEqualTo(1));

    // 先答一题触发首次会话落盘：未持久化的全新会话在暂停时不保存空快照。
    await tester.tap(_optionTile('A'));
    await tester.pump(const Duration(milliseconds: 300));

    // dispose（离开页面）仍走原暂停路径：冻结并落盘。
    await _leavePage(tester);
    final saved = sessions.load(setId: _setId, mode: 'exam');
    expect(saved, isNotNull);
    expect(saved!.elapsedMs, greaterThanOrEqualTo(1000));
    expect(saved.elapsedMs, lessThan(2500));

    await _pumpExam(tester, exam, sessions, records);
    expect(exam.startCalls, 1, reason: '续考同一会话，不是重新开考');
    expect(_elapsedSeconds(tester), greaterThanOrEqualTo(1));
    expect(_elapsedSeconds(tester), lessThanOrEqualTo(2));

    await _realTime(tester, const Duration(milliseconds: 1200));
    expect(_elapsedSeconds(tester), greaterThanOrEqualTo(2));
    expect(_elapsedSeconds(tester), lessThanOrEqualTo(3));
  });
}
