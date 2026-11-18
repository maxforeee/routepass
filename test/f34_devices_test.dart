/// F34 run 3（F23 B3）：GET /auth/devices 真实设备列表。
///
/// 覆盖：
/// - HttpAuthService.getDevices 解析真实响应（服务端倒序原样保留 /
///   is_current / app_version / ISO → 毫秒）；服务端空列表是诚实空；
/// - 未登录不发请求；404 / 500 / 断网 / 坏形状都回落 Mock（空列表），
///   绝不抛给 UI、绝不编造设备；
/// - 401 刷新一次并重放（AuthHttpClient，与 S11 同一层）；
/// - 缺字段行整行丢弃；空 device_name 显示「未知设备」而不是空串；
/// - 个人中心渲染真实列表（名称 / 版本 / 最近活跃 / 当前设备标注）
///   与诚实空态「暂无其他设备」，不再出现「待接口」文案。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:routepass/core/kv_store.dart';
import 'package:routepass/core/theme.dart';
import 'package:routepass/models/auth.dart';
import 'package:routepass/models/sync.dart';
import 'package:routepass/models/user.dart';
import 'package:routepass/pages/base/profile_page.dart';
import 'package:routepass/router/app_router.dart';
import 'package:routepass/services/auth/auth_service.dart';
import 'package:routepass/services/auth/secure_session_store.dart';
import 'package:routepass/services/bank/bank_sync_service.dart';
import 'package:routepass/services/mock/mock_auth_service.dart';

const String _phone = '13800138000';
const String _base = 'http://test';

AuthSession _session() {
  return AuthSession(
    accessToken: 'access-1',
    refreshToken: 'refresh-1',
    tokenType: 'Bearer',
    accessExpiresAt: DateTime.now().add(const Duration(hours: 1)),
    user: User(id: '7', username: _phone, nickname: 'Max'),
  );
}

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: const <String, String>{
    'content-type': 'application/json; charset=utf-8',
  },
);

/// 后端 GET /auth/devices 的真实行形状（auth.py list_devices）。
Map<String, Object?> _deviceRow({
  String id = 'dev-1',
  String name = 'Honor Magic6',
  String version = '0.2.12',
  String active = '2026-11-17T09:06:00+08:00',
  bool current = true,
}) => <String, Object?>{
  'id': id,
  'device_name': name,
  'app_version': version,
  'created_at': '2026-11-10T16:00:00+08:00',
  'last_active_at': active,
  'is_current': current,
};

Future<HttpAuthService> _loggedInAuth({required http.Client client}) async {
  final secure = InMemorySecureSessionStore();
  await secure.write(jsonEncode(_session().toJson()));
  return HttpAuthService(
    client: client,
    kvStore: InMemoryKvStore(),
    secureStore: secure,
    baseUrl: _base,
    fallback: MockAuthService(),
  );
}

class _DevicesAuth extends MockAuthService {
  _DevicesAuth(this.devices);

  final List<Device> devices;

  @override
  Future<List<Device>> getDevices() async => devices;

  @override
  Future<LocalDeviceInfo?> currentDevice() async => const LocalDeviceInfo(
    deviceId: 'abcdefgh-1234-5678-9abc-def012345678',
    deviceModel: 'Pixel 9',
    appVersion: '0.2.12',
  );
}

class _FakeSync implements SyncService {
  static const SyncStatus _status = SyncStatus(
    pendingCount: 0,
    state: 'local_only',
  );

  @override
  SyncStatus? get cachedStatus => _status;

  @override
  Future<SyncStatus> getSyncStatus() async => _status;

  @override
  Future<ManualSyncResult> syncNow() async =>
      const ManualSyncResult(ok: true, message: '已是最新', state: 'synced');

  @override
  Future<PushResult> pushPendingOps() async =>
      const PushResult(pushedCount: 0, failedCount: 0);

  @override
  Future<PullResult> pullIncremental({int? since}) async =>
      const PullResult(pulledCount: 0);
}

