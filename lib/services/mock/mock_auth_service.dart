/// AuthService 的 Mock 实现（规格文档第 4 章 §4.7.1）。
///
/// 演示登录即注册：本地校验 11 位手机号与密码（6–72 字节，与后端一致），
/// 新手机号自动创建本地账号，已有手机号直接登录，不发任何网络请求。
/// 没有真实 Token——[accessToken] 等生命周期方法返回空，生产走
/// [HttpAuthService]。
library;

import 'dart:convert';

import '../../models/auth.dart';
import '../../models/user.dart';
import '../base/auth_service.dart';

class MockAuthService extends AuthService {
  User? _currentUser;
  final _users = <String, User>{};

  static final RegExp _phonePattern = RegExp(r'^1[3-9]\d{9}$');

  bool _validPassword(String password) {
    final bytes = utf8.encode(password).length;
    return bytes >= 6 && bytes <= 72;
  }

  @override
  Future<User?> getCurrentUser() async {
    return _currentUser;
  }

  @override
  Future<LoginResult> login({
    required String phone,
    required String password,
  }) async {
    if (!_phonePattern.hasMatch(phone) || !_validPassword(password)) {
      return const LoginResult(success: false, message: '手机号或密码格式不正确');
    }
    _currentUser = _users.putIfAbsent(
      phone,
      () => User(id: 'local', username: phone, nickname: 'Max'),
    );
    return LoginResult(success: true, user: _currentUser);
  }

  @override
  Future<RegisterResult> register({
    required String phone,
    required String password,
    required String nickname,
  }) async {
    if (!_phonePattern.hasMatch(phone) ||
        !_validPassword(password) ||
        nickname.isEmpty) {
      return const RegisterResult(success: false, message: '手机号码、密码或昵称格式不正确');
    }
    _currentUser = User(id: 'local', username: phone, nickname: nickname);
    // Mock 演示流程：recoveryCode 为 null（真实注册成功后才有 12 词恢复码）。
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

  @override
  Future<String?> accessToken({bool forceRefresh = false}) async => null;

  @override
  Future<bool> refreshAccessToken() async => false;

  @override
  String? get cachedAccessToken => null;

  @override
  void clearSession() {
    _currentUser = null;
  }
}
