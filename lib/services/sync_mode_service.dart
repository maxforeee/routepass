/// 首页同步模式（F19：首页底部同步条）。
///
/// 把两件事合成一个状态：
/// - 本机网络（[ConnectivityService]）；
/// - 登录态 + 服务器是否真的能同步（[SyncService.getSyncStatus]，
///   内部请求 `GET /api/v1/sync/pull`）。
///
/// 只有“有网络 + 已登录 + 同步接口返回成功”才显示“同步模式”；
/// 其余一律“本地模式”。不编造服务器时间：服务器时间只在同步接口
/// 成功返回时才透出。
library;

import '../models/sync.dart';
import 'bank/bank_sync_service.dart';
import 'connectivity_service.dart';

enum SyncMode { local, sync }

/// 一次同步模式判定的完整快照（同步条与诊断 sheet 共用）。
class SyncModeSnapshot {
  const SyncModeSnapshot({
    required this.networkOnline,
    required this.loggedIn,
    required this.serverReachable,
    this.status,
    this.serverTime,
  });

  /// 本机有无网络。
  final bool networkOnline;

  /// 是否已登录（未登录没有可同步的账号）。
  final bool loggedIn;

  /// 同步接口是否可用（网络在线 + 已登录 + `/sync/pull` 成功）。
  final bool serverReachable;

  /// 同步状态；离线时为本地缓存的最近一次状态。
  final SyncStatus? status;

  /// 服务器时间（ISO 字符串），仅同步接口成功返回时有值。
  final String? serverTime;

  SyncMode get mode => serverReachable ? SyncMode.sync : SyncMode.local;

  String get modeLabel => mode == SyncMode.sync ? '同步模式' : '本地模式';

  @override
  String toString() =>
      'SyncModeSnapshot($modeLabel, online: $networkOnline, '
      'loggedIn: $loggedIn, reachable: $serverReachable)';
}

class SyncModeService {
  SyncModeService({
    required this.connectivity,
    required this.syncService,
    required this.isLoggedIn,
  });

  final ConnectivityService connectivity;
  final SyncService syncService;
  final Future<bool> Function() isLoggedIn;

  /// 网络状态变化，供首页同步条实时刷新。
  Stream<bool> get onChanged => connectivity.onChanged;

  /// 读取当前真实状态。每次调用都会重新检查网络并重新请求同步接口，
  /// 不返回应用启动时的旧快照。
  Future<SyncModeSnapshot> load() async {
    final online = await _safeIsOnline();
    final loggedIn = await _safeIsLoggedIn();
    final cached = syncService.cachedStatus;

    if (!online) {
      return SyncModeSnapshot(
        networkOnline: false,
        loggedIn: loggedIn,
        serverReachable: false,
        status: cached,
      );
    }
    if (!loggedIn) {
      // 未登录：没有账号可同步，保持本地模式，不请求同步接口。
      return SyncModeSnapshot(
        networkOnline: true,
        loggedIn: false,
        serverReachable: false,
        status: cached,
      );
    }

    SyncStatus? status;
    var fresh = false;
    try {
      status = await syncService.getSyncStatus();
      fresh = true;
    } catch (_) {
      status = cached;
    }
    // 只有本次查询真的拿到了服务端 200 才算服务器可达。`offline`（网络失败）
    // 与 `local_only`（401 / 404 / 未登录）以及异常回落都按本地模式处理。
    final reachable =
        fresh &&
        status != null &&
        status.serverReachable &&
        (status.state == 'synced' || status.state == 'pending');
    return SyncModeSnapshot(
      networkOnline: true,
      loggedIn: true,
      serverReachable: reachable,
      status: status,
      serverTime: reachable ? status.serverTime : null,
    );
  }

  Future<bool> _safeIsOnline() async {
    try {
      return await connectivity.isOnline();
    } catch (_) {
      return false;
    }
  }

  Future<bool> _safeIsLoggedIn() async {
    try {
      return await isLoggedIn();
    } catch (_) {
      return false;
    }
  }
}
