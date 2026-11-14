import 'dart:async';

import 'package:routepass/models/sync.dart';
import 'package:routepass/services/bank/bank_sync_service.dart';
import 'package:routepass/services/connectivity_service.dart';

/// 可控的网络状态（widget 测试不加载 connectivity_plus 平台插件）。
class FakeConnectivityService implements ConnectivityService {
  FakeConnectivityService({this.online = false});

  bool online;
  final _controller = StreamController<bool>.broadcast();

  @override
  Future<bool> isOnline() async => online;

  @override
  Stream<bool> get onChanged => _controller.stream;

  /// 模拟网络切换：更新状态并通知监听者。
  void setOnline(bool value) {
    online = value;
    _controller.add(value);
  }

  Future<void> dispose() => _controller.close();
}

/// 可控的同步服务：给定状态 / 服务器时间 / 同步结果。
class FakeSyncService implements SyncService {
  FakeSyncService({
    this.status = const SyncStatus(pendingCount: 0, state: 'local_only'),
    this.cached,
    this.manualResult = const ManualSyncResult(
      ok: true,
      message: '已是最新',
      state: 'synced',
    ),
  });

  SyncStatus status;
  SyncStatus? cached;
  ManualSyncResult manualResult;

  @override
  SyncStatus? get cachedStatus => cached;

  @override
  Future<SyncStatus> getSyncStatus() async => status;

  @override
  Future<PushResult> pushPendingOps() async =>
      const PushResult(pushedCount: 0, failedCount: 0);

  @override
  Future<PullResult> pullIncremental({int? since}) async =>
      const PullResult(pulledCount: 0);

  @override
  Future<ManualSyncResult> syncNow() async => manualResult;
}
