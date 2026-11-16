/// F25 Chunk 4：练习收藏按钮 + 考试全屏评分页。
///
/// - 收藏按钮只在练习页出现；点收藏 / 取消收藏走 FavoriteService，
///   图标即时切换、有提示，失败回滚。
/// - 交卷后的半屏结果 sheet 换成全屏评分页：得分 / 答错数 / 全部错题
///   （题干、你的答案 vs 正确答案、解析）逐条列出，每条带「加入错题本」；
///   退出按钮固定底部，20 道错题也不用滚动就能点到。
///
/// QuizPage 有每秒 setState 的计时器：集成用例全程固定时长 pump，
/// 不用 pumpAndSettle；独立评分页没有计时器，可以 pumpAndSettle。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/core/kv_store.dart';
import 'package:routepass/core/theme.dart';
import 'package:routepass/models/exam.dart';
import 'package:routepass/models/practice.dart';
import 'package:routepass/models/question.dart';
import 'package:routepass/models/wrong_favorite.dart';
import 'package:routepass/pages/bank/answer_widgets.dart';
import 'package:routepass/pages/bank/exam_score_page.dart';
import 'package:routepass/pages/bank/quiz_page.dart';
import 'package:routepass/services/bank/answer_record_service.dart';
import 'package:routepass/services/bank/answer_session_service.dart';
import 'package:routepass/services/bank/exam_service.dart';
import 'package:routepass/services/bank/favorite_service.dart';
import 'package:routepass/services/bank/practice_service.dart';
import 'package:routepass/services/bank/wrong_service.dart';

