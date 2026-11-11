/// 认证服务抽象接口（规格文档第 4 章 §4.7.1）。
///
/// 服务的页面：登录/注册页、G-03 AccountSheet、设置页。
/// 现在的实现是 Mock（演示登录：点登录进首页，不发任何请求）；以后真实实现走
/// `POST /auth/register`、`/auth/login`、`/auth/refresh`、`/auth/logout`、
/// `GET /auth/me`、`PATCH /auth/me`、`POST /auth/password`、
/// `POST /auth/recover`、`GET /auth/devices`。
library;

import '../../models/auth.dart';
import '../../models/user.dart';

abstract class AuthService {
  /// 当前用户。未登录返回 null。调用时机：进首页（H-04 头像态）、打开 G-03、进设置页时。
  /// Mock：固定返回 null（未登录态）；演示登录成功后返回 {username: 'Max', nickname: 'Max'} 的本地对象。
  /// 以后：GET /auth/me（本地 Token 有效时）。
  Future<User?> getCurrentUser();

  /// 演示登录。调用时机：登录页点“登录”时。
  /// Mock：只做第 2 章 §14.6 的本地格式校验（用户名 4–20 位字母数字下划线；密码 8–32 位含字母数字），
  /// 通过后直接进首页，不发任何网络请求。这是 M0 空壳已有的行为，保持原样。
  /// 以后：POST /auth/login，返回双 Token（access 15 分钟 + refresh 30 天），Token 只存 TokenStore。
  Future<LoginResult> login({
    required String username,
    required String password,
  });

  /// 注册。Mock：与登录相同的本地演示流程。以后：POST /auth/register，注册成功发 12 词恢复码（v3.1 D17）。
  Future<RegisterResult> register({
    required String username,
    required String password,
    required String nickname,
  });

  /// 登出。Mock：清本地演示态。以后：POST /auth/logout（撤销当前设备 sid），清 Token。
  Future<void> logout();

  /// 设备列表（G-03 内“设备列表”项）。Mock：返回本机 1 条。以后：GET /auth/devices。
  Future<List<Device>> getDevices();

  /// 恢复码（G-03 内“恢复码”项）。Mock：返回 null（显示“未设置”）。以后：POST /auth/recover。
  Future<String?> getRecoveryCodeHint();
}
