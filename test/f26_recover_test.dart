import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:routepass/core/kv_store.dart';
import 'package:routepass/models/auth.dart';
import 'package:routepass/models/user.dart';
import 'package:routepass/pages/base/login_page.dart';
import 'package:routepass/pages/base/recover_page.dart';
import 'package:routepass/pages/shell/app_shell.dart';
import 'package:routepass/router/app_router.dart';
import 'package:routepass/services/auth/auth_service.dart';
import 'package:routepass/services/base/auth_service.dart';
import 'package:routepass/services/mock/mock_auth_service.dart';

import 'test_helpers.dart';

// F26 chunk 3：找回密码（POST /api/v1/auth/recover）。
// 服务层走 MockClient 真实契约；页面层注入 stub，校验失败绝不发请求。

const _phone = '13800138000';
const _oldCode = 'apple river cloud stone bright maple harbor silver oak fern';
const _newCode = 'birch lake ember frost cedar wolf meadow dusk pine brook';

Future<void> _pumpRecover(
  WidgetTester tester, {
  AuthService? authService,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: RecoverPage(authService: authService),
      onGenerateRoute: AppRouter.onGenerateRoute,
    ),
  );
  await tester.pump();
}

Future<void> _fillForm(
  WidgetTester tester, {
  String phone = _phone,
  String code = _oldCode,
  String password = 'NewPass123',
  String confirm = 'NewPass123',
}) async {
  await tester.enterText(find.byKey(const Key('recover-phone')), phone);
  await tester.enterText(find.byKey(const Key('recover-code')), code);
  await tester.enterText(find.byKey(const Key('recover-password')), password);
  await tester.enterText(find.byKey(const Key('recover-confirm')), confirm);
}

