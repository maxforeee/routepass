/// F27 加载骨架 + 预测性预加载测试。
///
/// 覆盖任务书要求的五类断言：
/// - 加载中显示骨架（不是居中进度圈、不是空白页）；
/// - 数据到达后真实内容淡入（SkeletonToContent / FadeOnly）；
/// - 预加载完成的页面打开即有数据，无骨架闪烁；
/// - 预测性预加载在后台发起下一步请求，且不阻塞当前页与导航；
/// - 骨架与真实内容占位一致，无布局位移。
/// 另覆盖诚实态：清单 / 试卷失败显示既有错误重试态，不显示假骨架。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/core/modules.dart';
import 'package:routepass/core/theme.dart';
import 'package:routepass/models/answer_record.dart';
import 'package:routepass/models/bank_manifest.dart';
import 'package:routepass/models/knowledge_point.dart';
import 'package:routepass/models/practice.dart';
import 'package:routepass/models/question.dart';
import 'package:routepass/models/search.dart';
import 'package:routepass/models/stats.dart';
import 'package:routepass/pages/bank/answer_record_paper_page.dart';
import 'package:routepass/pages/bank/module_list_page.dart';
import 'package:routepass/pages/bank/quiz_page.dart';
import 'package:routepass/pages/bank/set_detail_page.dart';
import 'package:routepass/pages/knowledge/knowledge_detail_page.dart';
import 'package:routepass/services/bank/answer_entry_preload.dart';
import 'package:routepass/services/bank/bank_manifest_service.dart';
import 'package:routepass/services/bank/cached_practice_service.dart';
import 'package:routepass/services/bank/local_cache_service.dart';
import 'package:routepass/services/bank/practice_service.dart';
import 'package:routepass/services/bank/question_bank_source.dart';
import 'package:routepass/services/bank/question_repo.dart';
import 'package:routepass/services/bank/record_paper_preload.dart';
import 'package:routepass/services/bank/set_detail_preload.dart';
import 'package:routepass/services/knowledge/knowledge_detail_preload.dart';
import 'package:routepass/services/knowledge/knowledge_repo.dart';
import 'package:routepass/services/knowledge/search_service.dart';
import 'package:routepass/services/mock/mock_practice_service.dart';
import 'package:routepass/widgets/loading_skeleton.dart';
import 'package:routepass/widgets/set_row_card.dart';

import 'test_helpers.dart';

// ---------------------------------------------------------------------------
// 可控替身：gate 非空时所有读路径停在半路，模拟网络在途。
// ---------------------------------------------------------------------------

class _FakeRepo extends QuestionRepository {
  _FakeRepo({this.modules = const <ModuleStat>[], this.overview, this.error});

  final List<ModuleStat> modules;
  final List<ModuleStat> setStats = const <ModuleStat>[];
  final BankSetOverview? overview;
  final List<Question> questions = const <Question>[];
  final Object? error;

  Completer<void>? gate;

  int modulesCalls = 0;
  int drawCalls = 0;
  String? lastDrawMode;
  int? lastDrawCount;

  Future<T> _wait<T>(T value) async {
    final g = gate;
    if (g != null) await g.future;
    final e = error;
    if (e != null) throw e;
    return value;
  }

  @override
  Future<List<ModuleStat>> getModules() {
    modulesCalls++;
    return _wait(modules);
  }

  @override
  Future<List<ModuleStat>> getSetModuleStats({required String setId}) =>
      _wait(setStats);

  @override
  Future<BankSetOverview?> getSetOverview({required String setId}) =>
      _wait(overview);

  @override
  Future<List<Question>> drawQuestions({
    required String mode,
    required int drawCount,
    String? module,
    String? knowledgePointId,
  }) {
    drawCalls++;
    lastDrawMode = mode;
    lastDrawCount = drawCount;
    return _wait(questions);
  }

  @override
  Future<Question?> getQuestionById(String id) async => null;
}

class _FakeManifestService extends BankManifestService {
  _FakeManifestService(this.manifest, {this.error});