Question _question(int index, {List<String> answer = const <String>['A']}) {
  return Question(
    id: 'VLAN-${index.toString().padLeft(4, '0')}',
    module: 'VLAN',
    type: 'single',
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

/// 评分页 / 考试集成用的题目：服务端题目 id（EXAM-i），卷面不含答案。
Question _examQuestion(int index) {
  return Question(
    id: 'EXAM-$index',
    module: '',
    type: 'single',
    stem: '题干 ${index + 1}',
    options: const <QuestionOption>[
      QuestionOption(key: 'A', text: 'A 选项'),
      QuestionOption(key: 'B', text: 'B 选项'),
      QuestionOption(key: 'C', text: 'C 选项'),
      QuestionOption(key: 'D', text: 'D 选项'),
    ],
    answer: const <String>[],
    explanation: '',
    knowledge_point_id: '',
    difficulty: 1,
    set_no: 0,
    row_version: 0,
  );
}

class _FakeFavoriteService implements FavoriteService {
  _FakeFavoriteService({Set<String>? initial}) : ids = initial ?? <String>{};

  final Set<String> ids;
  final List<(String, bool)> toggleCalls = <(String, bool)>[];
  bool failToggle = false;

  @override
  Future<List<String>> getFavoriteIds() async => ids.toList();

  @override
  Future<List<Favorite>> getFavorites() async => <Favorite>[
    for (final id in ids) Favorite(question_id: id, created_at: 0),
  ];

  @override
  Future<void> toggleFavorite(String questionId, bool on) async {
    if (failToggle) throw Exception('favorite failed');
    toggleCalls.add((questionId, on));
    if (on) {
      ids.add(questionId);
    } else {
      ids.remove(questionId);
    }
  }

  @override
  Future<int> mergeFromServer(List<Favorite> items) async => 0;
}

class _FakeWrongService implements WrongService {
  final List<String> added = <String>[];
  bool failAdd = false;

  @override
  Future<void> addWrong(String questionId) async {
    if (failAdd) throw Exception('add failed');
    added.add(questionId);
  }

  @override
  Future<List<WrongItem>> getWrongBook({
    String? module,
    bool? masteredOnly,
  }) async => const <WrongItem>[];

  @override
  Future<void> markMastered(String questionId) async {}

  @override
  Future<void> removeWrong(
    String questionId, {
    String reason = 'user_removed',
  }) async {}

  @override
  Future<int> mergeFromServer(List<WrongItem> items) async => 0;
}

class _FakePracticeService implements PracticeService {
  _FakePracticeService(this.questions);

  final List<Question> questions;

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

class _FakeExamService implements ExamService {
  _FakeExamService(
    this.questions, {
    this.grading = const <String, ExamQuestionGrade>{},
  });

  final List<Question> questions;
  final Map<String, ExamQuestionGrade> grading;
  int submitCalls = 0;
  final List<String> gradingExamIds = <String>[];

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
  }) async {}

  @override
  Future<ExamResult?> submitExam({
    required String examId,
    required Map<String, List<String>> answers,
    required int durationMs,
  }) async {
    submitCalls++;
    return ExamResult(score: 78, passed: null, detail: '');
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
    return grading;
  }
}

/// 三道题的判分明细：第 1 / 3 题错（选 A 正确 B），第 2 题对。
const Map<String, ExamQuestionGrade> _grades = <String, ExamQuestionGrade>{
  'EXAM-0': ExamQuestionGrade(
    questionId: 'EXAM-0',
    chosen: <String>['A'],
    answer: <String>['B'],
    explanation: '解析一',
    correct: false,
  ),
  'EXAM-1': ExamQuestionGrade(
    questionId: 'EXAM-1',
    chosen: <String>['A'],
    answer: <String>['A'],
    explanation: '解析二',
    correct: true,
  ),
  'EXAM-2': ExamQuestionGrade(
    questionId: 'EXAM-2',
    chosen: <String>['A'],
    answer: <String>['B'],
    explanation: '解析三',
    correct: false,
  ),
};

/// 真实服务端卷面：startExamPaper 返回服务端题目 id（q-101 / q-102），
/// 与 startExam 回落快照的 EXAM-i 序号**不同**——页面必须走 startExamPaper，
/// 暂存 / 判分 / 加入错题本才都落在真实题目 id 上。
class _RealIdExamService extends _FakeExamService {
  _RealIdExamService() : super(const <Question>[], grading: _realIdGrades);

  final List<String> savedIds = <String>[];

  @override
  Future<ExamStart> startExamPaper({
    required int drawCount,
    String? setId,
  }) async {
    return ExamStart(
      id: 'E-REAL',
      startedAt: DateTime.now().millisecondsSinceEpoch,
      total: 2,
      questions: <Question>[
        _realIdQuestion('q-101', '真实题一'),
        _realIdQuestion('q-102', '真实题二'),
      ],
    );
  }

  @override
  Future<void> saveAnswer({
    required String examId,
    required String questionId,
    required List<String> chosen,
    required String opId,
  }) async {
    savedIds.add(questionId);
  }
}

Question _realIdQuestion(String id, String stem) {
  return Question(
    id: id,
    module: '',
    type: 'single',
    stem: stem,
    options: const <QuestionOption>[
      QuestionOption(key: 'A', text: 'A 选项'),
      QuestionOption(key: 'B', text: 'B 选项'),
      QuestionOption(key: 'C', text: 'C 选项'),
      QuestionOption(key: 'D', text: 'D 选项'),
    ],
    answer: const <String>[],
    explanation: '',
    knowledge_point_id: '',
    difficulty: 1,
    set_no: 0,
    row_version: 0,
  );
}

const Map<String, ExamQuestionGrade> _realIdGrades =
    <String, ExamQuestionGrade>{
      'q-101': ExamQuestionGrade(
        questionId: 'q-101',
        chosen: <String>['A'],
        answer: <String>['B'],
        explanation: '真实解析',
        correct: false,
      ),
      'q-102': ExamQuestionGrade(
        questionId: 'q-102',
        chosen: <String>['B'],
        answer: <String>['B'],
        explanation: '真实解析二',
        correct: true,
      ),
    };

Widget _host(Widget page) {
  // 每次启动换新 key：pumpWidget 复用同型 Navigator 的 State，不换 key
  // 时上一次推入的路由仍压在栈顶，二次 _launch 找不到 launch 按钮。
  return MaterialApp(
    key: UniqueKey(),
    theme: AppTheme.light,
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () =>
                Navigator.of(context)
                    .push(MaterialPageRoute<void>(builder: (_) => page)),
            child: const Text('launch'),
          ),
        ),
      ),
    ),
  );
}

