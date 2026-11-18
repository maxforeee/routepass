/// F31 (P2-1)：双 Token 迁入 flutter_secure_storage 的行为测试。
///
/// 覆盖：
/// - 旧版明文 kv `auth.session` 在恢复时迁入加密存储并删除明文（老用户不被登出）；
/// - 恢复优先读加密存储（重启后无需明文）；
/// - 登出 / refresh 401 会话失效都清空加密存储（无孤儿 Token）；
/// - 刷新轮换后的新 Token 只落加密存储；
/// - 损坏会话（明文 / 加密）按未登录处理并清理；
/// - 加密与明文并存时加密优先，明文残留被清除；
/// - 迁移写入失败保留明文下次重试，本次会话照常可用。
///
/// 全部用 InMemorySecureSessionStore / 失败假实现，不碰真实平台通道。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:routepass/core/kv_store.dart';
import 'package:routepass/models/auth.dart';
import 'package:routepass/models/user.dart';
import 'package:routepass/services/auth/auth_service.dart';
import 'package:routepass/services/auth/secure_session_store.dart';

const String _phone = '13800138000';

AuthSession _session({
  String access = 'access-1',
  String refresh = 'refresh-1',
}) {
  return AuthSession(
    accessToken: access,
    refreshToken: refresh,
    tokenType: 'Bearer',
    accessExpiresAt: DateTime.now().add(const Duration(hours: 1)),
    user: User(id: '7', username: _phone, nickname: 'Max'),
  );
}

http.Response _jsonResponse(int statusCode, Object body) {
  return http.Response(
    jsonEncode(body),
    statusCode,
    headers: const <String, String>{
      'content-type': 'application/json; charset=utf-8',
    },
  );
}

/// 写入永远失败的加密存储：模拟 Keystore 异常（如备份恢复后密钥失效）。
class _FailingWriteSecureStore implements SecureSessionStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async {
    throw Exception('keystore unavailable');
  }

  @override
  Future<void> delete() async {
    value = null;
  }
}