  final BankManifest manifest;
  final Object? error;
  Completer<void>? gate;

  @override
  Future<BankManifest> fetchManifest() async {
    final g = gate;
    if (g != null) await g.future;
    final e = error;
    if (e != null) throw e;
    return manifest;
  }
}

class _FakePaperService extends PracticeService {
  _FakePaperService({this.paper});

  PracticeRecordPaper? paper;
  Completer<void>? gate;
  int paperCalls = 0;

  @override
  Future<PracticeRecordPaper?> getRecordPaper(String sessionId) async {
    paperCalls++;
    final g = gate;
    if (g != null) await g.future;
    return paper;
  }

  @override
  Future<PracticeSession> startSession({
    required List<Question> questions,
    required String mode,
  }) async => throw UnimplementedError();

  @override
  Future<AnswerResult> submitAnswer({
    required String sessionId,
    required String questionId,
    required List<String> chosen,
    required int durationMs,
    String? setId,
    String? opId,
    String? mode,
  }) async => throw UnimplementedError();

  @override
  Future<PracticeNext?> drawNextQuestion({
    required String setId,
    String? module,
    required Set<String> excludedIds,
    String? sessionId,
  }) async => null;

  @override
  Future<ContinueSession?> getContinueSession() async => null;
}

class _FakeKnowledgeRepo extends KnowledgeRepository {
  _FakeKnowledgeRepo(this.point);

  final KnowledgePoint? point;
  int detailCalls = 0;
  Completer<void>? gate;

  @override
  Future<KnowledgePoint?> getPointDetail(String id) async {
    detailCalls++;
    final g = gate;
    if (g != null) await g.future;
    return point;
  }

  @override
  Future<List<Chapter>> getChapters() async => const <Chapter>[];

  @override
  Future<List<Section>> getSections(String chapterId) async =>
      const <Section>[];

  @override
  Future<List<KnowledgePoint>> getPointsBySection(String sectionId) async =>
      const <KnowledgePoint>[];

  @override
  Future<List<KnowledgePoint>> getPointsByQuestion(String questionId) async =>
      const <KnowledgePoint>[];

  @override
  Future<KnowledgePoint?> getDailyPoint() async => null;
}

class _FakeSearchService extends SearchService {
  _FakeSearchService(this.result);

  final SearchResult result;
  Completer<void>? gate;

  @override
  Future<SearchResult> search(String keyword) async {
    final g = gate;
    if (g != null) await g.future;
    return result;
  }
}

class _FakeBankSource extends BankQuestionBankSource {
  _FakeBankSource(this.questions, {this.error});

  final List<Question> questions;
  final Object? error;
  Completer<void>? gate;
  int calls = 0;

  @override
  Future<List<Question>> fetchQuestions({
    required String setId,
    String? module,
  }) async {
    calls++;
    final g = gate;
    if (g != null) await g.future;
    final e = error;
    if (e != null) throw e;
    return questions;
  }
}

// ---------------------------------------------------------------------------
// 数据与宿主
// ---------------------------------------------------------------------------

BankManifest _manifest() => BankManifest(
  bankId: 'bank-1',
  version: 'v1',
  questionCount: 500,
  practiceSets: [
    for (final module in kModuleOrder)
      PracticeSetRecord(module: module, questionCount: 100),
  ],
  examSets: const <ExamSetRecord>[
    ExamSetRecord(id: 'h3cne-2026-01', title: 'A卷', questionCount: 100),
  ],
);

List<ModuleStat> _modules() => [
  for (final module in kModuleOrder)
    ModuleStat(module: module, total: 100, answered: 0, correctRate: 0.0),
];

const BankSetOverview _overview = BankSetOverview(
  setId: 'VLAN',
  total: 100,
  done: 40,
  remaining: 60,
  byType: QuestionTypeStat(setId: 'VLAN', single: 60, multiple: 40),
  accuracy: 0.8,
);

