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
import 'package:routepass/pages/base/profile_page.dart';
import 'package:routepass/router/app_router.dart';
import 'package:routepass/services/bank/bank_sync_service.dart';
import 'package:routepass/services/bank/local_cache_service.dart';
import 'package:routepass/services/bank/sync_http_service.dart';
import 'package:routepass/services/mock/mock_auth_service.dart';

const _phone = '13800138000';

class _StubAuth extends MockAuthService {
  _StubAuth({required this.device});

  final LocalDeviceInfo device;

  @override
  Future<LocalDeviceInfo?> currentDevice() async => device;
}

class _FakeSync implements SyncService {
  _FakeSync(this.status, {this.result});

  SyncStatus? status;
  ManualSyncResult? result;
  final List<String> calls = <String>[];

  @override
  SyncStatus? get cachedStatus => status;

  @override
  Future<SyncStatus> getSyncStatus() async {
    calls.add('getSyncStatus');
    return status!;
  }

  @override
  Future<ManualSyncResult> syncNow() async {
    calls.add('syncNow');
    final manual =
        result ??
        const ManualSyncResult(ok: true, message: '已是最新', state: 'synced');
    status = SyncStatus(
      pendingCount: 0,
      lastSyncAt: DateTime(2026, 11, 14, 10, 30).millisecondsSinceEpoch,
      state: manual.state,
      serverTime: status?.serverTime,
      watermark: status?.watermark,
    );
    return manual;
  }

  @override
  Future<PushResult> pushPendingOps() async {
    calls.add('pushPendingOps');
    return const PushResult(pushedCount: 0, failedCount: 0);
  }

  @override
  Future<PullResult> pullIncremental({int? since}) async {
    calls.add('pullIncremental');
    return const PullResult(pulledCount: 0);
  }
}

Future<void> _pumpProfile(
  WidgetTester tester, {
  required MockAuthService auth,
  required SyncService sync,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: ProfilePage(authService: auth, syncService: sync),
      onGenerateRoute: AppRouter.onGenerateRoute,
    ),
  );
  await tester.pumpAndSettle();
}

Future<MockAuthService> _loggedInAuth() async {
  final auth = MockAuthService();
  final result = await auth.login(phone: _phone, password: 'Demo1234');
  expect(result.success, isTrue);
  return auth;
}

