/// F29：ocr F27 评审修复的回归测试。
///
/// 覆盖任务书 Tests 节要求的行为：
/// - 统计页加载失败显示错误 + 重试（诚实态），不再折叠成伪造的 0；
/// - 统计页骨架行盒与真实内容行盒一致（默认文字缩放下无纵向位移）；
/// - PreloadSlot：fetch 同步抛错不泄漏在途标记；失败释放 key 可重试；
///   在途并发 consume 不发第二次请求；永不完成的 fetch 由兜底超时释放；
///   null 结果不落槽；已就绪结果超龄过期；
/// - 知识详情预加载取到 null 不毒化详情页（页面重新拉取而非「不存在」）；
/// - 答题入口预热：非模块 setId 不拉全库；缓存层抛错静默且清理标记；
/// - 套卷前置页预加载四请求并行发起；
/// - 题库页只在首次加载成功时预测预加载，切 tab 不再重复预测。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/core/modules.dart';
import 'package:routepass/core/theme.dart';
import 'package:routepass/models/bank_manifest.dart';
import 'package:routepass/models/knowledge_point.dart';
import 'package:routepass/models/question.dart';
import 'package:routepass/models/search.dart';
import 'package:routepass/models/stats.dart';
import 'package:routepass/pages/bank/module_list_page.dart';
import 'package:routepass/pages/bank/stats_page.dart';
import 'package:routepass/pages/knowledge/knowledge_detail_page.dart';
import 'package:routepass/services/bank/answer_entry_preload.dart';
import 'package:routepass/services/bank/bank_manifest_service.dart';
import 'package:routepass/services/bank/cached_practice_service.dart';
import 'package:routepass/services/bank/local_cache_service.dart';
import 'package:routepass/services/bank/question_bank_source.dart';
import 'package:routepass/services/bank/question_repo.dart';
import 'package:routepass/services/bank/set_detail_preload.dart';
import 'package:routepass/services/bank/stats_service.dart';
import 'package:routepass/services/knowledge/knowledge_detail_preload.dart';
import 'package:routepass/services/knowledge/knowledge_repo.dart';
import 'package:routepass/services/knowledge/search_service.dart';
import 'package:routepass/services/mock/mock_practice_service.dart';
import 'package:routepass/services/preload_slot.dart';
import 'package:routepass/widgets/loading_skeleton.dart';

import 'test_helpers.dart';

// ---------------------------------------------------------------------------
// 可控替身
// ---------------------------------------------------------------------------

class _FakeStatsService implements StatsService {
  _FakeStatsService({
    this.overview,
    this.byModule = const <ModuleStat>[],
    this.daily = const <DailyStats>[],
    this.error,
  });

  StatsOverview? overview;
  List<ModuleStat> byModule;
  List<DailyStats> daily;
  Object? error;
  Completer<void>? gate;

  int overviewCalls = 0;
  int byModuleCalls = 0;
  int dailyCalls = 0;

  Future<T> _wait<T>(T value) async {
    final g = gate;
    if (g != null) await g.future;
    final e = error;
    if (e != null) throw e;
    return value;
  }

  @override
  Future<StatsOverview> getOverview() {
    overviewCalls++;
    return _wait(
      overview ??
          const StatsOverview(
            answeredTotal: 0,
            correctRate: 0,
            streakDays: 0,
            todayAnswered: 0,
            todayCorrect: 0,
          ),
    );
  }

  @override
  Future<List<ModuleStat>> getByModule() {
    byModuleCalls++;
    return _wait(byModule);
  }

  @override
  Future<List<DailyStats>> getDaily() {
    dailyCalls++;
    return _wait(daily);
  }
}

/// 记录四个首屏请求的发起顺序；gate 非空时全部停在半路。
class _RecordingRepo extends QuestionRepository {
  _RecordingRepo({
    this.starts,
    this.gate,
  });

  final List<String>? starts;
  final Completer<void>? gate;
  final List<ModuleStat> modules = const <ModuleStat>[];
  final BankSetOverview? overview = null;

  int modulesCalls = 0;

  Future<T> _wait<T>(String name, T value) async {
    starts?.add(name);
    final g = gate;
    if (g != null) await g.future;
    return value;
  }

  @override
  Future<List<ModuleStat>> getModules() {
    modulesCalls++;
    return _wait('modules', modules);
  }