Future<void> _pumpProfile(
  WidgetTester tester, {
  required MockAuthService auth,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: ProfilePage(authService: auth, syncService: _FakeSync()),
      onGenerateRoute: AppRouter.onGenerateRoute,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('HttpAuthService.getDevices (B3)', () {
    test('解析真实响应：倒序保留 / is_current / 版本 / ISO → 毫秒', () async {
      final paths = <String>[];
      final client = MockClient((request) async {
        paths.add(request.url.path);
        return _json(<String, Object?>{
          'devices': <Object?>[
            _deviceRow(),
            _deviceRow(
              id: 'dev-2',
              name: 'Redmi K70',
              version: '0.2.11',
              active: '2026-11-15T20:30:00+08:00',
              current: false,
            ),
          ],
        });
      });
      final auth = await _loggedInAuth(client: client);

      final devices = await auth.getDevices();

      expect(paths, <String>['/api/v1/auth/devices']);
      expect(devices, hasLength(2));
      expect(devices[0].id, 'dev-1');
      expect(devices[0].name, 'Honor Magic6');
      expect(devices[0].is_current, isTrue);
      expect(devices[0].app_version, '0.2.12');
      expect(
        devices[0].last_active_at,
        DateTime.parse('2026-11-17T09:06:00+08:00').millisecondsSinceEpoch,
      );
      expect(devices[1].id, 'dev-2');
      expect(devices[1].name, 'Redmi K70');
      expect(devices[1].is_current, isFalse);
      expect(devices[1].app_version, '0.2.11');
    });

    test('服务端空列表是诚实空（仍发了一次请求）', () async {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return _json(<String, Object?>{'devices': <Object?>[]});
      });
      final auth = await _loggedInAuth(client: client);

      expect(await auth.getDevices(), isEmpty);
      expect(calls, 1);
    });

    test('未登录：不发请求，回落 Mock 空列表', () async {
      final client = MockClient(
        (_) async => throw StateError('must not be called'),
      );
      final auth = HttpAuthService(
        client: client,
        kvStore: InMemoryKvStore(),
        secureStore: InMemorySecureSessionStore(),
        baseUrl: _base,
        fallback: MockAuthService(),
      );

      expect(await auth.getDevices(), isEmpty);
    });

    test('404 / 500 回落 Mock 空列表，不抛给 UI', () async {
      for (final status in <int>[404, 500]) {
        final client = MockClient(
          (_) async => _json(<String, Object?>{'detail': 'err'}, status),
        );
        final auth = await _loggedInAuth(client: client);
        expect(await auth.getDevices(), isEmpty);
      }
    });

    test('断网回落 Mock 空列表，不抛给 UI', () async {
      final client = MockClient(
        (_) async => throw const SocketException('offline'),
      );
      final auth = await _loggedInAuth(client: client);

      expect(await auth.getDevices(), isEmpty);
    });

    test('坏形状（非 JSON / 缺 devices 键）回落空列表', () async {
      final badBodies = <http.Response>[
        http.Response('not json', 200),
        _json(<String, Object?>{'unexpected': true}),
      ];
      for (final response in badBodies) {
        final client = MockClient((_) async => response);
        final auth = await _loggedInAuth(client: client);
        expect(await auth.getDevices(), isEmpty);
      }
    });

    test('缺字段行整行丢弃；空 device_name 显示未知设备', () async {
      final client = MockClient(
        (_) async => _json(<String, Object?>{
          'devices': <Object?>[
            _deviceRow(),
            <String, Object?>{'id': 'no-time'},
            <String, Object?>{
              'device_name': 'no-id',
              'last_active_at': '2026-11-17T09:06:00+08:00',
            },
            _deviceRow(id: 'dev-empty', name: ''),
          ],
        }),
      );
      final auth = await _loggedInAuth(client: client);

      final devices = await auth.getDevices();

      expect(devices.map((d) => d.id), <String>['dev-1', 'dev-empty']);
      expect(devices[1].name, '未知设备');
    });

    test('401 刷新一次并重放（AuthHttpClient）', () async {
      final authorization = <String?>[];
      final client = MockClient((request) async {
        final path = request.url.path;
        if (path == '/api/v1/auth/login') {
          return _json(<String, Object?>{
            'accessToken': 'access-1',
            'refreshToken': 'refresh-1',
            'tokenType': 'Bearer',
            'expiresIn': 900,
            'user': <String, Object?>{
              'id': 7,
              'nickname': 'Max',
              'avatarUrl': null,
            },
          });
        }
        if (path == '/api/v1/auth/refresh') {
          return _json(<String, Object?>{
            'accessToken': 'access-2',
            'refreshToken': 'refresh-2',
            'tokenType': 'Bearer',
            'expiresIn': 900,
          });
        }
        if (path == '/api/v1/auth/devices') {
          final header = request.headers['authorization'];
          authorization.add(header);
          if (header == 'Bearer access-1') {
            return _json(<String, Object?>{'detail': '登录会话已失效'}, 401);
          }
          return _json(<String, Object?>{
            'devices': <Object?>[_deviceRow()],
          });
        }
        return _json(<String, Object?>{}, 404);
      });
      final auth = HttpAuthService(
        client: client,
        kvStore: InMemoryKvStore(),
        secureStore: InMemorySecureSessionStore(),
        baseUrl: _base,
        fallback: MockAuthService(),
      );
      final login = await auth.login(phone: _phone, password: 'secret123');
      expect(login.success, isTrue);
      auth.authClient = AuthHttpClient(auth: auth, inner: client);

      final devices = await auth.getDevices();

      expect(devices.single.id, 'dev-1');
      expect(authorization, <String>['Bearer access-1', 'Bearer access-2']);
      expect(auth.cachedAccessToken, 'access-2');
    });
  });

  group('个人中心设备列表 (B3)', () {
    testWidgets('渲染真实设备：名称 / 版本 / 最近活跃 / 当前设备标注', (
      tester,
    ) async {
      final auth = _DevicesAuth(<Device>[
        Device(
          id: 'dev-1',
          name: 'Honor Magic6',
          last_active_at: DateTime(2026, 11, 17, 9, 6).millisecondsSinceEpoch,
          is_current: true,
          app_version: '0.2.12',
        ),
        Device(
          id: 'dev-2',
          name: 'Redmi K70',
          last_active_at: DateTime(2026, 11, 15, 20, 30).millisecondsSinceEpoch,
          is_current: false,
          app_version: '0.2.11',
        ),
        Device(
          id: 'dev-3',
          name: 'Old iPad',
          last_active_at: DateTime(2026, 11, 1, 8, 0).millisecondsSinceEpoch,
          is_current: false,
        ),
      ]);
      await auth.login(phone: _phone, password: 'Demo1234');

      await _pumpProfile(tester, auth: auth);

      expect(find.text('Honor Magic6（当前设备）'), findsOneWidget);
      expect(find.text('Redmi K70'), findsOneWidget);
      expect(find.text('Old iPad'), findsOneWidget);
      expect(find.text('版本 0.2.12'), findsOneWidget);
      expect(find.text('版本 0.2.11'), findsOneWidget);
      expect(find.text('2026-11-17 09:06'), findsOneWidget);
      expect(find.text('2026-11-15 20:30'), findsOneWidget);
      expect(find.text('暂无其他设备'), findsNothing);
      expect(find.textContaining('待接口'), findsNothing);
    });

    testWidgets('空列表显示诚实「暂无其他设备」，不编造设备', (tester) async {
      final auth = _DevicesAuth(const <Device>[]);
      await auth.login(phone: _phone, password: 'Demo1234');

      await _pumpProfile(tester, auth: auth);

      expect(find.text('暂无其他设备'), findsOneWidget);
      expect(find.textContaining('其他设备列表待接口'), findsNothing);
      expect(find.textContaining('auth/devices'), findsNothing);
    });
  });
}
