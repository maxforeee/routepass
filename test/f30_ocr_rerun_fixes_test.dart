/// F30：ocr F29 复评（23 条新发现）修复的回归测试。
///
/// 覆盖：
/// - H1：在途 fetch 失败时 consume 回落 fallback，不把错误抛给消费方；
/// - M2：兜底超时把在途 Future 落定为失败——consume / pending 的消费方
///   随之回落，不再永久挂起；迟到落定被静默吸收；
/// - M1：迟到落定不取消同 key 新 fetch 的兜底定时器；
/// - M4：overview 回落兜底时 byModule 派生缓存失效（成功路径本就新鲜，
///   另立契约测试锁定）；
/// - M5：页面销毁后触发重试（_load）不再 setState 抛错；
/// - M6：失败重试清空旧载荷（契约锁定——现 build 以 _failed 为先，
///   UI 行为前后一致，修复消除的是潜在陈旧数据）；
/// - M7：RecordPaperPreload 预取到 null 不毒化试卷页（仍显示重试态）；
/// - L6：overview/daily 成功但 getByModule / getDaily 单独失败的诚实错误态。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:routepass/core/theme.dart';
import 'package:routepass/models/answer_record.dart';
import 'package:routepass/models/practice.dart';
import 'package:routepass/models/question.dart';
import 'package:routepass/models/stats.dart';
import 'package:routepass/pages/bank/answer_record_paper_page.dart';
import 'package:routepass/pages/bank/stats_page.dart';
import 'package:routepass/services/bank/practice_service.dart';
import 'package:routepass/services/bank/record_paper_preload.dart';
import 'package:routepass/services/bank/stats_service.dart';
import 'package:routepass/services/preload_slot.dart';

// ---------------------------------------------------------------------------
// 可控替身
// ---------------------------------------------------------------------------

/// 三个读路径可分别注入错误 / gate，覆盖并行加载的单路失败边界。
class _StatsStub implements StatsService {
  _StatsStub({
    this.overview,
    this.byModule = const <ModuleStat>[],
    this.daily = const <DailyStats>[],
    this.overviewError,
    this.byModuleError,
    this.dailyError,
  });

  StatsOverview? overview;
  List<ModuleStat> byModule;
  List<DailyStats> daily;
  Object? overviewError;
  Object? byModuleError;
  Object? dailyError;
  Completer<void>? gate;

  int overviewCalls = 0;
  int byModuleCalls = 0;
  int dailyCalls = 0;

  Future<T> _wait<T>(T value, Object? error) async {
    final g = gate;
    if (g != null) await g.future;
    if (error != null) throw error;
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
      overviewError,
    );
  }

  @override
  Future<List<ModuleStat>> getByModule() {
    byModuleCalls++;
    return _wait(byModule, byModuleError);
  }

  @override
  Future<List<DailyStats>> getDaily() {
    dailyCalls++;
    return _wait(daily, dailyError);
  }
}

/// M4 的本地兜底：全 0 overview + 可辨识的 MOCK 模块行。
class _ZeroStats implements StatsService {
  @override
  Future<StatsOverview> getOverview() async => const StatsOverview(
    answeredTotal: 0,
    correctRate: 0,
    streakDays: 0,
    todayAnswered: 0,
    todayCorrect: 0,
  );

  @override
  Future<List<ModuleStat>> getByModule() async => const <ModuleStat>[
    ModuleStat(module: 'MOCK', total: 0, answered: 0, correctRate: 0),
  ];

  @override
  Future<List<DailyStats>> getDaily() async => const <DailyStats>[];
}

/// 试卷服务替身：只实现 getRecordPaper，其余路径本测试不会触达。
class _PaperStub extends PracticeService {
  _PaperStub({this.paper});

  PracticeRecordPaper? paper;
  int paperCalls = 0;

  @override
  Future<PracticeRecordPaper?> getRecordPaper(String sessionId) async {
    paperCalls++;
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

const List<ModuleStat> _byModule = <ModuleStat>[
  ModuleStat(module: 'VLAN', total: 0, answered: 40, correctRate: 0.8),
];

const List<DailyStats> _daily = <DailyStats>[
  DailyStats(stat_date: '2026-11-16', answered: 10, correct: 8, duration_sec: 600),
];

const AnswerRecord _record = AnswerRecord(
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

Widget _host(Widget child) => MaterialApp(theme: AppTheme.light, home: child);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    RecordPaperPreload.debugClear();
  });

