/// F45：统计页刷新（内容态）回归测试。
///
/// 覆盖：
/// - 成功态点 AppBar 刷新 → 失败落入诚实错误态，旧内容清空
///   （F30 M6 场景自此可达）；
/// - 错误态点重试 → 成功后内容回归；
/// - 下拉刷新驱动同一 _load（新数据到达）；错误态同样可下拉刷新；
/// - 在途重入守卫：首次加载在途时刷新按钮禁用；刷新在途时第二次
///   刷新被忽略，三路调用计数不翻倍；
/// - 刷新在途保留旧内容，不闪骨架。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/core/theme.dart';
import 'package:routepass/models/stats.dart';
import 'package:routepass/pages/bank/stats_page.dart';
import 'package:routepass/services/bank/stats_service.dart';
import 'package:routepass/widgets/loading_skeleton.dart';

// ---------------------------------------------------------------------------
// 可控替身（同 f30_ocr_rerun_fixes_test.dart 的 _StatsStub：字段可中途切换）
// ---------------------------------------------------------------------------

/// overview 路径可注入错误 / gate（本文件只用 overview 注入失败）。
class _StatsStub implements StatsService {
  _StatsStub({
    this.overview,
    this.byModule = const <ModuleStat>[],
    this.daily = const <DailyStats>[],
    this.overviewError,
  });

  StatsOverview? overview;
  List<ModuleStat> byModule;
  List<DailyStats> daily;
  Object? overviewError;
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
    return _wait(byModule, null);
  }

  @override
  Future<List<DailyStats>> getDaily() {
    dailyCalls++;
    return _wait(daily, null);
  }
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
  DailyStats(
    stat_date: '2026-11-16',
    answered: 10,
    correct: 8,
    duration_sec: 600,
  ),
];

Widget _host(Widget child) => MaterialApp(theme: AppTheme.light, home: child);

/// AppBar 刷新按钮（Tooltip 在 IconButton 内部，向上找 IconButton 本体）。
final Finder _refreshButton = find.ancestor(
  of: find.byTooltip('刷新'),
  matching: find.byType(IconButton),
);