void main() {
  group('Profile page - Device section', () {
    testWidgets('shows this device, bound account and binding state', (
      tester,
    ) async {
      final auth = _StubAuth(
        device: const LocalDeviceInfo(
          deviceId: 'abcdefgh-1234-5678-9abc-def012345678',
          deviceModel: 'Pixel 9',
          appVersion: '0.2.8',
        ),
      );
      await auth.login(phone: _phone, password: 'Demo1234');
      final sync = _FakeSync(
        const SyncStatus(pendingCount: 0, state: 'synced'),
      );

      await _pumpProfile(tester, auth: auth, sync: sync);

      expect(find.text('设备'), findsOneWidget);
      expect(find.text('abcdefgh…5678'), findsOneWidget);
      expect(find.text('Pixel 9'), findsOneWidget);
      expect(find.text('0.2.8'), findsOneWidget);
      expect(find.text(_phone), findsOneWidget);
      expect(find.text('已绑定'), findsOneWidget);
      expect(find.text('其他设备列表待接口'), findsOneWidget);
      expect(find.textContaining('auth/devices'), findsOneWidget);
    });

    testWidgets('not logged in shows 未登录, login button and disables sync', (
      tester,
    ) async {
      final auth = _StubAuth(
        device: const LocalDeviceInfo(
          deviceId: 'local-device',
          deviceModel: '本机',
          appVersion: '0.2.8',
        ),
      );
      final sync = _FakeSync(
        const SyncStatus(pendingCount: 0, state: 'local_only'),
      );

      await _pumpProfile(tester, auth: auth, sync: sync);

      expect(find.text('未登录'), findsWidgets);
      expect(find.text('去登录'), findsOneWidget);
      expect(find.text('未登录，无法同步账号数据。'), findsOneWidget);

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '立即同步'),
      );
      expect(button.onPressed, isNull);
    });
  });

  group('Profile page - Sync section', () {
    testWidgets(
      'shows real state, last sync time, pending count and waterline',
      (tester) async {
        final auth = await _loggedInAuth();
        final sync = _FakeSync(
          SyncStatus(
            pendingCount: 3,
            lastSyncAt: DateTime(2026, 11, 14, 9, 5).millisecondsSinceEpoch,
            state: 'pending',
            serverTime: '2026-11-14T09:05:00',
            watermark: 12345,
          ),
        );

        await _pumpProfile(tester, auth: auth, sync: sync);

        expect(find.text('同步'), findsOneWidget);
        expect(find.text('待同步'), findsOneWidget);
        expect(find.text('待同步 3 条'), findsOneWidget);
        expect(find.text('2026-11-14 09:05'), findsWidgets);
        expect(find.text('12345'), findsOneWidget);
        expect(find.text('立即同步'), findsOneWidget);
      },
    );

    testWidgets('sync now triggers the service and refreshes the state', (
      tester,
    ) async {
      final auth = await _loggedInAuth();
      final sync = _FakeSync(
        const SyncStatus(pendingCount: 2, state: 'pending'),
        result: const ManualSyncResult(
          ok: true,
          message: '同步完成：拉取 2 条，上传 1 条',
          pulledCount: 2,
          uploadedCount: 1,
          state: 'synced',
        ),
      );

      await _pumpProfile(tester, auth: auth, sync: sync);

      expect(find.text('待同步 2 条'), findsOneWidget);
      await tester.tap(find.text('立即同步'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(sync.calls, contains('syncNow'));
      expect(sync.calls.indexOf('syncNow'), greaterThan(0));
      expect(sync.calls.last, 'syncNow');
      expect(find.textContaining('同步完成：拉取 2 条，上传 1 条'), findsWidgets);
      expect(find.text('已同步'), findsOneWidget);
      expect(find.text('待同步 0 条'), findsOneWidget);
    });

    testWidgets('offline shows the cached state and an honest note', (
      tester,
    ) async {
      final auth = await _loggedInAuth();
      final sync = _FakeSync(
        SyncStatus(
          pendingCount: 1,
          lastSyncAt: DateTime(2026, 11, 13, 20, 15).millisecondsSinceEpoch,
          state: 'offline',
        ),
      );

      await _pumpProfile(tester, auth: auth, sync: sync);

      expect(find.text('离线'), findsOneWidget);
      expect(find.text('2026-11-13 20:15'), findsOneWidget);
      expect(find.text('待同步 1 条'), findsOneWidget);
      expect(find.text('当前网络不可达，展示的是本地缓存的同步状态。'), findsOneWidget);
    });
  });

  group('HttpSyncService', () {
    test('pull 200 reports synced state with server time/watermark', () async {
      final kv = InMemoryKvStore();
      final requests = <String>[];
      final client = MockClient((request) async {
        requests.add(request.url.path);
        if (request.url.path == '/api/v1/sync/pull') {
          return _json(200, _pullJson());
        }
        return _json(404, <String, Object?>{});
      });
      final service = HttpSyncService(
        client: client,
        baseUrl: 'http://test',
        tokenProvider: () => 'token-1',
        kvStore: kv,
      );

      final status = await service.getSyncStatus();

      expect(status.state, 'synced');
      expect(status.watermark, 101);
      expect(status.serverTime, '2026-11-14T09:05:00+08:00');
      expect(status.lastSyncAt, isNotNull);
      expect(service.cachedStatus?.state, 'synced');
      expect(kv.getString(KvStore.keySyncStatus), contains('synced'));
    });

    test('not logged in stays local_only without any request', () async {
      final client = MockClient(
        (_) async => throw StateError('must not be called'),
      );
      final service = HttpSyncService(
        client: client,
        baseUrl: 'http://test',
        tokenProvider: () => null,
        kvStore: InMemoryKvStore(),
      );

      final status = await service.getSyncStatus();
      final result = await service.syncNow();

      expect(status.state, 'local_only');
      expect(result.ok, isFalse);
      expect(result.message, contains('未登录'));
    });

    test('empty local + server data pulls instead of pushing', () async {
      final kv = InMemoryKvStore();
      final paths = <String>[];
      final client = MockClient((request) async {
        paths.add(request.url.path);
        if (request.url.path == '/api/v1/sync/baseline') {
          return _json(200, _baselineJson());
        }
        if (request.url.path == '/api/v1/sync/pull') {
          return _json(200, _pullJson());
        }
        if (request.url.path == '/api/v1/sync/push') {
          return _json(200, <String, Object?>{'accepted': 1});
        }
        return _json(404, <String, Object?>{});
      });
      final service = HttpSyncService(
        client: client,
        baseUrl: 'http://test',
        tokenProvider: () => 'token-1',
        kvStore: kv,
        localCache: InMemoryBankLocalCache(),
      );

      final result = await service.syncNow();

      expect(result.ok, isTrue);
      expect(result.message, startsWith('本地无数据，已从服务器拉取'));
      expect(result.uploadedCount, 0);
      expect(paths, isNot(contains('/api/v1/sync/push')));
      expect(kv.getString(KvStore.keySyncCursor), '101');
      expect(kv.getString(KvStore.keySyncMirror), isNotNull);
    });

    test('manual sync pushes pending ops, then pulls again', () async {
      final kv = InMemoryKvStore();
      final cache = InMemoryBankLocalCache();
      await cache.enqueueSync(
        LocalSyncOp(
          opId: 'answer-VLAN-q1-1700000000000',
          kind: LocalSyncOp.kindPracticeAnswer,
          createdAt: 1700000000000,
          payload: const <String, Object?>{
            'setId': 'VLAN',
            'questionId': 'q1',
            'chosen': <String>['A'],
            'durationMs': 5000,
            'mode': 'practice',
          },
        ),
      );
      final paths = <String>[];
      final pushBodies = <Map<String, dynamic>>[];
      final client = MockClient((request) async {
        paths.add(request.url.path);
        if (request.url.path == '/api/v1/sync/baseline') {
          return _json(200, _baselineJson());
        }
        if (request.url.path == '/api/v1/sync/pull') {
          return _json(200, _pullJson());
        }
        if (request.url.path == '/api/v1/sync/push') {
          final body = request.body;
          final decoded = body.isEmpty
              ? <String, dynamic>{}
              : jsonDecode(body) as Map<String, dynamic>;
          pushBodies.add(decoded);
          final changes = decoded['changes'] as List<dynamic>? ?? <dynamic>[];
          final opId = changes.isEmpty
              ? ''
              : (changes.first as Map<String, dynamic>)['opId'] as String;
          return _json(200, <String, Object?>{
            'accepted': changes.length,
            'duplicated': 0,
            'rejected': 0,
            'results': <Object?>[
              <String, Object?>{'opId': opId, 'status': 'accepted'},
            ],
          });
        }
        return _json(404, <String, Object?>{});
      });
      final service = HttpSyncService(
        client: client,
        baseUrl: 'http://test',
        tokenProvider: () => 'token-1',
        kvStore: kv,
        localCache: cache,
      );

      final result = await service.syncNow();

      expect(pushBodies, hasLength(1));
      final change =
          (pushBodies.first['changes'] as List<dynamic>).first
              as Map<String, dynamic>;
      expect(change['entity'], 'attempts');
      expect(change['data']['questionId'], 'q1');
      expect((change['opId'] as String).length, lessThanOrEqualTo(40));

      final pushIndex = paths.indexOf('/api/v1/sync/push');
      expect(pushIndex, greaterThan(0));
      expect(paths.lastIndexOf('/api/v1/sync/pull'), greaterThan(pushIndex));
      expect(result.uploadedCount, 1);
      expect(await cache.pendingSync(), isEmpty);
    });

    test('unreachable server keeps local state and reports offline', () async {
      final kv = InMemoryKvStore();
      kv.setString(
        KvStore.keySyncStatus,
        '{"pendingCount":0,"lastSyncAt":1700000000000,'
        '"state":"synced","serverTime":null,"watermark":null}',
      );
      final client = MockClient(
        (_) async => throw const SocketException('offline'),
      );
      final service = HttpSyncService(
        client: client,
        baseUrl: 'http://test',
        tokenProvider: () => 'token-1',
        kvStore: kv,
      );

      final status = await service.getSyncStatus();
      final result = await service.syncNow();

      expect(status.state, 'offline');
      expect(status.lastSyncAt, 1700000000000);
      expect(result.ok, isFalse);
      expect(result.state, 'offline');
      expect(result.message, contains('无法连接服务器'));
    });

    test('401 keeps the cached state instead of faking a sync', () async {
      final kv = InMemoryKvStore();
      kv.setString(
        KvStore.keySyncStatus,
        '{"pendingCount":0,"lastSyncAt":1700000000000,'
        '"state":"local_only","serverTime":null,"watermark":null}',
      );
      final client = MockClient(
        (_) async => _json(401, <String, Object?>{'detail': 'expired'}),
      );
      final service = HttpSyncService(
        client: client,
        baseUrl: 'http://test',
        tokenProvider: () => 'token-1',
        kvStore: kv,
      );

      final status = await service.getSyncStatus();

      expect(status.state, 'local_only');
      expect(status.lastSyncAt, 1700000000000);
    });

    test('中途失败不清空已拉页、也不推进游标（下次仍能拿到同一批）', () async {
      final kv = InMemoryKvStore();
      var pullCalls = 0;
      final client = MockClient((request) async {
        if (request.url.path == '/api/v1/sync/baseline') {
          return _json(404, <String, Object?>{});
        }
        if (request.url.path == '/api/v1/sync/pull') {
          pullCalls++;
          if (pullCalls == 1) {
            return _json(200, <String, Object?>{
              ..._pullJson(),
              'hasMore': true,
            });
          }
          // 第二页失败：本批变更一条都不能算已同步。
          return _json(500, <String, Object?>{});
        }
        return _json(404, <String, Object?>{});
      });
      final service = HttpSyncService(
        client: client,
        baseUrl: 'http://test',
        tokenProvider: () => 'token-1',
        kvStore: kv,
      );

      final result = await service.syncNow();

      expect(result.ok, isFalse);
      expect(result.state, 'offline');
      expect(kv.getString(KvStore.keySyncCursor), isNull);
      expect(kv.getString(KvStore.keySyncMirror), isNull);
    });

    test('pullIncremental 有待上传操作时状态为 pending，而不是已同步', () async {
      final kv = InMemoryKvStore();
      final cache = InMemoryBankLocalCache();
      await cache.enqueueSync(
        LocalSyncOp(
          opId: 'answer-VLAN-q1-1700000000000',
          kind: LocalSyncOp.kindPracticeAnswer,
          createdAt: 1700000000000,
          payload: const <String, Object?>{
            'setId': 'VLAN',
            'questionId': 'q1',
            'chosen': <String>['A'],
            'durationMs': 5000,
            'mode': 'practice',
          },
        ),
      );
      final client = MockClient((request) async {
        if (request.url.path == '/api/v1/sync/pull') {
          return _json(200, _pullJson());
        }
        return _json(404, <String, Object?>{});
      });
      final service = HttpSyncService(
        client: client,
        baseUrl: 'http://test',
        tokenProvider: () => 'token-1',
        kvStore: kv,
        localCache: cache,
      );

      await service.pullIncremental();

      expect(service.cachedStatus?.state, 'pending');
      expect(service.cachedStatus?.pendingCount, 1);
      expect(kv.getString(KvStore.keySyncCursor), '101');
    });
  });
}

http.Response _json(int statusCode, Object body) {
  return http.Response(
    jsonEncode(body),
    statusCode,
    headers: <String, String>{
      'content-type': 'application/json; charset=utf-8',
    },
  );
}

Map<String, Object?> _pullJson() {
  return <String, Object?>{
    'changes': <Object?>[
      <String, Object?>{
        'txid': 101,
        'entity': 'wrong_book',
        'entityId': 'q1',
        'op': 'upsert',
        'data': <String, Object?>{
          'questionId': 'q1',
          'wrongCount': 2,
          'mastered': false,
          'clientAt': '2026-11-14T09:04:00+08:00',
        },
        'clientAt': '2026-11-14T09:04:00+08:00',
      },
    ],
    'nextCursor': 101,
    'watermark': 101,
    'hasMore': false,
    'serverTime': '2026-11-14T09:05:00+08:00',
    'baselineRequired': false,
  };
}

Map<String, Object?> _baselineJson() {
  return <String, Object?>{
    'source': 'live',
    'txidWatermark': 101,
    'generatedAt': '2026-11-14T09:05:00+08:00',
    'wrongBook': <Object?>[
      <String, Object?>{
        'questionId': 'q1',
        'wrongCount': 2,
        'lastWrongAt': '2026-11-14T09:04:00+08:00',
        'mastered': false,
      },
      <String, Object?>{
        'questionId': 'q2',
        'wrongCount': 1,
        'lastWrongAt': '2026-11-13T09:04:00+08:00',
        'mastered': true,
      },
    ],
    'favorites': <Object?>[],
    'userKv': <Object?>[],
    'dailyStats': <Object?>[],
  };
}