Question _question(String id) => Question(
  id: id,
  module: 'VLAN',
  type: 'single',
  stem: '题干 $id',
  options: const <QuestionOption>[
    QuestionOption(key: 'A', text: '选项A'),
    QuestionOption(key: 'B', text: '选项B'),
  ],
  answer: const <String>['A'],
  explanation: '解析',
  knowledge_point_id: '',
  difficulty: 1,
  set_no: 0,
  row_version: 0,
);

AnswerRecord _record() => const AnswerRecord(
  id: 'rec-1',
  setId: 'VLAN',
  setTitle: 'VLAN',
  mode: 'practice',
  kind: 'completion',
  targetCount: 20,
  answeredCount: 20,
  totalCount: 20,
  durationMs: 60000,
  createdAt: 1000,
  updatedAt: 2000,
  correctCount: 16,
  serverId: 'sess-1',
);

PracticeRecordPaper _paper() => PracticeRecordPaper(
  sessionId: 'sess-1',
  module: 'VLAN',
  status: 'completed',
  items: <PracticePaperItem>[
    PracticePaperItem(
      questionId: 'q-1',
      question: _question('q-1'),
      chosen: const <String>['A'],
      correct: true,
      explanation: '解析',
    ),
  ],
);

KnowledgePoint _kp(String id) => KnowledgePoint(
  id: id,
  module: 'VLAN',
  topic: 'VLAN',
  code: '1.1',
  title: '知识点 $id',
  summary: '摘要',
  content_md: '# 标题\n正文',
  row_version: 1,
);

Map<String, Object?> _setArgs({
  String mode = 'practice',
  String setId = 'VLAN',
  int drawCount = 100,
}) => <String, Object?>{'mode': mode, 'setId': setId, 'drawCount': drawCount};

Widget _host(Widget child) => MaterialApp(theme: AppTheme.light, home: child);