Future<void> _submitRecover(WidgetTester tester) async {
  await tester.ensureVisible(find.text('重置密码'));
  await tester.pump();
  await tester.tap(find.text('重置密码'));
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

String? _errorOf(WidgetTester tester, String fieldKey) {
  final field = tester.widget<TextField>(find.byKey(Key(fieldKey)));
  return field.decoration?.errorText;
}

void main() {
  setUp(initTestServices);

  // ---- 服务层：真实契约（MockClient） ----

  test(
    'recover success parses tokens/user/new code and persists session',
    () async {
      final kv = InMemoryKvStore();
      http.Request? recoverRequest;
      final client = MockClient((request) async {
        if (request.url.path == '/api/v1/auth/recover') {
          recoverRequest = request;
          return _jsonResponse(200, _recoverJson(restoreCode: _newCode));
        }
        return _jsonResponse(404, <String, Object?>{'detail': 'not found'});
      });
      final auth = HttpAuthService(
        client: client,
        kvStore: kv,
        baseUrl: 'http://test',
        deviceId: 'device-abc',
      );

      final result = await auth.recover(
        phone: _phone,
        restoreCode: _oldCode,
        newPassword: 'NewPass123',
      );

      expect(result.success, isTrue);
      expect(result.user?.username, _phone);
      expect(result.user?.nickname, 'Max');
      expect(result.restoreCode, _newCode);
      expect(auth.cachedAccessToken, 'access-1');

      final body = jsonDecode(recoverRequest!.body) as Map<String, dynamic>;
      expect(body['phone'], _phone);
      expect(body['restoreCode'], _oldCode);
      expect(body['newPassword'], 'NewPass123');

      final stored = kv.getString(KvStore.keyAuthSession);
      expect(stored, isNotNull);
      expect(stored, contains('access-1'));
      expect(stored, contains('refresh-1'));
      expect(stored, isNot(contains('NewPass123')));
      expect(stored, isNot(contains(_oldCode)));
      expect(await auth.getCurrentUser(), isNotNull);
    },
  );

  test(
    'recover 401 surfaces the invalid-code message and keeps no session',
    () async {
      final kv = InMemoryKvStore();
      final client = MockClient(
        (_) async => _jsonResponse(401, <String, Object?>{
          'error': <String, Object?>{
            'code': 'RESTORE_CODE_INVALID',
            'message': '恢复码无效',
          },
        }),
      );
      final auth = HttpAuthService(
        client: client,
        kvStore: kv,
        baseUrl: 'http://test',
      );

      final result = await auth.recover(
        phone: _phone,
        restoreCode: 'wrong code words here',
        newPassword: 'NewPass123',
      );

      expect(result.success, isFalse);
      expect(result.statusCode, 401);
      expect(result.message, '恢复码无效');
      expect(result.restoreCode, isNull);
      expect(kv.getString(KvStore.keyAuthSession), isNull);
      expect(auth.cachedAccessToken, isNull);
    },
  );

  test('recover 422 bad phone surfaces the validation message', () async {
    final client = MockClient(
      (_) async => _jsonResponse(422, <String, Object?>{
        'error': <String, Object?>{
          'code': 'VALIDATION_ERROR',
          'message': '手机号格式不正确',
        },
      }),
    );
    final auth = HttpAuthService(
      client: client,
      kvStore: InMemoryKvStore(),
      baseUrl: 'http://test',
    );

    final result = await auth.recover(
      phone: '12800138000',
      restoreCode: _oldCode,
      newPassword: 'NewPass123',
    );

    expect(result.success, isFalse);
    expect(result.statusCode, 422);
    expect(result.message, '手机号格式不正确');
  });

  test('recover 422 short password surfaces the validation message', () async {
    final client = MockClient(
      (_) async => _jsonResponse(422, <String, Object?>{
        'error': <String, Object?>{
          'code': 'VALIDATION_ERROR',
          'message': '密码长度需为 6-72 字节',
        },
      }),
    );
    final auth = HttpAuthService(
      client: client,
      kvStore: InMemoryKvStore(),
      baseUrl: 'http://test',
    );

    final result = await auth.recover(
      phone: _phone,
      restoreCode: _oldCode,
      newPassword: '12345',
    );

    expect(result.success, isFalse);
    expect(result.statusCode, 422);
    expect(result.message, '密码长度需为 6-72 字节');
  });

  test('recover network failure is retry-able and keeps no session', () async {
    final kv = InMemoryKvStore();
    final client = MockClient((_) async => throw Exception('offline'));
    final auth = HttpAuthService(
      client: client,
      kvStore: kv,
      baseUrl: 'http://test',
    );

    final result = await auth.recover(
      phone: _phone,
      restoreCode: _oldCode,
      newPassword: 'NewPass123',
    );

    expect(result.success, isFalse);
    expect(result.statusCode, isNull);
    expect(result.message, '网络连接失败，请检查网络后重试');
    expect(kv.getString(KvStore.keyAuthSession), isNull);
  });

  test(
    'recover 401 without a JSON body falls back to the invalid-code text',
    () async {
      final client = MockClient(
        (_) async => http.Response('gateway timeout', 401),
      );
      final auth = HttpAuthService(
        client: client,
        kvStore: InMemoryKvStore(),
        baseUrl: 'http://test',
      );

      final result = await auth.recover(
        phone: _phone,
        restoreCode: _oldCode,
        newPassword: 'NewPass123',
      );

      expect(result.success, isFalse);
      expect(result.statusCode, 401);
      expect(result.message, '恢复码无效，请核对后重试');
    },
  );

  // ---- 页面层：客户端校验失败绝不发请求 ----

  testWidgets(
    'confirm-password mismatch shows an error and never calls the backend',
    (tester) async {
      final stub = _StubRecoverAuth(const RecoverResult(success: true));
      await _pumpRecover(tester, authService: stub);

      await _fillForm(tester, confirm: 'Different123');
      await _submitRecover(tester);

      expect(stub.recoverCalls, 0);
      expect(_errorOf(tester, 'recover-confirm'), '两次输入的密码不一致');
      expect(find.byType(RecoverPage), findsOneWidget);
      expect(find.byType(AppShell), findsNothing);
    },
  );

  testWidgets('bad phone is rejected client-side before any request', (
    tester,
  ) async {
    final stub = _StubRecoverAuth(const RecoverResult(success: true));
    await _pumpRecover(tester, authService: stub);

    await _fillForm(tester, phone: '12800138000');
    await _submitRecover(tester);

    expect(stub.recoverCalls, 0);
    expect(_errorOf(tester, 'recover-phone'), '请输入 11 位手机号码');
  });

  testWidgets('short new password is rejected client-side before any request', (
    tester,
  ) async {
    final stub = _StubRecoverAuth(const RecoverResult(success: true));
    await _pumpRecover(tester, authService: stub);

    await _fillForm(tester, password: '12345', confirm: '12345');
    await _submitRecover(tester);

    expect(stub.recoverCalls, 0);
    expect(_errorOf(tester, 'recover-password'), '密码长度需为 6-72 字节');
  });

  testWidgets('empty restore code is rejected client-side before any request', (
    tester,
  ) async {
    final stub = _StubRecoverAuth(const RecoverResult(success: true));
    await _pumpRecover(tester, authService: stub);

    await _fillForm(tester, code: '');
    await _submitRecover(tester);

    expect(stub.recoverCalls, 0);
    expect(_errorOf(tester, 'recover-code'), '请输入 12 词恢复码');
  });

  testWidgets('success shows the NEW restore code once, then enters the app', (
    tester,
  ) async {
    final stub = _StubRecoverAuth(
      const RecoverResult(
        success: true,
        user: User(id: '7', username: _phone, nickname: 'Max'),
        restoreCode: _newCode,
      ),
    );
    await _pumpRecover(tester, authService: stub);

    await _fillForm(tester);
    await _submitRecover(tester);

    expect(stub.recoverCalls, 1);
    expect(stub.lastPhone, _phone);
    expect(stub.lastRestoreCode, _oldCode);
    expect(stub.lastNewPassword, 'NewPass123');

    expect(find.text('请保存新恢复码'), findsOneWidget);
    final shown = tester.widget<SelectableText>(
      find.byKey(const Key('restore-code')),
    );
    expect(shown.data, _newCode);
    expect(find.byType(AppShell), findsNothing);

    await tester.tap(find.text('我已保存，进入 App'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(AppShell), findsOneWidget);
    expect(find.byType(RecoverPage), findsNothing);
    expect(find.byType(LoginPage), findsNothing);
  });

  testWidgets(
    '401 invalid code shows the server message and stays on the form',
    (tester) async {
      final stub = _StubRecoverAuth(
        const RecoverResult(success: false, message: '恢复码无效', statusCode: 401),
      );
      await _pumpRecover(tester, authService: stub);

      await _fillForm(tester);
      await _submitRecover(tester);

      expect(stub.recoverCalls, 1);
      expect(find.text('恢复码无效'), findsOneWidget);
      expect(find.byType(RecoverPage), findsOneWidget);
      expect(find.byType(AppShell), findsNothing);
    },
  );

  testWidgets(
    'network failure shows a retry-able error and stays on the form',
    (tester) async {
      final stub = _StubRecoverAuth(
        const RecoverResult(success: false, message: '网络连接失败，请检查网络后重试'),
      );
      await _pumpRecover(tester, authService: stub);

      await _fillForm(tester);
      await _submitRecover(tester);

      expect(find.text('网络连接失败，请检查网络后重试'), findsOneWidget);
      expect(find.byType(RecoverPage), findsOneWidget);
    },
  );

  // ---- 登录页入口 ----

  testWidgets(
    'login page has a forgot-password entry that opens the recover form',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: LoginPage(
            authService: _StubRecoverAuth(const RecoverResult(success: true)),
          ),
          onGenerateRoute: AppRouter.onGenerateRoute,
        ),
      );
      // 登录页顶部图形无限动画，不能 pumpAndSettle。
      await tester.pump();

      final entry = find.byKey(const Key('forgot-password'));
      expect(entry, findsOneWidget);
      expect(find.widgetWithText(TextButton, '忘记密码？'), findsOneWidget);

      await tester.ensureVisible(entry);
      await tester.pump();
      await tester.tap(entry);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(RecoverPage), findsOneWidget);
      expect(find.text('找回密码'), findsOneWidget);
    },
  );
}

http.Response _jsonResponse(int statusCode, Object body) {
  return http.Response(
    jsonEncode(body),
    statusCode,
    headers: <String, String>{
      'content-type': 'application/json; charset=utf-8',
    },
  );
}

Map<String, Object?> _recoverJson({required String restoreCode}) {
  return <String, Object?>{
    'accessToken': 'access-1',
    'refreshToken': 'refresh-1',
    'tokenType': 'Bearer',
    'expiresIn': 900,
    'user': <String, Object?>{'id': 7, 'nickname': 'Max', 'avatarUrl': null},
    'restoreCode': restoreCode,
  };
}

class _StubRecoverAuth extends MockAuthService {
  _StubRecoverAuth(this.result);

  final RecoverResult result;
  int recoverCalls = 0;
  String? lastPhone;
  String? lastRestoreCode;
  String? lastNewPassword;

  @override
  Future<RecoverResult> recover({
    required String phone,
    required String restoreCode,
    required String newPassword,
  }) async {
    recoverCalls++;
    lastPhone = phone;
    lastRestoreCode = restoreCode;
    lastNewPassword = newPassword;
    return result;
  }
}
