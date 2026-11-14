/// 网络连通性检测（F19：首页同步模式条）。
///
/// 只回答“本机有没有可用的网络接口”，不探测后端：
/// - 在线：任一接口不是 [ConnectivityResult.none]（含 VPN / 有线 / 蜂窝）；
/// - “网络在线但服务器不可达”由同步服务自己判断（`/sync/pull` 失败），
///   同步模式条只在两者都成立时才显示“同步模式”。
library;

import 'package:connectivity_plus/connectivity_plus.dart';

abstract class ConnectivityService {
  /// 当前是否有网络。检测失败按离线处理（宁可不报“同步模式”）。
  Future<bool> isOnline();

  /// 网络状态变化（true = 在线）。用于同步条实时刷新，不是只查一次。
  Stream<bool> get onChanged;
}

/// connectivity_plus 实现（Android / iOS / Linux）。
class PlatformConnectivityService implements ConnectivityService {
  PlatformConnectivityService({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  static bool _anyOnline(List<ConnectivityResult> results) {
    return results.any((result) => result != ConnectivityResult.none);
  }

  @override
  Future<bool> isOnline() async {
    try {
      return _anyOnline(await _connectivity.checkConnectivity());
    } catch (_) {
      // 平台通道不可用（如桌面单元测试）按离线处理。
      return false;
    }
  }

  @override
  Stream<bool> get onChanged => _connectivity.onConnectivityChanged
      .map(_anyOnline)
      .handleError((Object _) {})
      .distinct();
}
