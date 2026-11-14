/// 认证服务抽象接口（规格文档第 4 章 §4.7.1；F19 接入真实后端）。
///
/// 服务的页面：登录/注册页、G-03 AccountSheet、设置页。
/// Mock 实现是本地演示登录（不发请求）；生产实现 [HttpAuthService] 走
/// `POST /api/v1/auth/login`、`/auth/refresh`、`/auth/logout` 等真实契约。
///
/// Token 生命周期只由本接口管理：UI 与 HTTP 服务都不自己存 Token。
library;

import '../../models/auth.dart';
import '../../models/user.dart';

abstract class AuthService {
  /// 会话失效回调（refreshToken 也 401 时触发）。main.dart 接到登录页；
  /// 默认 null（测试与 Mock 不需要强制跳转）。
  void Function()? onSessionExpired;

  /// 当前用户。未登录返回 null。调用时机：启动页、首页头像、G-03、设置页。
  Future<User?> getCurrentUser();

  /// 登录（v1.2：登录即注册）。调用时机：登录页点“login”时。
  /// 未知手机号由服务端创建账号并随结果下发一次性恢复码。
  Future<LoginResult> login({required String phone, required String password});

  /// 注册（保留接口；真实后端登录即注册，本方法目前只被 Mock 使用）。
  Future<RegisterResult> register({
    required String phone,
    required String password,
    required String nickname,
  });

  /// 登出：撤销服务端会话 + 清本地 Token。
  Future<void> logout();

  /// 设备列表（G-03 内“设备列表”项）。
  Future<List<Device>> getDevices();

  /// 本机设备信息（个人中心“设备”区）。后端没有设备列表端点，
  /// 这里只返回登录时上送的这台设备；未登录时也返回本机标识。
  Future<LocalDeviceInfo?> currentDevice() async => null;

  /// 恢复码提示（G-03 内“恢复码”项）。
  Future<String?> getRecoveryCodeHint();

  /// 取 accessToken 供已鉴权请求使用；快过期时先自动刷新。
  /// 未登录（或刷新被服务端拒绝）返回 null。
  Future<String?> accessToken({bool forceRefresh = false});

  /// 主动刷新一次 accessToken。成功返回 true；refreshToken 被服务端拒绝
  /// （401）时清本地会话并触发 [onSessionExpired]，返回 false。
  Future<bool> refreshAccessToken();

  /// 同步取缓存中的 accessToken（供 HTTP 服务的 `tokenProvider` 钩子；
  /// 不做刷新，刷新由 [AuthHttpClient] 处理）。
  String? get cachedAccessToken;

  /// 清本地会话（不调服务端）。
  void clearSession();
}