/// 题库页 → 前置页的命名路由宿主（预加载导航测试用）。
Widget _bankHost({
  required BankManifestService manifestService,
  required QuestionRepository repository,
  SearchService? searchService,
}) => MaterialApp(
  theme: AppTheme.light,
  home: BankModuleListPage(
    manifestService: manifestService,
    questionRepository: repository,
    searchService: searchService,
  ),
  onGenerateRoute: (settings) => MaterialPageRoute<void>(
    settings: settings,
    builder: (_) => SetDetailPage(
      args:
          (settings.arguments as Map<String, Object?>?) ??
          const <String, Object?>{},
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initTestServices();

  setUp(() {
    SetDetailPreload.debugClear();
    AnswerEntryPreload.debugClear();
    RecordPaperPreload.debugClear();
    KnowledgeDetailPreload.debugClear();
  });

  group('SetDetailPage 骨架 + 淡入', () {
    testWidgets('加载中显示骨架（无居中进度圈），数据到达后淡入', (tester) async {
      final repo = _FakeRepo(modules: _modules(), overview: _overview);
      final gate = Completer<void>();
      repo.gate = gate;
      await tester.pumpWidget(
        _host(
          SetDetailPage(
            args: _setArgs(),
            questionRepository: repo,
            manifestService: _FakeManifestService(_manifest()),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(LoadingSkeleton), findsWidgets);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      // 真实内容尚未挂载，不提前显示“待接口”文案。
      expect(find.text('题量待接口 · 进度待接口'), findsNothing);

      gate.complete();
      await tester.pumpAndSettle();

      expect(find.byType(LoadingSkeleton), findsNothing);
      expect(find.byType(SkeletonToContent), findsWidgets);
      expect(find.text('100 题 · 进度待接口'), findsNWidgets(5));
      expect(find.text('已答题数：40'), findsOneWidget);
      expect(find.text('正确率 80.0%'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('无布局位移：骨架与真实内容占位一致', (tester) async {
      final repo = _FakeRepo(modules: _modules(), overview: _overview);
      final gate = Completer<void>();
      repo.gate = gate;
      await tester.pumpWidget(
        _host(
          SetDetailPage(
            args: _setArgs(),
            questionRepository: repo,
            manifestService: _FakeManifestService(_manifest()),
          ),
        ),
      );
      await tester.pump();

      // 模块行下方的「练习目标」行位置在骨架态与就绪态必须完全一致，
      // 即题型行 / 完成行 / 五个模块行的总高度不变。
      final targetBefore = tester.getTopLeft(find.text('练习目标')).dy;
      final sectionBefore = tester.getTopLeft(find.text('知识点考察')).dy;

      gate.complete();
      await tester.pumpAndSettle();

      expect(tester.getTopLeft(find.text('练习目标')).dy, targetBefore);
      expect(tester.getTopLeft(find.text('知识点考察')).dy, sectionBefore);
      expect(tester.takeException(), isNull);
    });

    testWidgets('预加载完成：打开即有数据，无骨架闪烁', (tester) async {
      final repo = _FakeRepo(modules: _modules(), overview: _overview);
      final manifest = _FakeManifestService(_manifest());
      SetDetailPreload.start(
        setId: 'VLAN',
        repository: repo,
        manifestService: manifest,
      );
      await SetDetailPreload.pending('VLAN');

      await tester.pumpWidget(
        _host(
          SetDetailPage(
            args: _setArgs(),
            questionRepository: repo,
            manifestService: manifest,
          ),
        ),
      );
      await tester.pump();

      // 首帧即真实内容：没有骨架，也没有第二次首屏请求。
      expect(find.byType(LoadingSkeleton), findsNothing);
      expect(find.text('100 题 · 进度待接口'), findsNWidgets(5));
      expect(find.text('已答题数：40'), findsOneWidget);
      expect(repo.modulesCalls, 1);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('BankModuleListPage 预加载 + 骨架', () {
    testWidgets('清单加载中显示同高骨架，到达后卡片淡入且位置不变', (tester) async {
      final manifest = _FakeManifestService(_manifest());
      final gate = Completer<void>();
      manifest.gate = gate;
      await tester.pumpWidget(
        _host(
          BankModuleListPage(
            manifestService: manifest,
            questionRepository: _FakeRepo(),
            searchService: _FakeSearchService(
              const SearchResult(knowledgePoints: [], questions: []),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(LoadingSkeleton), findsNWidgets(5));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      final skeletonRect = tester.getRect(find.byType(LoadingSkeleton).first);
      expect(skeletonRect.height, AppSizes.setRowMinHeight);

      gate.complete();
      await tester.pumpAndSettle();

      expect(find.byType(SetRowCard), findsNWidgets(5));
      expect(find.byType(LoadingSkeleton), findsNothing);
      final cardRect = tester.getRect(find.byType(SetRowCard).first);
      expect(cardRect.height, skeletonRect.height);
      expect(cardRect.topLeft, skeletonRect.topLeft);
      expect(tester.takeException(), isNull);
    });

    testWidgets('预测性预加载：清单到达后后台预取第一张套卷卡的前置页数据', (tester) async {
      final repo = _FakeRepo(modules: _modules(), overview: _overview);
      final gate = Completer<void>();
      repo.gate = gate;
      await tester.pumpWidget(
        _host(
          BankModuleListPage(
            manifestService: _FakeManifestService(_manifest()),
            questionRepository: repo,
            searchService: _FakeSearchService(
              const SearchResult(knowledgePoints: [], questions: []),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 当前页照常渲染（未被预加载阻塞），而第一步的详情请求已在途。
      expect(find.byType(SetRowCard), findsNWidgets(5));
      expect(repo.modulesCalls, 1);
      expect(SetDetailPreload.pending('VLAN'), isNotNull);

      gate.complete();
      await tester.pumpAndSettle();
      expect(SetDetailPreload.take('VLAN'), isNotNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('点按套卷卡：先预加载再导航，请求在途不阻塞导航', (tester) async {
      final repo = _FakeRepo(modules: _modules(), overview: _overview);
      final gate = Completer<void>();
      repo.gate = gate;
      await tester.pumpWidget(
        _bankHost(
          manifestService: _FakeManifestService(_manifest()),
          repository: repo,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(SetRowCard).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // 导航已完成；数据仍在途 → 前置页显示骨架而不是空白。
      expect(find.byType(SetDetailPage), findsOneWidget);
      expect(find.byType(LoadingSkeleton), findsWidgets);

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('100 题 · 进度待接口'), findsNWidgets(5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('清单失败：显示错误 + 重试（诚实态），不显示假骨架', (tester) async {
      await tester.pumpWidget(
        _host(
          BankModuleListPage(
            manifestService: _FakeManifestService(
              _manifest(),
              error: Exception('offline'),
            ),
            questionRepository: _FakeRepo(),
            searchService: _FakeSearchService(
              const SearchResult(knowledgePoints: [], questions: []),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('题库清单加载失败'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      expect(find.byType(LoadingSkeleton), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('预加载失败不影响当前页，也不阻塞导航', (tester) async {
      final repo = _FakeRepo(error: Exception('offline'));
      await tester.pumpWidget(
        _bankHost(
          manifestService: _FakeManifestService(_manifest()),
          repository: repo,
        ),
      );
      await tester.pumpAndSettle();

      // 预测预加载的单项失败静默降级（模块为空、清单仍取到），当前页照常。
      expect(find.byType(SetRowCard), findsNWidgets(5));

      await tester.tap(find.byType(SetRowCard).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      // 前置页正常打开：模块题量回落到清单 practiceByModule 的真实题量，
      // 进度无真实已答数 → 待接口，不虚构。
      expect(find.byType(SetDetailPage), findsOneWidget);
      expect(find.text('100 题 · 进度待接口'), findsNWidgets(5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('搜索结果：搜索中显示骨架，结果到达淡入', (tester) async {
      final search = _FakeSearchService(
        SearchResult(knowledgePoints: const [], questions: [_question('q-1')]),
      );
      final gate = Completer<void>();
      search.gate = gate;
      await tester.pumpWidget(
        _host(
          BankModuleListPage(
            manifestService: _FakeManifestService(_manifest()),
            questionRepository: _FakeRepo(),
            searchService: search,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'VLAN');
      // F29：防抖 300ms，pump 留足余量（原 350ms 贴边，计时抖动敏感）。
      await tester.pump(const Duration(milliseconds: 500));

      // F30：按卡形断言——4 张结果骨架卡、每卡恰好 2 行；不再依赖
      // 全局总数 8（套卷骨架 itemCount / 视口裁剪变化不会误伤本断言），
      // 裸骨架（无 Card）也混不进计数。
      final skeletonCards = find.byType(Card);
      expect(skeletonCards, findsNWidgets(4));
      for (final card in skeletonCards.evaluate()) {
        expect(
          find.descendant(
            of: find.byWidget(card),
            matching: find.byType(LoadingSkeleton),
          ),
          findsNWidgets(2),
        );
      }
      expect(
        find.descendant(
          of: skeletonCards,
          matching: find.byType(LoadingSkeleton),
        ),
        findsNWidgets(8),
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('题干 q-1'), findsOneWidget);
      expect(find.byType(LoadingSkeleton), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('AnswerEntryPreload 答题入口预热', () {
    testWidgets('前置页后台预热本地题库：首题命中缓存，不重复拉取', (tester) async {
      final cache = InMemoryBankLocalCache();
      final source = _FakeBankSource([_question('VLAN-0001')]);
      final practice = CachedPracticeService(
        delegate: MockPracticeService(),
        cache: cache,
        bankSource: source,
      );
      await tester.pumpWidget(
        _host(
          SetDetailPage(
            args: _setArgs(),
            questionRepository: _FakeRepo(modules: _modules()),
            manifestService: _FakeManifestService(_manifest()),
            practiceService: practice,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 预测性预热已在后台把整套题库写进本地缓存。
      expect(source.calls, 1);
      expect(await cache.hasQuestions('VLAN'), isTrue);

      // 答题页首题抽题直接命中本地，不再发第二次题库拉取。
      final next = await practice.drawNextQuestion(
        setId: 'VLAN',
        excludedIds: const <String>{},
      );
      expect(next?.question.id, 'VLAN-0001');
      expect(source.calls, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('题库已缓存：预热短路，不发请求', (tester) async {
      final cache = InMemoryBankLocalCache();
      await cache.writeQuestions(
        setId: 'VLAN',
        questions: [_question('VLAN-0001')],
      );
      final source = _FakeBankSource([_question('VLAN-0002')]);
      final practice = CachedPracticeService(
        delegate: MockPracticeService(),
        cache: cache,
        bankSource: source,
      );
      await tester.pumpWidget(
        _host(
          SetDetailPage(
            args: _setArgs(),
            questionRepository: _FakeRepo(modules: _modules()),
            manifestService: _FakeManifestService(_manifest()),
            practiceService: practice,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(source.calls, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('考试前置页不预热（不预创建服务端考卷）', (tester) async {
      final source = _FakeBankSource([_question('VLAN-0001')]);
      final practice = CachedPracticeService(
        delegate: MockPracticeService(),
        cache: InMemoryBankLocalCache(),
        bankSource: source,
      );
      await tester.pumpWidget(
        _host(
          SetDetailPage(
            args: _setArgs(mode: 'exam', setId: 'h3cne-2026-01'),
            questionRepository: _FakeRepo(modules: _modules()),
            manifestService: _FakeManifestService(_manifest()),
            practiceService: practice,
          ),
        ),
      );
      await tester.pump();
      // F29：直接断言预热状态——考试 setId 从未进入在途标记。
      // F30 注：_preloadAnswerEntry 对考试直接 return、从不调用 start，
      // 首帧的 false 是「设计上跳过」，不是「预热尚未开始」。
      expect(AnswerEntryPreload.debugIsWarming('h3cne-2026-01'), isFalse);
      await tester.pumpAndSettle();
      expect(source.calls, 0);
      expect(AnswerEntryPreload.debugIsWarming('h3cne-2026-01'), isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('预热在途不阻塞前置页渲染', (tester) async {
      final source = _FakeBankSource([_question('VLAN-0001')]);
      final gate = Completer<void>();
      source.gate = gate;
      final practice = CachedPracticeService(
        delegate: MockPracticeService(),
        cache: InMemoryBankLocalCache(),
        bankSource: source,
      );
      await tester.pumpWidget(
        _host(
          SetDetailPage(
            args: _setArgs(),
            questionRepository: _FakeRepo(modules: _modules()),
            manifestService: _FakeManifestService(_manifest()),
            practiceService: practice,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 预热请求仍在途，前置页内容已完整渲染。
      expect(find.text('100 题 · 进度待接口'), findsNWidgets(5));
      // F29：在途标记直接可观测（与考试不预热断言互为正反对照）。
      expect(AnswerEntryPreload.debugIsWarming('VLAN'), isTrue);
      gate.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('预热失败静默：前置页照常，不抛给 UI', (tester) async {
      final source = _FakeBankSource(
        const <Question>[],
        error: Exception('offline'),
      );
      final practice = CachedPracticeService(
        delegate: MockPracticeService(),
        cache: InMemoryBankLocalCache(),
        bankSource: source,
      );
      await tester.pumpWidget(
        _host(
          SetDetailPage(
            args: _setArgs(),
            questionRepository: _FakeRepo(modules: _modules()),
            manifestService: _FakeManifestService(_manifest()),
            practiceService: practice,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('100 题 · 进度待接口'), findsNWidgets(5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('端到端：预热后答题页首题即开，不重复拉取题库', (tester) async {
      final cache = InMemoryBankLocalCache();
      final source = _FakeBankSource([_question('VLAN-0001')]);
      final practice = CachedPracticeService(
        delegate: MockPracticeService(),
        cache: cache,
        bankSource: source,
      );
      await tester.pumpWidget(
        _host(
          SetDetailPage(
            args: _setArgs(),
            questionRepository: _FakeRepo(modules: _modules()),
            manifestService: _FakeManifestService(_manifest()),
            practiceService: practice,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(source.calls, 1);

      // 换宿主前先卸掉旧树，避免无 key 宿主复用 Navigator 旧路由栈。
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        _host(
          QuizPage(
            args: <String, Object?>{
              'mode': 'practice',
              'setId': 'VLAN',
              'setTitle': 'VLAN',
              'drawCount': 100,
              'target': 20,
            },
            practiceService: practice,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('第 1/20 题'), findsOneWidget);
      expect(source.calls, 1);
      expect(tester.takeException(), isNull);
    });
  });

  group('RecordPaperPreload 试卷页', () {
    testWidgets('试卷加载中显示骨架（无居中进度圈），到达后淡入', (tester) async {
      final service = _FakePaperService(paper: _paper());
      final gate = Completer<void>();
      service.gate = gate;
      await tester.pumpWidget(
        _host(
          AnswerRecordPaperPage(
            args: <String, Object?>{'record': _record(), 'sessionId': 'sess-1'},
            practiceService: service,
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(LoadingSkeleton), findsWidgets);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('第 1 题'), findsOneWidget);
      expect(find.byType(LoadingSkeleton), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('预加载完成：试卷页打开即有卷面，不重复请求', (tester) async {
      final service = _FakePaperService(paper: _paper());
      RecordPaperPreload.start(sessionId: 'sess-1', service: service);
      // testWidgets 跑在 FakeAsync 里：Future.delayed 的定时器不 pump 就
      // 永不触发，await 它会 0% CPU 死等（整套套件挂起的根因）。idle() 冲刷
      // 微任务并触发零时长定时器，预加载链（纯微任务）就此落槽。
      await tester.idle();

      await tester.pumpWidget(
        _host(
          AnswerRecordPaperPage(
            args: <String, Object?>{'record': _record(), 'sessionId': 'sess-1'},
            practiceService: service,
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(LoadingSkeleton), findsNothing);
      expect(find.text('第 1 题'), findsOneWidget);
      expect(service.paperCalls, 1);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('试卷拉取失败：显示重试态，不显示假骨架', (tester) async {
      final service = _FakePaperService(paper: null);
      await tester.pumpWidget(
        _host(
          AnswerRecordPaperPage(
            args: <String, Object?>{'record': _record(), 'sessionId': 'sess-1'},
            practiceService: service,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('试卷加载失败'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      expect(find.byType(LoadingSkeleton), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('KnowledgeDetailPreload 知识详情', () {
    test('预加载命中：consume 返回预取结果，不重复请求', () async {
      final repo = _FakeKnowledgeRepo(_kp('kp-1'));
      KnowledgeDetailPreload.start(kpId: 'kp-1', repository: repo);
      await Future<void>.delayed(Duration.zero);

      final point = await KnowledgeDetailPreload.consume(
        kpId: 'kp-1',
        repository: repo,
      );
      expect(point?.id, 'kp-1');
      expect(repo.detailCalls, 1);
    });

    testWidgets('知识详情页：加载中显示骨架，内容到达后淡入', (tester) async {
      // F29：注入 fake KnowledgeRepository，详情拉取本身不再走 ServiceLocator。
      // F30 更正：本测试仍依赖全局 initTestServices()——页面未注入的
      // 协作者仍由 ServiceLocator 兜底，并非完全脱离单例。
      final repo = _FakeKnowledgeRepo(_kp('kp-1'));
      final gate = Completer<void>();
      repo.gate = gate;

      await tester.pumpWidget(
        _host(
          KnowledgeDetailPage(
            args: <String, Object?>{'kpId': 'kp-1'},
            repository: repo,
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(LoadingSkeleton), findsWidgets);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('知识点 kp-1'), findsWidgets);
      expect(find.byType(LoadingSkeleton), findsNothing);
      expect(repo.detailCalls, 1);
      expect(tester.takeException(), isNull);
    });
  });
}