  tearDown(() {
    RecordPaperPreload.debugClear();
  });

  group('PreloadSlot 消费方兜底（H1 / M2 / M1）', () {
    testWidgets('H1 在途 fetch 失败：consume 回落 fallback，不向消费方抛错', (tester) async {
      final slot = PreloadSlot<String>();
      final completer = Completer<String?>();
      slot.start('k', () => completer.future);

      var fallbackCalls = 0;
      final result = slot.consume('k', () async {
        fallbackCalls++;
        return 'fallback';
      });
      completer.completeError(StateError('net'));
      await tester.idle();

      // 修复前：consume 透传原始 Future 的错误，await 直接抛。
      expect(await result, 'fallback');
      expect(fallbackCalls, 1);
      expect(slot.pending('k'), isNull);
      expect(tester.takeException(), isNull);
      slot.debugClear();
    });

    testWidgets('M2 兜底超时把在途 Future 落定为失败：consume / pending 不再永久挂起', (tester) async {
      final slot = PreloadSlot<String>(
        fetchTimeout: const Duration(seconds: 1),
      );
      final stuck = Completer<String?>();
      slot.start('k', () => stuck.future);

      final consumed = slot.consume('k', () async => 'fallback');
      final pending = slot.pending('k')!;
      final pendingResult = pending.then<String?>(
        (value) => value,
        onError: (_) => 'pending-fallback',
      );

      // 修复前：watchdog 只清标记，两个消费方永远等不到落定。
      await tester.pump(const Duration(seconds: 2));
      expect(await consumed, 'fallback');
      expect(await pendingResult, 'pending-fallback');
      expect(slot.pending('k'), isNull);

      // 迟到的失败被静默吸收，不成为未处理异步错误。
      stuck.completeError(StateError('late'));
      await tester.idle();
      expect(tester.takeException(), isNull);

      // key 已释放：可立即重试成功。
      slot.start('k', () => Future<String?>.value('retry-ok'));
      await tester.idle();
      expect(slot.take('k'), 'retry-ok');
      slot.debugClear();
    });

    testWidgets('M1 迟到落定不取消同 key 新 fetch 的兜底定时器', (tester) async {
      final slot = PreloadSlot<String>(
        fetchTimeout: const Duration(seconds: 1),
      );
      final stuckA = Completer<String?>();
      slot.start('k', () => stuckA.future);
      await tester.pump(const Duration(seconds: 2));
      expect(slot.pending('k'), isNull);

      final stuckB = Completer<String?>();
      slot.start('k', () => stuckB.future);
      // A 迟到落定：修复前其回调无条件 remove+cancel，误杀 B 的定时器。
      stuckA.complete('stale');
      await tester.idle();
      expect(slot.take('k'), isNull);

      // B 的超时必须照常触发（修复前 B 的定时器已被 A 取消，永不超时）。
      await tester.pump(const Duration(seconds: 2));
      expect(slot.pending('k'), isNull);
      expect(await slot.consume('k', () async => 'fallback'), 'fallback');

      stuckB.complete('b-late');
      await tester.idle();
      expect(tester.takeException(), isNull);
      slot.debugClear();
    });
  });

