import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/core/service_locator.dart';
import 'package:routepass/models/sync.dart';
import 'package:routepass/pages/home/home_content.dart';
import 'package:routepass/services/sync_mode_service.dart';
import 'package:routepass/widgets/sync_detail_sheet.dart';

import 'support/fake_connectivity.dart';
import 'test_helpers.dart';

/// F19：首页同步模式条 —— 网络 + 服务器可达性驱动“本地模式 / 同步模式”，
/// 点开同步诊断看到实时状态。
void main() {
  setUp(() {
    initTestServices();
  });

  SyncModeService useMode({
    required FakeConnectivityService connectivity,
    required FakeSyncService sync,
    bool loggedIn = true,
  }) {
    final service = SyncModeService(
      connectivity: connectivity,
      syncService: sync,
      isLoggedIn: () async => loggedIn,
    );
    ServiceLocator.syncModeService = service;
    return service;
  }

  Future<void> pumpHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(home: HomeContentPage(onSelectTab: (_) {})),
    );
    await tester.pumpAndSettle();
  }

  group('SyncModeService', () {
    test('无网络 → 本地模式，且不请求同步接口', () async {
      final connectivity = FakeConnectivityService(online: false);
      final sync = FakeSyncService(
        cached: const SyncStatus(pendingCount: 2, state: 'offline'),
      );
      final service = useMode(connectivity: connectivity, sync: sync);

      final snapshot = await service.load();
      expect(snapshot.mode, SyncMode.local);
      expect(snapshot.modeLabel, '本地模式');
      expect(snapshot.networkOnline, isFalse);
      expect(snapshot.serverReachable, isFalse);
      // 离线时回落到本地缓存的最近一次状态。
      expect(snapshot.status?.pendingCount, 2);
      expect(snapshot.serverTime, isNull);
    });

    test('有网络但未登录 → 本地模式', () async {
      final connectivity = FakeConnectivityService(online: true);
      final sync = FakeSyncService(
        status: const SyncStatus(pendingCount: 0, state: 'synced'),
      );
      final service = useMode(
        connectivity: connectivity,
        sync: sync,
        loggedIn: false,
      );

      final snapshot = await service.load();
      expect(snapshot.mode, SyncMode.local);
      expect(snapshot.loggedIn, isFalse);
      expect(snapshot.serverReachable, isFalse);
    });

    test('有网络 + 已登录 + 同步接口成功 → 同步模式，透出服务器时间', () async {
      final connectivity = FakeConnectivityService(online: true);
      final sync = FakeSyncService(
        status: const SyncStatus(
          pendingCount: 0,
          state: 'synced',
          serverTime: '2026-11-14T10:00:00Z',
          serverReachable: true,
        ),
      );
      final service = useMode(connectivity: connectivity, sync: sync);

      final snapshot = await service.load();
      expect(snapshot.mode, SyncMode.sync);
      expect(snapshot.modeLabel, '同步模式');
      expect(snapshot.serverReachable, isTrue);
      expect(snapshot.serverTime, '2026-11-14T10:00:00Z');
    });

    test('有网络但服务器不可达（state=offline）→ 本地模式，不编造服务器时间', () async {
      final connectivity = FakeConnectivityService(online: true);
      final sync = FakeSyncService(
        status: const SyncStatus(
          pendingCount: 1,
          state: 'offline',
          serverTime: '2026-11-13T10:00:00Z',
        ),
      );
      final service = useMode(connectivity: connectivity, sync: sync);

      final snapshot = await service.load();
      expect(snapshot.mode, SyncMode.local);
      expect(snapshot.serverReachable, isFalse);
      expect(snapshot.serverTime, isNull);
    });

    test('401/404 回落（缓存是 synced 但本次未拿到响应）→ 本地模式', () async {
      final connectivity = FakeConnectivityService(online: true);
      final sync = FakeSyncService(
        // HttpSyncService 在 401/404 时沿用缓存 state，但 serverReachable=false。
        status: const SyncStatus(
          pendingCount: 0,
          state: 'synced',
          serverTime: '2026-11-13T10:00:00Z',
        ),
      );
      final service = useMode(connectivity: connectivity, sync: sync);

      final snapshot = await service.load();
      expect(snapshot.mode, SyncMode.local);
      expect(snapshot.serverReachable, isFalse);
      expect(snapshot.serverTime, isNull);
    });
  });

  group('首页同步条', () {
    testWidgets('离线：显示本地模式，点开诊断看到离线说明', (tester) async {
      final connectivity = FakeConnectivityService(online: false);
      useMode(
        connectivity: connectivity,
        sync: FakeSyncService(
          cached: SyncStatus(
            pendingCount: 2,
            lastSyncAt: DateTime(2026, 11, 13, 9, 30).millisecondsSinceEpoch,
            state: 'offline',
          ),
        ),
      );

      await pumpHome(tester);
      await tester.scrollUntilVisible(
        find.text('本地模式 · 未连接服务器'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('本地模式 · 未连接服务器'), findsOneWidget);
      expect(find.text('学习记录保存在本机，点击查看同步诊断'), findsOneWidget);

      await tester.tap(find.text('本地模式 · 未连接服务器'));
      await tester.pumpAndSettle();
      expect(find.text('同步诊断'), findsOneWidget);
      expect(find.text('当前离线，显示最近一次同步状态'), findsOneWidget);
      expect(find.text('离线'), findsOneWidget);
      expect(find.text('2 条'), findsOneWidget);
      // 离线时服务器时间不可用，不能拿上次的旧值冒充。
      expect(find.text('不可用'), findsOneWidget);
    });

    testWidgets('在线且服务器可达：显示同步模式与实时服务器信息', (tester) async {
      final connectivity = FakeConnectivityService(online: true);
      final sync = FakeSyncService(
        status: const SyncStatus(
          pendingCount: 3,
          state: 'synced',
          serverTime: '2026-11-14T10:00:00Z',
          serverReachable: true,
        ),
        manualResult: const ManualSyncResult(
          ok: true,
          message: '同步完成：拉取 2 条',
          pulledCount: 2,
          state: 'synced',
        ),
      );
      useMode(connectivity: connectivity, sync: sync);

      await pumpHome(tester);
      await tester.scrollUntilVisible(
        find.text('同步模式'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('同步模式'), findsOneWidget);
      expect(find.text('已连接服务器，学习记录自动同步'), findsOneWidget);

      await tester.tap(find.text('同步模式'));
      await tester.pumpAndSettle();
      expect(find.text('同步诊断'), findsOneWidget);
      // 当前模式 + 同步状态 + 待同步 + 服务器可达（首页同步条也在树里）。
      expect(find.text('同步模式'), findsWidgets);
      expect(find.text('已同步'), findsOneWidget);
      expect(find.text('3 条'), findsOneWidget);
      expect(find.text('可达'), findsOneWidget);
      expect(find.text('服务器时间'), findsOneWidget);
      expect(find.text('立即同步'), findsOneWidget);
    });

    testWidgets('诊断里的立即同步复用 SyncService.syncNow 并回报结果', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final connectivity = FakeConnectivityService(online: true);
      final sync = FakeSyncService(
        status: const SyncStatus(
          pendingCount: 0,
          state: 'synced',
          serverReachable: true,
        ),
        manualResult: const ManualSyncResult(
          ok: true,
          message: '本地无数据，已从服务器拉取 4 条',
          pulledCount: 4,
          state: 'synced',
        ),
      );
      final mode = SyncModeService(
        connectivity: connectivity,
        syncService: sync,
        isLoggedIn: () async => true,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SyncDetailSheet(syncService: sync, modeService: mode),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('立即同步'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('立即同步'));
      await tester.pumpAndSettle();
      expect(find.text('本地无数据，已从服务器拉取 4 条'), findsOneWidget);
    });

    testWidgets('诊断打开后刷新读取实时状态（不是启动时的快照）', (tester) async {
      final connectivity = FakeConnectivityService(online: true);
      final sync = FakeSyncService(
        status: const SyncStatus(
          pendingCount: 1,
          state: 'synced',
          serverReachable: true,
        ),
      );
      useMode(connectivity: connectivity, sync: sync);

      await pumpHome(tester);
      await tester.scrollUntilVisible(
        find.text('同步模式'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('同步模式'));
      await tester.pumpAndSettle();
      expect(find.text('1 条'), findsOneWidget);

      sync.status = const SyncStatus(
        pendingCount: 5,
        state: 'pending',
        serverReachable: true,
      );
      await tester.tap(find.byTooltip('刷新'));
      await tester.pumpAndSettle();
      expect(find.text('5 条'), findsOneWidget);
      expect(find.text('有待同步操作'), findsOneWidget);
    });

    testWidgets('网络恢复后同步条自动从本地模式切到同步模式', (tester) async {
      final connectivity = FakeConnectivityService(online: false);
      useMode(
        connectivity: connectivity,
        sync: FakeSyncService(
          status: const SyncStatus(
            pendingCount: 0,
            state: 'synced',
            serverReachable: true,
          ),
        ),
      );

      await pumpHome(tester);
      await tester.scrollUntilVisible(
        find.text('本地模式 · 未连接服务器'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('本地模式 · 未连接服务器'), findsOneWidget);

      connectivity.setOnline(true);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('同步模式'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('同步模式'), findsOneWidget);
    });

    testWidgets('在线但未登录：同步条显示本地模式 · 未登录', (tester) async {
      final connectivity = FakeConnectivityService(online: true);
      useMode(
        connectivity: connectivity,
        sync: FakeSyncService(
          status: const SyncStatus(
            pendingCount: 0,
            state: 'synced',
            serverReachable: true,
          ),
        ),
        loggedIn: false,
      );

      await pumpHome(tester);
      await tester.scrollUntilVisible(
        find.text('本地模式 · 未登录'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('本地模式 · 未登录'), findsOneWidget);
      expect(find.text('登录后可将学习记录同步到服务器'), findsOneWidget);
    });
  });
}