void main() {
  test('legacy plaintext session migrates into secure storage on restore', () async {
    final kv = InMemoryKvStore();
    final secure = InMemorySecureSessionStore();
    kv.setString(KvStore.keyAuthSession, jsonEncode(_session().toJson()));
    final auth = HttpAuthService(
      client: MockClient((_) async => _jsonResponse(404, <String, Object?>{})),
      kvStore: kv,
      secureStore: secure,
      baseUrl: 'http://test',
    );

    final user = await auth.getCurrentUser();

    // 老用户升级后仍是登录态，Token 原样保留。
    expect(user?.username, _phone);
    expect(auth.cachedAccessToken, 'access-1');
    final migrated = await secure.read();
    expect(migrated, isNotNull);
    expect(migrated, contains('access-1'));
    expect(migrated, contains('refresh-1'));
    // 明文副本必须删除。
    expect(kv.getString(KvStore.keyAuthSession), isNull);

    // 再次“重启”（新实例、同一存储）：直接从加密存储恢复，不再依赖明文。
    final restarted = HttpAuthService(
      client: MockClient((_) async => _jsonResponse(404, <String, Object?>{})),
      kvStore: kv,
      secureStore: secure,
      baseUrl: 'http://test',
    );
    expect((await restarted.getCurrentUser())?.username, _phone);
    expect(restarted.cachedAccessToken, 'access-1');
  });

  test('restore reads the session from secure storage without any plaintext', () async {
    final kv = InMemoryKvStore();
    final secure = InMemorySecureSessionStore();
    await secure.write(jsonEncode(_session().toJson()));
    final auth = HttpAuthService(
      client: MockClient((_) async => _jsonResponse(404, <String, Object?>{})),
      kvStore: kv,
      secureStore: secure,
      baseUrl: 'http://test',
    );

    expect((await auth.getCurrentUser())?.username, _phone);
    expect(auth.cachedAccessToken, 'access-1');
    expect(kv.getString(KvStore.keyAuthSession), isNull);
  });

  test('logout after migration clears secure storage and kv', () async {
    final kv = InMemoryKvStore();
    final secure = InMemorySecureSessionStore();
    kv.setString(KvStore.keyAuthSession, jsonEncode(_session().toJson()));
    String? logoutAuthorization;
    final auth = HttpAuthService(
      client: MockClient((request) async {
        if (request.url.path == '/api/v1/auth/logout') {
          logoutAuthorization = request.headers['authorization'];
          return _jsonResponse(200, <String, Object?>{'success': true});
        }
        return _jsonResponse(404, <String, Object?>{});
      }),
      kvStore: kv,
      secureStore: secure,
      baseUrl: 'http://test',
    );
    expect(await auth.getCurrentUser(), isNotNull);

    await auth.logout();

    expect(logoutAuthorization, 'Bearer access-1');
    expect(await secure.read(), isNull);
    expect(kv.getString(KvStore.keyAuthSession), isNull);
    expect(await auth.getCurrentUser(), isNull);
  });

  test('refresh 401 expiry clears secure storage (no orphaned tokens)', () async {
    final kv = InMemoryKvStore();
    final secure = InMemorySecureSessionStore();
    await secure.write(jsonEncode(_session().toJson()));
    var expired = false;
    final auth = HttpAuthService(
      client: MockClient(
        (_) async => _jsonResponse(401, <String, Object?>{'detail': '登录会话已失效'}),
      ),
      kvStore: kv,
      secureStore: secure,
      baseUrl: 'http://test',
    );
    auth.onSessionExpired = () => expired = true;

    final token = await auth.accessToken(forceRefresh: true);

    expect(token, isNull);
    expect(expired, isTrue);
    expect(await secure.read(), isNull);
    expect(kv.getString(KvStore.keyAuthSession), isNull);
  });

  test('refresh rotation persists the rotated tokens to secure storage only', () async {
    final kv = InMemoryKvStore();
    final secure = InMemorySecureSessionStore();
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/auth/login') {
        return _jsonResponse(200, <String, Object?>{
          'accessToken': 'access-1',
          'refreshToken': 'refresh-1',
          'tokenType': 'Bearer',
          'expiresIn': 30,
          'user': <String, Object?>{'id': 7, 'nickname': 'Max'},
        });
      }
      if (request.url.path == '/api/v1/auth/refresh') {
        return _jsonResponse(200, <String, Object?>{
          'accessToken': 'access-2',
          'refreshToken': 'refresh-2',
          'tokenType': 'Bearer',
          'expiresIn': 900,
        });
      }
      return _jsonResponse(404, <String, Object?>{});
    });
    final auth = HttpAuthService(
      client: client,
      kvStore: kv,
      secureStore: secure,
      baseUrl: 'http://test',
    );
    await auth.login(phone: _phone, password: 'secret123');

    final token = await auth.accessToken();

    expect(token, 'access-2');
    final stored = await secure.read();
    expect(stored, contains('access-2'));
    expect(stored, contains('refresh-2'));
    expect(stored, isNot(contains('refresh-1')));
    expect(kv.getString(KvStore.keyAuthSession), isNull);
  });

  test('corrupt legacy plaintext is dropped without a session', () async {
    final kv = InMemoryKvStore();
    final secure = InMemorySecureSessionStore();
    kv.setString(KvStore.keyAuthSession, '{definitely not json');
    final auth = HttpAuthService(
      client: MockClient((_) async => _jsonResponse(404, <String, Object?>{})),
      kvStore: kv,
      secureStore: secure,
      baseUrl: 'http://test',
    );

    expect(await auth.getCurrentUser(), isNull);
    expect(kv.getString(KvStore.keyAuthSession), isNull);
    expect(await secure.read(), isNull);
  });

  test('corrupt secure value falls back to legacy migration', () async {
    final kv = InMemoryKvStore();
    final secure = InMemorySecureSessionStore();
    await secure.write('garbage');
    kv.setString(KvStore.keyAuthSession, jsonEncode(_session().toJson()));
    final auth = HttpAuthService(
      client: MockClient((_) async => _jsonResponse(404, <String, Object?>{})),
      kvStore: kv,
      secureStore: secure,
      baseUrl: 'http://test',
    );

    expect((await auth.getCurrentUser())?.username, _phone);
    expect(await secure.read(), contains('access-1'));
    expect(kv.getString(KvStore.keyAuthSession), isNull);
  });

  test('secure session wins over a leftover plaintext copy, which is removed', () async {
    final kv = InMemoryKvStore();
    final secure = InMemorySecureSessionStore();
    await secure.write(jsonEncode(_session(access: 'access-2').toJson()));
    kv.setString(KvStore.keyAuthSession, jsonEncode(_session().toJson()));
    final auth = HttpAuthService(
      client: MockClient((_) async => _jsonResponse(404, <String, Object?>{})),
      kvStore: kv,
      secureStore: secure,
      baseUrl: 'http://test',
    );

    expect(await auth.getCurrentUser(), isNotNull);
    expect(auth.cachedAccessToken, 'access-2');
    expect(kv.getString(KvStore.keyAuthSession), isNull);
  });

  test('failed migration write keeps plaintext for retry and stays logged in', () async {
    final kv = InMemoryKvStore();
    final secure = _FailingWriteSecureStore();
    kv.setString(KvStore.keyAuthSession, jsonEncode(_session().toJson()));
    final auth = HttpAuthService(
      client: MockClient((_) async => _jsonResponse(404, <String, Object?>{})),
      kvStore: kv,
      secureStore: secure,
      baseUrl: 'http://test',
    );

    // Keystore 写入失败不登出：本次会话可用，明文保留待下次启动重试。
    expect((await auth.getCurrentUser())?.username, _phone);
    expect(kv.getString(KvStore.keyAuthSession), isNotNull);
  });
}