  @override
  Future<List<ModuleStat>> getSetModuleStats({required String setId}) =>
      _wait('setStats', const <ModuleStat>[]);

  @override
  Future<BankSetOverview?> getSetOverview({required String setId}) =>
      _wait('overview', overview);

  @override
  Future<List<Question>> drawQuestions({
    required String mode,
    required int drawCount,
    String? module,
    String? knowledgePointId,
  }) => _wait('draw', const <Question>[]);

  @override
  Future<Question?> getQuestionById(String id) async => null;
}

class _RecordingManifestService extends BankManifestService {
  _RecordingManifestService(this.manifest, {this.starts, this.gate});

  final BankManifest manifest;
  final List<String>? starts;
  final Completer<void>? gate;
  int calls = 0;

  @override
  Future<BankManifest> fetchManifest() async {
    calls++;
    starts?.add('manifest');
    final g = gate;
    if (g != null) await g.future;
    return manifest;
  }
}

class _MutableKnowledgeRepo extends KnowledgeRepository {
  _MutableKnowledgeRepo(this.point);

  KnowledgePoint? point;
  int detailCalls = 0;

  @override
  Future<KnowledgePoint?> getPointDetail(String id) async {
    detailCalls++;
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
  @override
  Future<SearchResult> search(String keyword) async =>
      const SearchResult(knowledgePoints: [], questions: []);
}

class _FakeBankSource extends BankQuestionBankSource {
  _FakeBankSource(this.questions);

  final List<Question> questions;
  int calls = 0;

  @override
  Future<List<Question>> fetchQuestions({
    required String setId,
    String? module,
  }) async {
    calls++;
    return questions;
  }
}

/// hasQuestions 抛错的缓存：预热链必须在槽位外兜底，保持静默 + 清标记。
class _ThrowingCache extends InMemoryBankLocalCache {
  @override
  Future<bool> hasQuestions(String setId) async =>
      throw Exception('cache broken');
}

// ---------------------------------------------------------------------------
// 数据与宿主
// ---------------------------------------------------------------------------

const StatsOverview _overview = StatsOverview(
  answeredTotal: 120,
  correctRate: 0.75,
  streakDays: 2,
  todayAnswered: 10,
  todayCorrect: 8,
);

List<ModuleStat> _byModule() => const <ModuleStat>[
  ModuleStat(module: 'VLAN', total: 0, answered: 40, correctRate: 0.8),
  ModuleStat(module: 'OSPF', total: 0, answered: 0, correctRate: 0),
];

List<DailyStats> _daily() => const <DailyStats>[
  DailyStats(stat_date: '2026-11-16', answered: 10, correct: 8, duration_sec: 600),
  DailyStats(stat_date: '2026-11-15', answered: 5, correct: 3, duration_sec: 300),
];

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

Widget _host(Widget child) => MaterialApp(theme: AppTheme.light, home: child);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initTestServices();

  setUp(() {
    SetDetailPreload.debugClear();
    AnswerEntryPreload.debugClear();
    KnowledgeDetailPreload.debugClear();
  });