/// QuizPage 集成用例的启动：固定时长 pump（页面有每秒计时器）。
Future<void> _launch(WidgetTester tester, Widget page) async {
  await tester.pumpWidget(_host(page));
  await tester.tap(find.text('launch'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _tapOption(WidgetTester tester, String key) async {
  await tester.tap(find.text('$key 选项'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

/// 评分页卡片在折叠线以下时先滚进构建窗口（ListView children 懒构建）。
/// 集成用例里答题页还压在评分页下面，滚动目标要限定在评分页内。
Future<void> _scrollTo(
  WidgetTester tester,
  Finder finder, {
  Finder? scrollable,
}) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: scrollable ?? find.byType(Scrollable).first,
  );
  await tester.pump(const Duration(milliseconds: 300));
}

/// 评分页内的文本查找：避免匹配到压在下面的答题页 / 回顾页同名文本。
Finder _inScore(String text) {
  return find.descendant(
    of: find.byType(ExamScorePage),
    matching: find.text(text),
  );
}

Finder _scoreScrollable() {
  return find
      .descendant(
        of: find.byType(ExamScorePage),
        matching: find.byType(Scrollable),
      )
      .first;
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

  Widget practicePage(
    _FakePracticeService practice,
    _FakeFavoriteService favorite,
  ) {
    return QuizPage(
      args: <String, Object?>{
        'mode': 'practice',
        'setId': 'VLAN',
        'setTitle': 'VLAN',
        'drawCount': 100,
        'target': 20,
      },
      practiceService: practice,
      recordService: records,
      sessionService: sessions,
      favoriteService: favorite,
    );
  }

  Widget examPage(_FakeExamService exam, _FakeWrongService wrong) {
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
      wrongService: wrong,
    );
  }

  group('练习收藏按钮', () {
    testWidgets('练习页有收藏按钮，考试页没有', (tester) async {
      final practice = _FakePracticeService(<Question>[_question(1)]);
      await _launch(tester, practicePage(practice, _FakeFavoriteService()));
      expect(find.byTooltip('收藏'), findsOneWidget);
      expect(find.byIcon(Icons.bookmark_border), findsOneWidget);

      final exam = _FakeExamService(<Question>[_examQuestion(0)]);
      await _launch(tester, examPage(exam, _FakeWrongService()));
      expect(find.byTooltip('收藏'), findsNothing);
      expect(find.byTooltip('取消收藏'), findsNothing);
      expect(find.byIcon(Icons.bookmark_border), findsNothing);
    });

    testWidgets('点收藏：实心图标 + 服务收到 toggle(true) + 提示；再点取消', (tester) async {
      final practice = _FakePracticeService(<Question>[
        _question(1),
        _question(2),
      ]);
      final favorite = _FakeFavoriteService();
      await _launch(tester, practicePage(practice, favorite));

      await tester.tap(find.byTooltip('收藏'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(favorite.toggleCalls, <(String, bool)>[('VLAN-0001', true)]);
      expect(find.byIcon(Icons.bookmark), findsOneWidget);
      expect(find.byIcon(Icons.bookmark_border), findsNothing);
      expect(find.text('已收藏'), findsOneWidget);

      await tester.tap(find.byTooltip('取消收藏'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(favorite.toggleCalls.last, ('VLAN-0001', false));
      expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
      expect(find.byIcon(Icons.bookmark), findsNothing);
      expect(find.text('已取消收藏'), findsOneWidget);
    });

    testWidgets('收藏态按题目 id 还原：下一题未收藏，回看上一题仍收藏', (tester) async {
      final practice = _FakePracticeService(<Question>[
        _question(1),
        _question(2),
      ]);
      final favorite = _FakeFavoriteService();
      await _launch(tester, practicePage(practice, favorite));

      await _tapOption(tester, 'A');
      await tester.tap(find.byTooltip('收藏'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byIcon(Icons.bookmark), findsOneWidget);

      await _tapText(tester, '下一题');
      expect(find.text('题干 2'), findsOneWidget);
      expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
      expect(find.byIcon(Icons.bookmark), findsNothing);

      await _tapText(tester, '上一题');
      expect(find.text('题干 1'), findsOneWidget);
      expect(find.byIcon(Icons.bookmark), findsOneWidget);
      expect(favorite.toggleCalls, <(String, bool)>[('VLAN-0001', true)]);
    });

    testWidgets('进页已收藏的题目直接显示实心图标', (tester) async {
      final practice = _FakePracticeService(<Question>[_question(1)]);
      final favorite = _FakeFavoriteService(initial: <String>{'VLAN-0001'});
      await _launch(tester, practicePage(practice, favorite));

      expect(find.byIcon(Icons.bookmark), findsOneWidget);
      expect(find.byTooltip('取消收藏'), findsOneWidget);
    });

    testWidgets('收藏失败：图标回滚并提示重试', (tester) async {
      final practice = _FakePracticeService(<Question>[_question(1)]);
      final favorite = _FakeFavoriteService()..failToggle = true;
      await _launch(tester, practicePage(practice, favorite));

      await tester.tap(find.byTooltip('收藏'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
      expect(find.byIcon(Icons.bookmark), findsNothing);
      expect(find.text('收藏失败，请重试'), findsOneWidget);
    });
  });

  group('全屏评分页', () {
    /// 独立推入评分页，记录 pop 结果（退出 = true，回顾 = null）。
    Future<void> pumpScore(
      WidgetTester tester,
      ExamScorePage page, {
      void Function(bool?)? onResult,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Center(
              child: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () async {
                    final result = await Navigator.of(
                      context,
                    ).push<bool>(MaterialPageRoute<bool>(builder: (_) => page));
                    onResult?.call(result);
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    ExamScorePage scorePage({
      int total = 3,
      int answered = 3,
      int? score = 92,
      List<Question>? questions,
      Map<String, List<String>>? answers,
      Map<String, ExamQuestionGrade> grading =
          const <String, ExamQuestionGrade>{},
      _FakeWrongService? wrong,
    }) {
      return ExamScorePage(
        total: total,
        answered: answered,
        elapsed: const Duration(minutes: 2, seconds: 5),
        score: score,
        questions:
            questions ??
            <Question>[_examQuestion(0), _examQuestion(1), _examQuestion(2)],
        answers:
            answers ??
            <String, List<String>>{
              'EXAM-0': <String>['A'],
              'EXAM-1': <String>['A'],
              'EXAM-2': <String>['A'],
            },
        grading: grading,
        wrongService: wrong ?? _FakeWrongService(),
        onReview: (_) {},
      );
    }

    testWidgets('得分、答错数、全部错题与加入错题本按钮', (tester) async {
      final wrong = _FakeWrongService();
      await pumpScore(tester, scorePage(grading: _grades, wrong: wrong));

      expect(find.text('考试结果'), findsOneWidget);
      expect(find.text('92 分'), findsOneWidget);
      expect(find.text('答错 2 题'), findsOneWidget);
      expect(find.text('用时 02:05 · 已答 3/3 题'), findsOneWidget);

      // 第一道错题：题干 / 你的答案 / 正确答案 / 解析 / 加入按钮。
      await _scrollTo(tester, find.text('题干 1'));
      expect(find.text('题干 1'), findsOneWidget);
      expect(find.text('你的答案：A'), findsWidgets);
      expect(find.text('正确答案：B'), findsWidgets);
      expect(find.text('解析一'), findsOneWidget);
      expect(find.text('题干 2'), findsNothing, reason: '答对的题不列');

      await tester.tap(find.widgetWithText(OutlinedButton, '加入错题本').first);
      await tester.pumpAndSettle();
      expect(wrong.added, <String>['EXAM-0']);
      // 按钮文案与 snackbar 同文，断言限定在按钮上，避免数到提示条。
      expect(find.widgetWithText(OutlinedButton, '已加入错题本'), findsOneWidget);

      // 第二道错题也在列表里，同样能加入。
      await _scrollTo(tester, find.text('题干 3'));
      expect(find.text('题干 3'), findsOneWidget);
      expect(find.text('解析三'), findsOneWidget);
      await tester.tap(find.widgetWithText(OutlinedButton, '加入错题本').first);
      await tester.pumpAndSettle();
      expect(wrong.added, <String>['EXAM-0', 'EXAM-2']);
    });

    testWidgets('未作答的错题显示「未作答」', (tester) async {
      const grading = <String, ExamQuestionGrade>{
        'EXAM-0': ExamQuestionGrade(
          questionId: 'EXAM-0',
          chosen: <String>[],
          answer: <String>['B'],
          explanation: '解析一',
          correct: false,
        ),
      };
      await pumpScore(
        tester,
        scorePage(
          total: 1,
          answered: 0,
          questions: <Question>[_examQuestion(0)],
          answers: const <String, List<String>>{},
          grading: grading,
        ),
      );

      expect(find.text('答错 1 题'), findsOneWidget);
      await _scrollTo(tester, find.text('你的答案：未作答'));
      expect(find.text('你的答案：未作答'), findsOneWidget);
      expect(find.text('正确答案：B'), findsOneWidget);
    });

    testWidgets('无判分依据：不编造答错数，明说明细未下发', (tester) async {
      await pumpScore(
        tester,
        scorePage(
          questions: <Question>[_examQuestion(0)],
          answers: <String, List<String>>{
            'EXAM-0': <String>['A'],
          },
        ),
      );

      expect(find.text('判分明细未下发，暂无法列出错题'), findsOneWidget);
      expect(find.textContaining('答错'), findsNothing);
      expect(find.text('加入错题本'), findsNothing);
    });

    testWidgets('无判分明细但卷面自带答案键：按答案键列错题', (tester) async {
      final questions = <Question>[
        for (var i = 0; i < 3; i++)
          Question(
            id: 'EXAM-$i',
            module: '',
            type: 'single',
            stem: '题干 ${i + 1}',
            options: const <QuestionOption>[
              QuestionOption(key: 'A', text: 'A 选项'),
              QuestionOption(key: 'B', text: 'B 选项'),
            ],
            answer: const <String>['B'],
            explanation: '自带解析',
            knowledge_point_id: '',
            difficulty: 1,
            set_no: 0,
            row_version: 0,
          ),
      ];
      await pumpScore(tester, scorePage(questions: questions));

      expect(find.text('答错 3 题'), findsOneWidget);
      await _scrollTo(tester, find.text('题干 1'));
      expect(find.text('题干 1'), findsOneWidget);
      // 卡片矮，三道错题可能同进构建窗口：共享文案用 findsWidgets。
      expect(find.text('正确答案：B'), findsWidgets);
      expect(find.text('自带解析'), findsWidgets);
    });

    testWidgets('加入失败：提示重试，按钮仍可再点', (tester) async {
      final wrong = _FakeWrongService()..failAdd = true;
      await pumpScore(tester, scorePage(grading: _grades, wrong: wrong));

      await _scrollTo(tester, find.text('题干 1'));
      await tester.tap(find.widgetWithText(OutlinedButton, '加入错题本').first);
      await tester.pumpAndSettle();

      expect(find.text('加入失败，请重试'), findsOneWidget);
      expect(wrong.added, isEmpty);
      final button = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, '加入错题本').first,
      );
      expect(button.onPressed, isNotNull, reason: '失败后必须还能重试');
    });

    testWidgets('未注册错题本服务：评分页照常渲染，只有加入动作失败', (tester) async {
      // 只搭考试流程的装配（老测试注入 exam/record/session，不注册
      // ServiceLocator.wrongService）也必须能进评分页：进页就取服务会
      // LateInitializationError 整页崩掉，服务只能延迟到点「加入错题本」时取。
      bool? exitResult;
      await pumpScore(
        tester,
        ExamScorePage(
          total: 3,
          answered: 3,
          elapsed: const Duration(minutes: 2, seconds: 5),
          score: 92,
          questions: <Question>[
            _examQuestion(0),
            _examQuestion(1),
            _examQuestion(2),
          ],
          answers: const <String, List<String>>{
            'EXAM-0': <String>['A'],
            'EXAM-1': <String>['A'],
            'EXAM-2': <String>['A'],
          },
          grading: _grades,
          onReview: (_) {},
        ),
        onResult: (result) => exitResult = result,
      );

      expect(find.text('考试结果'), findsOneWidget);
      expect(find.text('92 分'), findsOneWidget);
      expect(find.text('答错 2 题'), findsOneWidget);
      expect(find.text('用时 02:05 · 已答 3/3 题'), findsOneWidget);
      await _scrollTo(tester, find.text('题干 1'));
      expect(find.text('题干 1'), findsOneWidget);
      expect(find.text('解析一'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '加入错题本'), findsWidgets);
      // 退出固定在滚动区之外：没有服务也照样能离开评分页。
      expect(find.text('退出'), findsOneWidget);
      expect(tester.getRect(find.text('退出')).bottom, lessThanOrEqualTo(600));

      await tester.tap(find.widgetWithText(OutlinedButton, '加入错题本').first);
      await tester.pumpAndSettle();
      expect(find.text('加入失败，请重试'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, '加入错题本').first,
            )
            .onPressed,
        isNotNull,
        reason: '服务缺席也不能把按钮卡死在「加入中」',
      );

      // 等提示条自动消失再点退出，避免浮层挡住底部按钮。
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.tap(find.text('退出'));
      await tester.pumpAndSettle();
      expect(exitResult, isTrue);
    });

    testWidgets('20 道错题：退出按钮不用滚动就可见，滚到底仍在底部', (tester) async {
      final questions = <Question>[
        for (var i = 0; i < 20; i++)
          Question(
            id: 'EXAM-$i',
            module: '',
            type: 'single',
            stem: '题干 ${i + 1}',
            options: const <QuestionOption>[
              QuestionOption(key: 'A', text: 'A 选项'),
              QuestionOption(key: 'B', text: 'B 选项'),
            ],
            answer: const <String>['B'],
            explanation: '',
            knowledge_point_id: '',
            difficulty: 1,
            set_no: 0,
            row_version: 0,
          ),
      ];
      final answers = <String, List<String>>{
        for (var i = 0; i < 20; i++) 'EXAM-$i': <String>['A'],
      };
      bool? exitResult;
      await pumpScore(
        tester,
        scorePage(
          total: 20,
          answered: 20,
          questions: questions,
          answers: answers,
        ),
        onResult: (result) => exitResult = result,
      );

      expect(find.text('答错 20 题'), findsOneWidget);
      // 不滚动列表：退出按钮已经在视口内。
      final exitFinder = find.text('退出');
      expect(exitFinder, findsOneWidget);
      final exitRect = tester.getRect(exitFinder);
      expect(exitRect.bottom, lessThanOrEqualTo(600));
      expect(exitRect.top, greaterThan(0));

      // 把错题列表滚到深处，退出按钮依旧固定在底部可见。
      await tester.drag(find.byType(ListView), const Offset(0, -3000));
      await tester.pumpAndSettle();
      expect(exitFinder, findsOneWidget);
      expect(tester.getRect(exitFinder).bottom, lessThanOrEqualTo(600));

      await tester.tap(exitFinder);
      await tester.pumpAndSettle();
      expect(exitResult, isTrue);
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('样例考试不计分：不编造分数', (tester) async {
      await pumpScore(tester, scorePage(score: null, grading: _grades));
      expect(find.text('样例考试，不计分'), findsOneWidget);
      expect(find.text('92 分'), findsNothing);
    });
  });

  group('考试交卷 → 全屏评分页（集成）', () {
    Future<void> answerAndSubmit(WidgetTester tester) async {
      await _tapOption(tester, 'A');
      await _tapText(tester, '下一题');
      await _tapOption(tester, 'A');
      await _tapText(tester, '下一题');
      await _tapOption(tester, 'A');
      await _tapText(tester, '交卷');
      await tester.tap(find.widgetWithText(FilledButton, '确认交卷'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 600));
    }

    testWidgets('半屏 sheet 被全屏评分页取代；退出浮动可见，退出后离开答题页', (tester) async {
      final exam = _FakeExamService(<Question>[
        _examQuestion(0),
        _examQuestion(1),
        _examQuestion(2),
      ], grading: _grades);
      final wrong = _FakeWrongService();
      await _launch(tester, examPage(exam, wrong));
      await answerAndSubmit(tester);

      expect(exam.submitCalls, 1);
      expect(find.byType(ResultSheetContent), findsNothing);
      expect(find.text('考试结果'), findsOneWidget);
      expect(find.text('78 分'), findsOneWidget);
      expect(find.text('答错 2 题'), findsOneWidget);
      expect(exam.gradingExamIds, <String>['E-1']);

      // 退出按钮不滚动就可见。
      final exitFinder = find.text('退出');
      expect(exitFinder, findsOneWidget);
      expect(tester.getRect(exitFinder).bottom, lessThanOrEqualTo(600));

      // 错题逐条列出并可加入错题本（查找限定在评分页内，答题页还压在下面）。
      await _scrollTo(tester, _inScore('题干 1'), scrollable: _scoreScrollable());
      expect(_inScore('你的答案：A'), findsWidgets);
      expect(_inScore('正确答案：B'), findsWidgets);
      expect(_inScore('解析一'), findsOneWidget);
      await tester.tap(find.widgetWithText(OutlinedButton, '加入错题本').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(wrong.added, <String>['EXAM-0']);
      // 按钮文案与 snackbar 同文，断言限定在评分页内的按钮上。
      expect(
        find.descendant(
          of: find.byType(ExamScorePage),
          matching: find.widgetWithText(OutlinedButton, '已加入错题本'),
        ),
        findsOneWidget,
      );

      await _scrollTo(tester, _inScore('题干 3'), scrollable: _scoreScrollable());
      expect(_inScore('解析三'), findsOneWidget);
      // 列表滚到深处，退出仍在底部。
      expect(exitFinder, findsOneWidget);
      expect(tester.getRect(exitFinder).bottom, lessThanOrEqualTo(600));

      await tester.tap(exitFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 600));

      // 离开整个答题流程：不弹退出确认，回到宿主页面。
      expect(find.text('退出答题'), findsNothing);
      expect(find.text('launch'), findsOneWidget);
      final list = records.recordsFor(setId: 'h3cne-2026-01', mode: 'exam');
      expect(list.length, 1);
      expect(list.single.kind, 'completion', reason: '交卷后退出不得再写 breakpoint');
      expect(sessions.load(setId: 'h3cne-2026-01', mode: 'exam'), isNull);
    });

    testWidgets('评分页「逐题回顾」进入回顾，红绿来自服务端判分', (tester) async {
      final exam = _FakeExamService(<Question>[
        _examQuestion(0),
        _examQuestion(1),
        _examQuestion(2),
      ], grading: _grades);
      await _launch(tester, examPage(exam, _FakeWrongService()));
      await answerAndSubmit(tester);

      await _tapText(tester, '逐题回顾');

      expect(find.text('第 1/3 题'), findsOneWidget);
      final tiles = tester
          .widgetList<OptionTile>(find.byType(OptionTile))
          .toList();
      expect(tiles[0].state, OptionTileState.wrong);
      expect(tiles[1].state, OptionTileState.correct);
      expect(find.text('正确答案：B'), findsOneWidget);
    });

    testWidgets('卷面用服务端真实题目 id：暂存 / 判分 / 加入错题本都落在真实 id 上', (tester) async {
      final exam = _RealIdExamService();
      final wrong = _FakeWrongService();
      await _launch(
        tester,
        QuizPage(
          args: const <String, Object?>{
            'mode': 'exam',
            'setId': 'h3cne-2026-01',
            'setTitle': 'A卷',
            'drawCount': 2,
          },
          examService: exam,
          recordService: records,
          sessionService: sessions,
          wrongService: wrong,
        ),
      );

      await _tapOption(tester, 'A');
      await _tapText(tester, '下一题');
      await _tapOption(tester, 'B');
      // 暂存按服务端题目 id 定位，不是自编 EXAM-N 序号。
      expect(exam.savedIds, <String>['q-101', 'q-102']);
      await _tapText(tester, '交卷');
      await tester.tap(find.widgetWithText(FilledButton, '确认交卷'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 600));

      // 判分明细按真实 id 命中：错题列得出来，而不是「明细未下发」。
      expect(exam.gradingExamIds, <String>['E-REAL']);
      expect(find.text('答错 1 题'), findsOneWidget);
      expect(find.text('判分明细未下发，暂无法列出错题'), findsNothing);
      expect(find.text('真实题一'), findsOneWidget);
      expect(find.text('你的答案：A'), findsOneWidget);
      expect(find.text('正确答案：B'), findsOneWidget);
      expect(find.text('真实解析'), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, '加入错题本'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // 加入错题本 POST 的必须是真实题目 id（EXAM-N 会被服务端 404）。
      expect(wrong.added, <String>['q-101']);
    });
  });
}