/// 内容 / 错误态里唯一挂在 RefreshIndicator 下的 ListView
/// （骨架 ListView 不在 RefreshIndicator 内，不会误匹配）。
final Finder _refreshableList = find.descendant(
  of: find.byType(RefreshIndicator),
  matching: find.byType(ListView),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StatsPage 刷新（F45）', () {
    testWidgets('成功态点刷新后失败：诚实错误态 + 重试，旧内容清空（F30 M6 场景）', (tester) async {
      final stats = _StatsStub(
        overview: _overview,
        byModule: _byModule,
        daily: _daily,
      );
      await tester.pumpWidget(_host(StatsPage(statsService: stats)));
      await tester.pumpAndSettle();
      expect(find.text('累计答题'), findsOneWidget);
      expect(find.text('120 题'), findsOneWidget);
      expect(tester.widget<IconButton>(_refreshButton).onPressed, isNotNull);

      stats.overviewError = Exception('offline');
      await tester.tap(find.byTooltip('刷新'));
      await tester.pumpAndSettle();

      expect(find.text('统计加载失败'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      expect(find.text('累计答题'), findsNothing);
      expect(find.text('120 题'), findsNothing);
      expect(stats.overviewCalls, 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('错误态点重试后成功：内容回归', (tester) async {
      final stats = _StatsStub(overviewError: Exception('offline'));
      await tester.pumpWidget(_host(StatsPage(statsService: stats)));
      await tester.pumpAndSettle();
      expect(find.text('统计加载失败'), findsOneWidget);

      stats.overviewError = null;
      stats.overview = _overview;
      stats.byModule = _byModule;
      stats.daily = _daily;
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();

      expect(find.text('累计答题'), findsOneWidget);
      expect(find.text('120 题'), findsOneWidget);
      expect(find.text('统计加载失败'), findsNothing);
      expect(stats.overviewCalls, 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('下拉刷新驱动同一 _load：新数据到达', (tester) async {
      final stats = _StatsStub(
        overview: _overview,
        byModule: _byModule,
        daily: _daily,
      );
      await tester.pumpWidget(_host(StatsPage(statsService: stats)));
      await tester.pumpAndSettle();
      expect(find.text('120 题'), findsOneWidget);

      stats.overview = const StatsOverview(
        answeredTotal: 240,
        correctRate: 0.5,
        streakDays: 3,
        todayAnswered: 20,
        todayCorrect: 10,
      );
      await tester.fling(_refreshableList, const Offset(0, 300), 1000);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('240 题'), findsOneWidget);
      expect(find.text('120 题'), findsNothing);
      expect(stats.overviewCalls, 2);
      expect(stats.dailyCalls, 2);
      expect(stats.byModuleCalls, 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('错误态也可下拉刷新：恢复成功后内容回归', (tester) async {
      final stats = _StatsStub(overviewError: Exception('offline'));
      await tester.pumpWidget(_host(StatsPage(statsService: stats)));
      await tester.pumpAndSettle();
      expect(find.text('统计加载失败'), findsOneWidget);

      stats.overviewError = null;
      stats.overview = _overview;
      stats.byModule = _byModule;
      stats.daily = _daily;
      await tester.fling(_refreshableList, const Offset(0, 300), 1000);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('累计答题'), findsOneWidget);
      expect(find.text('120 题'), findsOneWidget);
      expect(find.text('统计加载失败'), findsNothing);
      expect(stats.overviewCalls, 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('在途重入守卫：加载在途时刷新被禁用 / 忽略，计数不翻倍', (tester) async {
      final stats = _StatsStub(
        overview: _overview,
        byModule: _byModule,
        daily: _daily,
      );
      stats.gate = Completer<void>();
      await tester.pumpWidget(_host(StatsPage(statsService: stats)));
      await tester.pump();

      // 首次加载在途：刷新按钮禁用，点按不产生第二次加载。
      expect(tester.widget<IconButton>(_refreshButton).onPressed, isNull);
      await tester.tap(find.byTooltip('刷新'));
      await tester.pump();
      expect(stats.overviewCalls, 1);
      expect(stats.dailyCalls, 1);

      stats.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('120 题'), findsOneWidget);
      expect(stats.overviewCalls, 1);
      expect(stats.dailyCalls, 1);
      expect(stats.byModuleCalls, 1);

      // 刷新在途：按钮再次禁用，第二次点按被忽略，三路计数不翻倍。
      stats.gate = Completer<void>();
      await tester.tap(find.byTooltip('刷新'));
      await tester.pump();
      expect(stats.overviewCalls, 2);
      expect(stats.dailyCalls, 2);
      expect(tester.widget<IconButton>(_refreshButton).onPressed, isNull);
      await tester.tap(find.byTooltip('刷新'));
      await tester.pump();
      expect(stats.overviewCalls, 2);
      expect(stats.dailyCalls, 2);

      stats.gate!.complete();
      await tester.pumpAndSettle();
      expect(stats.overviewCalls, 2);
      expect(stats.dailyCalls, 2);
      expect(stats.byModuleCalls, 2);
      expect(tester.widget<IconButton>(_refreshButton).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('刷新在途保留旧内容：不闪骨架', (tester) async {
      final stats = _StatsStub(
        overview: _overview,
        byModule: _byModule,
        daily: _daily,
      );
      await tester.pumpWidget(_host(StatsPage(statsService: stats)));
      await tester.pumpAndSettle();
      // 骨架退出定时器（150ms）落定后骨架移出树。
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('120 题'), findsOneWidget);
      expect(find.byType(LoadingSkeleton), findsNothing);

      stats.gate = Completer<void>();
      stats.overview = const StatsOverview(
        answeredTotal: 360,
        correctRate: 0.6,
        streakDays: 4,
        todayAnswered: 30,
        todayCorrect: 18,
      );
      await tester.tap(find.byTooltip('刷新'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 刷新在途：旧内容仍在，骨架未重新挂载。
      expect(find.text('累计答题'), findsOneWidget);
      expect(find.text('120 题'), findsOneWidget);
      expect(find.byType(LoadingSkeleton), findsNothing);

      stats.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('360 题'), findsOneWidget);
      expect(find.text('120 题'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