  group('HttpStatsService byModule 派生缓存（M4）', () {
    test('overview 回落兜底时派生缓存失效，不返回上一次成功的旧模块列表', () async {
      var online = true;
      final client = MockClient((request) async {
        if (!online) return http.Response('', 500);
        if (request.url.path.endsWith('/stats/overview')) {
          return http.Response(
            jsonEncode({
              'totalAnswered': 120,
              'accuracy': 75.0,
              'today': {'answered': 10, 'correct': 8},
              'byModule': [
                {'module': 'VLAN', 'answered': 40, 'accuracy': 80.0},
              ],
            }),
            200,
          );
        }
        return http.Response(jsonEncode({'items': [], 'total': 0}), 200);
      });
      final service = HttpStatsService(
        client: client,
        baseUrl: 'http://stats.test',
        fallback: _ZeroStats(),
      );

      expect((await service.getOverview()).answeredTotal, 120);
      expect((await service.getByModule()).single.module, 'VLAN');

      online = false;
      expect((await service.getOverview()).answeredTotal, 0);
      // 修复前：_byModuleCache 未失效，仍返回旧 VLAN；修复后随兜底一致。
      expect((await service.getByModule()).single.module, 'MOCK');
      client.close();
    });

    test('成功刷新：派生缓存随新 overview 更新（成功路径本就新鲜，契约锁定）', () async {
      var module = 'VLAN';
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/stats/overview')) {
          return http.Response(
            jsonEncode({
              'totalAnswered': 1,
              'accuracy': 0,
              'today': <String, dynamic>{},
              'byModule': [
                {'module': module, 'answered': 1, 'accuracy': 0},
              ],
            }),
            200,
          );
        }
        return http.Response(jsonEncode({'items': [], 'total': 0}), 200);
      });
      final service = HttpStatsService(
        client: client,
        baseUrl: 'http://stats.test',
      );

      await service.getOverview();
      expect((await service.getByModule()).single.module, 'VLAN');
      module = 'OSPF';
      await service.getOverview();
      // getOverview 在完成前已刷新派生缓存：重试 / 刷新不会拿到旧模块。
      expect((await service.getByModule()).single.module, 'OSPF');
      client.close();
    });
  });

  group('StatsPage 重试健壮性（M5 / M6 / L6）', () {
    testWidgets('M5 页面销毁后触发重试：不再 setState after dispose', (tester) async {
      final stats = _StatsStub(overviewError: Exception('offline'));
      await tester.pumpWidget(_host(StatsPage(statsService: stats)));
      await tester.pumpAndSettle();
      expect(find.text('统计加载失败'), findsOneWidget);

      final retry = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text('重试'),
          matching: find.byType(OutlinedButton),
        ),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      // 修复前：_load 的首个 setState 无 mounted 守卫，此处抛
      // setState() called after dispose()（未处理异步错误）。
      retry.onPressed!();
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('M6 成功后失败重试：错误态且不再持有旧载荷（契约锁定）', (tester) async {
      final stats = _StatsStub(
        overview: _overview,
        byModule: _byModule,
        daily: _daily,
      );
      await tester.pumpWidget(_host(StatsPage(statsService: stats)));
      await tester.pumpAndSettle();
      expect(find.text('120 题'), findsOneWidget);
      expect(find.text('已答 40 题'), findsOneWidget);

      stats.overviewError = Exception('offline');
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();

      expect(find.text('统计加载失败'), findsOneWidget);
      expect(find.text('120 题'), findsNothing);
      expect(find.text('已答 40 题'), findsNothing);
      expect(find.text('按模块'), findsNothing);
      expect(find.text('每日记录'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('L6 overview/daily 成功但 getByModule 单独失败：仍显示诚实错误态', (tester) async {
      final stats = _StatsStub(
        overview: _overview,
        daily: _daily,
        byModuleError: Exception('by-module down'),
      );
      await tester.pumpWidget(_host(StatsPage(statsService: stats)));
      await tester.pumpAndSettle();

      expect(find.text('统计加载失败'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      expect(find.text('累计答题'), findsNothing);
      expect(stats.overviewCalls, 1);
      expect(stats.dailyCalls, 1);
      expect(stats.byModuleCalls, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('L6 getDaily 单独失败（.wait 单路拒绝）：仍显示诚实错误态', (tester) async {
      final stats = _StatsStub(
        overview: _overview,
        byModule: _byModule,
        dailyError: Exception('daily down'),
      );
      await tester.pumpWidget(_host(StatsPage(statsService: stats)));
      await tester.pumpAndSettle();

      expect(find.text('统计加载失败'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      expect(find.text('累计答题'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('RecordPaperPreload null 不毒化试卷页（M7）', () {
    testWidgets('预取返回 null：试卷页回落自行拉取并显示重试态', (tester) async {
      final service = _PaperStub(paper: null);
      RecordPaperPreload.start(sessionId: 'sess-1', service: service);
      await tester.idle();
      expect(service.paperCalls, 1);
      // null 不落槽：take 拿不到任何「就绪结果」。
      expect(RecordPaperPreload.take('sess-1'), isNull);

      await tester.pumpWidget(
        _host(
          AnswerRecordPaperPage(
            args: <String, Object?>{
              'record': _record,
              'sessionId': 'sess-1',
            },
            practiceService: service,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('试卷加载失败'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      expect(find.text('暂无试卷'), findsNothing);
      // 消费回落触发了第二次真实拉取（页面自身加载路径）。
      expect(service.paperCalls, 2);
      expect(tester.takeException(), isNull);
    });
  });
}
