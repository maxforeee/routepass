/// F34：F33 的边界回归——答题页被其它路由盖住期间退后台、再回前台，
/// resumed 不能直接续计（页面仍被盖住，计时必须停在冻结值）；盖住的路由
/// pop 露出后才从冻结值恢复。
///
/// 计时用 `DateTime.now()`（真实墙钟），fake async 的 pump 时长推不动它，
/// 沿用 f25/f33 的办法：`tester.runAsync` 真实等待，再 pump 一秒触发秒针
/// tick；断言给区间而不是精确秒数。回前台必须走完整
/// paused → hidden → inactive → resumed 序列（AppLifecycleListener 拒绝
/// paused 直接跳 resumed / inactive）。被盖住的页面 offstage，读计时文本
/// 一律 skipOffstage: false；页面有每秒 setState 的计时器，不用 pumpAndSettle。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/core/route_observer.dart';
import 'package:routepass/models/answer_record.dart';
import 'package:routepass/models/answer_session_state.dart';
import 'package:routepass/models/exam.dart';
import 'package:routepass/models/question.dart';
import 'package:routepass/pages/bank/answer_widgets.dart';
import 'package:routepass/pages/bank/quiz_page.dart';
import 'package:routepass/services/bank/answer_record_service.dart';
import 'package:routepass/services/bank/answer_session_service.dart';
import 'package:routepass/services/bank/exam_service.dart';

const String _setId = 'h3cne-2026-01';

const List<QuestionOption> _options = <QuestionOption>[
  QuestionOption(key: 'A', text: '选项甲'),
  QuestionOption(key: 'B', text: '选项乙'),
  QuestionOption(key: 'C', text: '选项丙'),
  QuestionOption(key: 'D', text: '选项丁'),
];

ExamSnapshot _snapshot(String stem) {
  return ExamSnapshot(
    stem: stem,
    options: _options,
    answer: const <String>[],
    analysis: '',
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

  @override
  Future<ExamSession> startExam({required int drawCount, String? setId}) async {
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

Future<void> _background(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  await tester.pump();
}

/// 回前台必须走完整序列：paused 直接跳 resumed / inactive 会被
/// AppLifecycleListener 的状态机断言拒绝（f25 测试踩过）。
Future<void> _foreground(WidgetTester tester) async {
  for (final state in <AppLifecycleState>[
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
    await tester.pump();
  }
}

void main() {
  testWidgets('被盖住期间退后台再回前台不续计，pop 露出后才从冻结值恢复', (tester) async {
    final exam = _FakeExamService();
    final sessions = _MemorySessionService();
    final records = _RecordingRecordService();

    await _pumpExam(tester, exam, sessions, records);
    await _realTime(tester, const Duration(milliseconds: 1200));
    final before = _elapsedSeconds(tester);
    expect(before, greaterThanOrEqualTo(1));

    // 先答一题触发首次会话落盘（同 f33）：全新会话未持久化前暂停不落盘。
    await tester.tap(_optionTile('A'));
    await tester.pump(const Duration(milliseconds: 300));

    // 盖住答题页：计时冻结并落盘。
    final nav = _quizNavigator(tester);
    await _pushCover(tester, nav);
    final frozen = _elapsedSeconds(tester);
    expect(frozen, greaterThanOrEqualTo(before));
    expect(frozen, lessThanOrEqualTo(before + 1));
    final saved = sessions.load(setId: _setId, mode: 'exam');
    expect(saved, isNotNull);

    // 被盖住期间退后台，真实等 2 秒再回前台（完整生命周期序列）。
    await _background(tester);
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(seconds: 2));
    });
    await _foreground(tester);

    // 页面仍被盖住：回前台绝不能续计——再真实等 1.5 秒，显示值一动不动。
    // 旧实现 resumed 无条件 _startTimer，这里会涨约 1~2 秒。
    await _realTime(tester, const Duration(milliseconds: 1500));
    expect(_elapsedSeconds(tester), frozen, reason: '仍被盖住时回前台不能续计');
    expect(
      sessions.load(setId: _setId, mode: 'exam')!.elapsedMs,
      saved!.elapsedMs,
      reason: '落盘值同样不含被盖住 / 退后台的时间',
    );

    // pop 露出：从冻结值续计，不是 0、也不是含被盖时长的墙钟。
    await _popCover(tester, nav);
    expect(_elapsedSeconds(tester), greaterThanOrEqualTo(frozen));
    expect(_elapsedSeconds(tester), lessThanOrEqualTo(frozen + 1));

    // 露出之后继续往前走。
    await _realTime(tester, const Duration(milliseconds: 1200));
    expect(_elapsedSeconds(tester), greaterThanOrEqualTo(frozen + 1));
    expect(_elapsedSeconds(tester), lessThanOrEqualTo(frozen + 2));
  });
}
