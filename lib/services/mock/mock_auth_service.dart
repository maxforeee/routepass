/// AuthService 的 Mock 实现（规格文档第 4 章 §4.7.1）。
///
/// 演示登录：只做第 2 章 §14.6 的本地格式校验（用户名 4–20 位字母数字下划线；
/// 密码 8–32 位含字母数字），通过后直接进首页，不发任何网络请求。
/// 这是 M0 空壳已有的行为，保持原样。
library;

import '../../models/auth.dart';
import '../../models/user.dart';
import '../base/auth_service.dart';

class MockAuthService implements AuthService {
  User? _currentUser;

  static final RegExp _usernamePattern = RegExp(r'^[A-Za-z0-9_]{4,20}$');

  bool _validPassword(String password) {
    if (password.length < 8 || password.length > 32) return false;
    var hasLetter = false;
    var hasDigit = false;
    for (final c in password.codeUnits) {
      if ((c >= 65 && c <= 90) || (c >= 97 && c <= 122)) hasLetter = true;
      if (c >= 48 && c <= 57) hasDigit = true;
    }
    return hasLetter && hasDigit;
  }

  @override
  Future<User?> getCurrentUser() async {
    return _currentUser;
  }

  @override
  Future<LoginResult> login({
    required String username,
    required String password,
  }) async {
    if (!_usernamePattern.hasMatch(username) || !_validPassword(password)) {
      return LoginResult(success: false, message: '用户名或密码格式不正确');
    }
    _currentUser = User(id: 'local', username: username, nickname: 'Max');
    return LoginResult(success: true, user: _currentUser);
  }

  @override
  Future<RegisterResult> register({
    required String username,
    required String password,
    required String nickname,
  }) async {
    if (!_usernamePattern.hasMatch(username) ||
        !_validPassword(password) ||
        nickname.isEmpty) {
      return RegisterResult(success: false, message: '用户名、密码或昵称格式不正确');
    }
    _currentUser = User(id: 'local', username: username, nickname: nickname);
    // Mock 演示流程：recoveryCode 为 null（以后真实注册成功后发 12 词恢复码）。
    return RegisterResult(success: true, user: _currentUser);
  }

  @override
  Future<void> logout() async {
    _currentUser = null;
  }

  @override
  Future<List<Device>> getDevices() async {
    return <Device>[
      Device(
        id: 'local-device',
        name: '本机',
        last_active_at: DateTime.now().millisecondsSinceEpoch,
        is_current: true,
      ),
    ];
  }

  @override
  Future<String?> getRecoveryCodeHint() async {
    // Mock：返回 null（显示“未设置”）。
    return null;
  }
}
