// W2：web 登录无限转圈回归测试。
//
// 根因：web 上 dart:io 的 Platform 一触即抛 UnsupportedError，而登录
// 请求体在 try 之外组装 deviceModel —— 异常未捕获，_submitting 永不复位。
// VM 上 kIsWeb 恒为 false，无法直接断言 'Web' 分支；这里用「组装阶段抛
// 异常」模拟同一故障形态，钉住两层防线：
// 1. login() 把请求体组装放进 try —— 组装失败返回失败文案而非未捕获异常；
// 2. LoginPage._submit 的 try/finally —— login 抛异常时按钮复位并提示。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:routepass/core/kv_store.dart';
import 'package:routepass/models/auth.dart';
import 'package:routepass/pages/base/login_page.dart';
import 'package:routepass/router/app_router.dart';
import 'package:routepass/services/auth/auth_service.dart';
import 'package:routepass/services/auth/secure_session_store.dart';
import 'package:routepass/services/base/auth_service.dart';
import 'package:routepass/services/mock/mock_auth_service.dart';

import 'test_helpers.dart';

void main() {
  setUp(initTestServices);

  test('login body-building failure is a LoginResult, not an uncaught throw', () async {
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      throw StateError('no request should be sent when the body cannot build');
    });
    final auth = HttpAuthService(
      client: client,
      kvStore: _ThrowingKvStore(),
      secureStore: InMemorySecureSessionStore(),
      baseUrl: 'http://test',
    );

    // 修复前：body 在 try 之外组装，_deviceId() 抛异常直接逃逸。
    final result = await auth.login(
      phone: '13800138000',
      password: 'secret123',
    );

    expect(result.success, isFalse);
    expect(result.message, '网络连接失败，请检查网络后重试');
    expect(requests, 0);
  });

  testWidgets('login throw re-enables the button and shows the failure', (
    tester,
  ) async {
    final stub = _ThrowingAuthService();
    await _pumpLogin(tester, authService: stub);

    await _submitCredentials(tester);

    expect(stub.loginCalls, 1);
    expect(find.text('网络连接失败，请检查网络后重试'), findsOneWidget);
    expect(find.byType(LoginPage), findsOneWidget);

    // 修复前：_submitting 卡在 true，第二次点击被 `if (_submitting) return`
    // 吞掉，按钮永远转圈。
    await _submitCredentials(tester);
    expect(stub.loginCalls, 2);
  });
}

/// 模拟 web 上 Platform 一触即抛：deviceId 读取（请求体组装的一部分）失败。
class _ThrowingKvStore extends InMemoryKvStore {
  @override
  String? getString(String key) =>
      throw UnsupportedError('simulated web dart:io failure');
}

class _ThrowingAuthService extends MockAuthService {
  int loginCalls = 0;

  @override
  Future<LoginResult> login({
    required String phone,
    required String password,
  }) async {
    loginCalls++;
    throw UnsupportedError('simulated web dart:io failure');
  }
}

Future<void> _pumpLogin(WidgetTester tester, {AuthService? authService}) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: LoginPage(authService: authService),
      onGenerateRoute: AppRouter.onGenerateRoute,
    ),
  );
  // 顶部图形无限动画，不能 pumpAndSettle，只推一帧。
  await tester.pump();
}

Future<void> _submitCredentials(WidgetTester tester) async {
  final fields = find.byType(TextField);
  await tester.enterText(fields.at(0), '13800138000');
  await tester.enterText(fields.at(1), 'Demo1234');
  await tester.tap(find.text('login'));
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}
