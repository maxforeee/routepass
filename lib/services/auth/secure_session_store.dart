/// F31 (P2-1)：登录会话的加密持久化抽象。
///
/// 双 Token（accessToken + refreshToken）与用户信息整体存入
/// flutter_secure_storage（Android Keystore 加密），不再落明文
/// SharedPreferences。kv `auth.session` 只作为旧版本迁移来源读取，
/// 迁移成功后立即删除。
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 会话 JSON 的加密读写接口（生产 [FlutterSecureSessionStore]，
/// 测试 [InMemorySecureSessionStore]，单测不碰真实平台通道）。
abstract class SecureSessionStore {
  /// 读取会话 JSON；未登录返回 null。
  Future<String?> read();

  /// 写入会话 JSON（整体覆盖）。
  Future<void> write(String value);

  /// 删除会话（登出 / 会话失效）。
  Future<void> delete();
}

/// flutter_secure_storage 实现。键名沿用 `auth.session`，但背后的
/// 存储与 kv 完全不同（Keystore 加密的独立 SharedPreferences 文件）。
class FlutterSecureSessionStore implements SecureSessionStore {
  FlutterSecureSessionStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const String _key = 'auth.session';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String value) => _storage.write(key: _key, value: value);

  @override
  Future<void> delete() => _storage.delete(key: _key);
}

/// 基于内存的实现，用于测试（与 kv 的 InMemoryKvStore 同款约定）。
class InMemorySecureSessionStore implements SecureSessionStore {
  String? _value;

  @override
  Future<String?> read() async => _value;

  @override
  Future<void> write(String value) async {
    _value = value;
  }

  @override
  Future<void> delete() async {
    _value = null;
  }
}