  group('StatsPage 诚实错误态 + 骨架行盒（HIGH-1 / MEDIUM-6）', () {
    testWidgets('加载失败显示错误 + 重试，不渲染伪造的 0；重试成功恢复内容', (tester) async {
      final stats = _FakeStatsService(error: Exception('offline'));
      await tester.pumpWidget(_host(StatsPage(statsService: stats)));
      await tester.pumpAndSettle();

      expect(find.text('统计加载失败'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      expect(find.text('累计答题'), findsNothing);
      expect(find.text('连续学习'), findsNothing);
      expect(find.text('暂无数据'), findsNothing);
      expect(find.byType(LoadingSkeleton), findsNothing);

      stats.error = null;
      stats.overview = _overview;
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();

      expect(find.text('统计加载失败'), findsNothing);
      expect(find.text('累计答题'), findsOneWidget);
      expect(find.text('120 题'), findsOneWidget);
      expect(stats.overviewCalls, 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('getOverview 与 getDaily 并行发起，getByModule 保持在其后', (tester) async {
      final stats = _FakeStatsService(overview: _overview);
      final gate = Completer<void>();
      stats.gate = gate;
      await tester.pumpWidget(_host(StatsPage(statsService: stats)));
      await tester.pump();

      // 串行旧实现此刻只有 getOverview 在途；并行后两者同时发起。
      expect(stats.overviewCalls, 1);
      expect(stats.dailyCalls, 1);
      // F30 注：byModule 刻意保持在 overview 之后——它复用 getOverview
      // warmed 的派生缓存（后端无独立 by-module 接口，不多发请求）。
      // 本断言锁定该派生缓存契约；若将来改为并行独立请求，应同步更新。
      expect(stats.byModuleCalls, 0);

      gate.complete();
      await tester.pumpAndSettle();
      expect(stats.byModuleCalls, 1);
      expect(find.text('120 题'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('骨架行盒与真实统计行一致：标题近似、四行行高逐行相等', (tester) async {
      final stats = _FakeStatsService(
        overview: _overview,
        byModule: _byModule(),
        daily: _daily(),
      );
      final gate = Completer<void>();
      stats.gate = gate;
      await tester.pumpWidget(_host(StatsPage(statsService: stats)));
      await tester.pump();

      final skeletonCard = find.byType(Card).first;
      final skeletonRows = find.descendant(
        of: skeletonCard,
        matching: find.byType(Row),
      );
      expect(skeletonRows, findsNWidgets(4));
      final skeletonRowHeights = <double>[
        for (final e in skeletonRows.evaluate())
          (e.renderObject! as RenderBox).size.height,
      ];
      final skeletonTitle = tester.getSize(
        find
            .descendant(
              of: skeletonCard,
              matching: find.byType(LoadingSkeleton),
            )
            .first,
      );

      gate.complete();
      await tester.pumpAndSettle();

      final realCard = find.byType(Card).first;
      final realRows = find.descendant(of: realCard, matching: find.byType(Row));
      expect(realRows, findsNWidgets(4));
      final realRowHeights = <double>[
        for (final e in realRows.evaluate())
          (e.renderObject! as RenderBox).size.height,
      ];
      // 无布局位移的核心不变量：骨架行与真实行逐行同高。
      expect(realRowHeights, skeletonRowHeights);
      // F30：标题骨架只与真实标题行盒做容差交叉校验，不再锁死绝对
      // 字体常量（16sp×1.5=24 之类）——字体度量 / 主题变化不误报。
      expect(
        tester.getSize(find.text('总览')).height,
        closeTo(skeletonTitle.height, 1),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('PreloadSlot 容错 / 并发 / 兜底（HIGH-2 / MEDIUM-7）', () {
    testWidgets('fetch 同步抛错不泄漏在途标记，key 可立即重试', (tester) async {
      final slot = PreloadSlot<String>();
      slot.start('k', () => throw StateError('sync boom'));
      expect(slot.pending('k'), isNull);
      expect(slot.take('k'), isNull);

      slot.start('k', () => Future<String?>.value('ok'));
      await tester.idle();
      expect(await slot.consume('k', () async => 'fallback'), 'ok');

      // 空 key 始终 no-op。
      slot.start('', () => Future<String?>.value('x'));
      expect(slot.pending(''), isNull);
      slot.debugClear();
    });

    testWidgets('异步失败释放 key：不落槽、可重试成功', (tester) async {
      final slot = PreloadSlot<String>();
      slot.start('k', () => Future<String?>.error(StateError('net')));
      await tester.idle();
      expect(slot.pending('k'), isNull);
      expect(slot.take('k'), isNull);

      slot.start('k', () => Future<String?>.value('retry-ok'));
      await tester.idle();
      expect(await slot.consume('k', () async => 'fallback'), 'retry-ok');
      slot.debugClear();
    });

    testWidgets('在途并发 consume 共享同一 Future，不发第二次请求', (tester) async {
      final slot = PreloadSlot<String>();
      final completer = Completer<String?>();
      var fetchCalls = 0;
      slot.start('k', () {
        fetchCalls++;
        return completer.future;
      });

      var fallbackCalls = 0;
      Future<String?> fallback() async {
        fallbackCalls++;
        return 'fallback';
      }

      final first = slot.consume('k', fallback);
      final second = slot.consume('k', fallback);
      // 标记保留到 Future 落定：并发消费期间仍能查到在途。
      expect(slot.pending('k'), isNotNull);

      completer.complete('data');
      await tester.idle();
      expect(await first, 'data');
      expect(await second, 'data');
      expect(fetchCalls, 1);
      expect(fallbackCalls, 0);

      // 落定后在途标记清除，结果落槽：下一次消费直接命中，仍不发请求。
      expect(slot.pending('k'), isNull);
      expect(await slot.consume('k', fallback), 'data');
      expect(fallbackCalls, 0);
      // 取走即清除：再下一次消费才回落 fallback 重新拉取。
      expect(await slot.consume('k', fallback), 'fallback');
      expect(fallbackCalls, 1);
      slot.debugClear();
    });

    testWidgets('null 结果不落槽：消费回落 fallback 重新拉取', (tester) async {
      final slot = PreloadSlot<String>();
      slot.start('k', () => Future<String?>.value(null));
      await tester.idle();
      expect(slot.take('k'), isNull);
      expect(await slot.consume('k', () async => 'fallback'), 'fallback');
      slot.debugClear();
    });

    testWidgets('永不完成的 fetch 由兜底超时释放 key；迟到结果不污染新预载', (tester) async {
      // F30：显式传短超时，不与 30s 默认常量耦合（默认改了本测试不碎）。
      final slot = PreloadSlot<String>(
        fetchTimeout: const Duration(seconds: 1),
      );
      final stuck = Completer<String?>();
      slot.start('k', () => stuck.future);
      expect(slot.pending('k'), isNotNull);

      await tester.pump(const Duration(seconds: 2));
      expect(slot.pending('k'), isNull);

      slot.start('k', () => Future<String?>.value('fresh'));
      stuck.complete('stale');
      await tester.idle();
      // 超时释放后旧 Future 的结果不再落槽，新结果正常可用。
      expect(slot.take('k'), 'fresh');
      slot.debugClear();
    });

    testWidgets('已就绪结果 TTL 内可用、超龄过期（readyTtl 新鲜度检查）', (tester) async {
      // F30：非零 TTL——先验证 TTL 内命中，再验证超龄过期；
      // Duration.zero 恒过期，只测得到退化情形。
      final slot = PreloadSlot<String>(
        readyTtl: const Duration(milliseconds: 100),
      );
      slot.start('k', () => Future<String?>.value('v'));
      await tester.idle();
      expect(slot.take('k'), 'v');

      // DateTime.now() 是真实墙钟：fake pump 不推进它，
      // 用 runAsync 真实等待超过 TTL 再验证过期。
      slot.start('k', () => Future<String?>.value('v2'));
      await tester.idle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 250)),
      );
      expect(slot.take('k'), isNull);
      expect(await slot.consume('k', () async => 'fallback'), 'fallback');
      slot.debugClear();
    });
  });

  group('KnowledgeDetailPreload null 不毒化详情页（HIGH-3）', () {
    testWidgets('预取到 null：详情页重新拉取成功，不显示「不存在」', (tester) async {
      final repo = _MutableKnowledgeRepo(null);
      KnowledgeDetailPreload.start(kpId: 'kp-1', repository: repo);
      await tester.idle();
      expect(repo.detailCalls, 1);

      // 真实拉取会成功：预加载的 null 不得被当成「知识点不存在」。
      repo.point = _kp('kp-1');
      await tester.pumpWidget(
        _host(
          KnowledgeDetailPage(
            args: <String, Object?>{'kpId': 'kp-1'},
            repository: repo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('知识点不存在或已下线'), findsNothing);
      expect(find.text('知识点 kp-1'), findsWidgets);
      expect(repo.detailCalls, 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('预取命中：详情页直接消费，不重复请求', (tester) async {
      final repo = _MutableKnowledgeRepo(_kp('kp-1'));
      KnowledgeDetailPreload.start(kpId: 'kp-1', repository: repo);
      await tester.idle();

      await tester.pumpWidget(
        _host(
          KnowledgeDetailPage(
            args: <String, Object?>{'kpId': 'kp-1'},
            repository: repo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('知识点 kp-1'), findsWidgets);
      expect(repo.detailCalls, 1);
      expect(tester.takeException(), isNull);
    });
  });

  group('AnswerEntryPreload 模块守卫 + 静默失败（MEDIUM-4）', () {
    testWidgets('非模块 setId 不预热：不拉全库、不占用在途标记', (tester) async {
      final cache = InMemoryBankLocalCache();
      final source = _FakeBankSource([_question('VLAN-0001')]);
      final practice = CachedPracticeService(
        delegate: MockPracticeService(),
        cache: cache,
        bankSource: source,
      );

      AnswerEntryPreload.start(setId: 'h3cne-2026-01', service: practice);
      await tester.idle();

      expect(source.calls, 0);
      expect(await cache.hasQuestions('h3cne-2026-01'), isFalse);
      expect(AnswerEntryPreload.debugIsWarming('h3cne-2026-01'), isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('模块 setId 照常预热（守卫不误伤练习套卷）', (tester) async {
      final cache = InMemoryBankLocalCache();
      final source = _FakeBankSource([_question('VLAN-0001')]);
      final practice = CachedPracticeService(
        delegate: MockPracticeService(),
        cache: cache,
        bankSource: source,
      );

      AnswerEntryPreload.start(setId: 'VLAN', service: practice);
      await tester.idle();

      expect(source.calls, 1);
      expect(await cache.hasQuestions('VLAN'), isTrue);
      expect(AnswerEntryPreload.debugIsWarming('VLAN'), isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('缓存层抛错：预热静默失败，_warming 标记必被清理', (tester) async {
      final source = _FakeBankSource([_question('VLAN-0001')]);
      final practice = CachedPracticeService(
        delegate: MockPracticeService(),
        cache: _ThrowingCache(),
        bankSource: source,
      );

      AnswerEntryPreload.start(setId: 'VLAN', service: practice);
      expect(AnswerEntryPreload.debugIsWarming('VLAN'), isTrue);
      await tester.idle();

      expect(AnswerEntryPreload.debugIsWarming('VLAN'), isFalse);
      expect(tester.takeException(), isNull);
    });
  });

  group('SetDetailPreload 四请求并行（MEDIUM-5）', () {
    testWidgets('四个独立请求同时发起，而不是串行之和', (tester) async {
      final starts = <String>[];
      final gate = Completer<void>();
      final repo = _RecordingRepo(starts: starts, gate: gate);
      final manifest = _RecordingManifestService(
        _manifest(),
        starts: starts,
        gate: gate,
      );

      SetDetailPreload.start(
        setId: 'VLAN',
        repository: repo,
        manifestService: manifest,
      );
      await tester.idle();

      // 串行旧实现此刻只有 modules 在途；并行后四项全部已发起。
      expect(starts.length, 4);
      expect(
        starts,
        containsAll(<String>['modules', 'manifest', 'setStats', 'overview']),
      );
      expect(SetDetailPreload.pending('VLAN'), isNotNull);
      // F30：gate 未开——四项全部在途且无一落定（拿不到就绪结果），
      // 「并行」不只是已发起，而是同时处于 pending。
      expect(SetDetailPreload.take('VLAN'), isNull);

      gate.complete();
      await tester.idle();
      final data = SetDetailPreload.take('VLAN');
      expect(data, isNotNull);
      expect(data!.manifest, isNotNull);
      expect(tester.takeException(), isNull);
    });
  });

  group('BankModuleListPage 首次加载才预测（MEDIUM-7）', () {
    testWidgets('切 tab 重拉清单不再重复预测预加载', (tester) async {
      final repo = _RecordingRepo();
      final manifest = _RecordingManifestService(_manifest());
      await tester.pumpWidget(
        _host(
          BankModuleListPage(
            manifestService: manifest,
            questionRepository: repo,
            searchService: _FakeSearchService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 首次加载成功：预测发起了第一张练习套卷卡（VLAN）的前置页预加载。
      // manifest 共 2 次：页面清单 1 次 + 预加载四请求自带的 manifest 1 次。
      expect(manifest.calls, 2);
      expect(repo.modulesCalls, 1);
      expect(SetDetailPreload.take('VLAN'), isNotNull);

      // 切到考试 tab：清单重拉（+1），但不再预测（否则会对考试卷再发一轮，
      // manifest 与 modules 都会再多一次）。
      await tester.tap(find.text('考试'));
      await tester.pumpAndSettle();
      expect(manifest.calls, 3);
      expect(repo.modulesCalls, 1);
      expect(SetDetailPreload.pending('h3cne-2026-01'), isNull);
      expect(SetDetailPreload.take('h3cne-2026-01'), isNull);

      // 切回练习 tab：同样不再预测。
      await tester.tap(find.text('练习'));
      await tester.pumpAndSettle();
      expect(manifest.calls, 4);
      expect(repo.modulesCalls, 1);
      expect(SetDetailPreload.take('VLAN'), isNull);
      expect(tester.takeException(), isNull);
    });
  });
}
