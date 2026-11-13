/// AuthService 的 Mock 实现（规格文档第 4 章 §4.7.1）。
///
/// 演示登录即注册：本地校验 11 位手机号与密码（8–32 位含字母数字），
/// 新手机号自动创建本地账号，已有手机号直接登录，不发任何网络请求。
library;

import '../../models/auth.dart';
import '../../models/user.dart';
import '../base/auth_service.dart';

class MockAuthService implements AuthService {
  User? _currentUser;
  final _users = <String, User>{};

  static final RegExp _phonePattern = RegExp(r'^1[3-9]\d{9}$');

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
    if (!_phonePattern.hasMatch(username) || !_validPassword(password)) {
      return LoginResult(success: false, message: '手机号码或密码格式不正确');
    }
    _currentUser = _users.putIfAbsent(
      username,
      () => User(id: 'local', username: username, nickname: 'Max'),
    );
    return LoginResult(success: true, user: _currentUser);
  }

  @override
  Future<RegisterResult> register({
    required String username,
    required String password,
    required String nickname,
  }) async {
    if (!_phonePattern.hasMatch(username) ||
        !_validPassword(password) ||
        nickname.isEmpty) {
      return RegisterResult(success: false, message: '手机号码、密码或昵称格式不正确');
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
