import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:routepass/core/kv_store.dart';
import 'package:routepass/core/service_locator.dart';
import 'package:routepass/core/theme.dart';
import 'package:routepass/models/auth.dart';
import 'package:routepass/models/user.dart';
import 'package:routepass/pages/base/login_page.dart';
import 'package:routepass/pages/shell/app_shell.dart';
import 'package:routepass/router/app_router.dart';
import 'package:routepass/services/auth/auth_service.dart';
import 'package:routepass/services/base/auth_service.dart';
import 'package:routepass/services/mock/mock_auth_service.dart';

import 'test_helpers.dart';

Future<void> _pumpLogin(WidgetTester tester, {AuthService? authService}) async {
  // 1:1 参考稿的 390x844 画幅，保证两个胶囊与 login 按钮都在视口内。
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

Future<void> _submitPhone(WidgetTester tester, String phone) async {
  await _submitCredentials(tester, phone, 'Demo1234');
}

Future<void> _submitCredentials(
  WidgetTester tester,
  String phone,
  String password,
) async {
  final fields = find.byType(TextField);
  await tester.enterText(fields.at(0), phone);
  await tester.enterText(fields.at(1), password);
  await tester.tap(find.text('login'));
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUp(initTestServices);

  testWidgets('valid unknown phone creates an account and navigates home', (
    tester,
  ) async {
    const phone = '13800138000';
    await _pumpLogin(tester);

    await _submitPhone(tester, phone);

    expect(find.byType(AppShell), findsOneWidget);
    expect(find.byType(LoginPage), findsNothing);
    final user = await ServiceLocator.authService.getCurrentUser();
    expect(user, isNotNull);
    expect(user!.username, phone);
  });

  test(
    'known phone logs into the account created by the first login',
    () async {
      final service = MockAuthService();
      final created = await service.login(
        phone: '13900139000',
        password: 'Demo1234',
      );
      await service.logout();

      final loggedIn = await service.login(
        phone: '13900139000',
        password: 'Other5678',
      );

      expect(created.success, isTrue);
      expect(loggedIn.success, isTrue);
      expect(loggedIn.user, same(created.user));
      expect(await service.getCurrentUser(), same(created.user));
    },
  );

  final invalidPhones = <String, String>{
    '': '请输入手机号码',
    '1380013800': '请输入 11 位手机号码',
    '12800138000': '请输入 11 位手机号码',
    '1380013800a': '请输入 11 位手机号码',
  };
  for (final entry in invalidPhones.entries) {
    final description = entry.key.isEmpty ? 'empty' : entry.key;
    testWidgets('phone validation rejects $description', (tester) async {
      await _pumpLogin(tester);

      await _submitPhone(tester, entry.key);

      final phoneField = tester.widget<TextField>(find.byType(TextField).first);
      expect(phoneField.decoration?.errorText, entry.value);
      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.byType(AppShell), findsNothing);
    });
  }

  testWidgets('login has one combined submit and no floating field labels', (
    tester,
  ) async {
    await _pumpLogin(tester);

    expect(find.text('login'), findsOneWidget);
    expect(find.text('登录 / 注册'), findsNothing);
    expect(find.text('注册'), findsNothing);
    expect(find.text('还没有账号？'), findsNothing);
    expect(find.widgetWithText(TextButton, '注册'), findsNothing);

    final fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .toList();
    expect(fields, hasLength(2));
    expect(fields.first.keyboardType, TextInputType.phone);
    for (final field in fields) {
      expect(field.decoration?.labelText, isNull);
      expect(field.decoration?.floatingLabelStyle, isNull);
    }

    expect(find.text('phone number'), findsOneWidget);
    expect(find.text('password'), findsOneWidget);
  });

  testWidgets('placeholders hide on focus and return when unfocused', (
    tester,
  ) async {
    await _pumpLogin(tester);

    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    expect(find.text('phone number'), findsNothing);
    expect(find.text('password'), findsOneWidget);

    await tester.tap(find.byType(TextField).last);
    await tester.pump();
    expect(find.text('phone number'), findsOneWidget);
    expect(find.text('password'), findsNothing);

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    expect(find.text('phone number'), findsOneWidget);
    expect(find.text('password'), findsOneWidget);
  });

  // ---- F15/F18：登录页保真度（Oswald / 标题宽度 / 胶囊尺寸 / 底部无黑带） ----

  testWidgets('F18 title uses bundled Oswald 700 and fits 410dp with margin', (
    tester,
  ) async {
    // 加载真实 Oswald 度量（离线打包的 TTF），宽度断言才有意义。
    final bold = rootBundle.load('assets/fonts/Oswald-Bold.ttf');
    final semiBold = rootBundle.load('assets/fonts/Oswald-SemiBold.ttf');
    await (FontLoader('Oswald')
          ..addFont(bold)
          ..addFont(semiBold))
        .load();
    await _pumpLoginScene(tester);

    final title = tester.widget<Text>(find.text('login in / sign up'));
    expect(title.style?.fontFamily, 'Oswald');
    expect(title.style?.fontWeight, FontWeight.w700);
    expect(title.style?.fontSize, 24);

    // Oswald-Bold 实测 6.956em：24px ≈ 167dp，远小于 410 - 2x24 的留白上限。
    final titleSize = tester.getSize(find.text('login in / sign up'));
    expect(titleSize.width, lessThanOrEqualTo(410 - 2 * 24));

    final fields = tester.widgetList<TextField>(find.byType(TextField));
    for (final field in fields) {
      expect(field.style?.fontFamily, 'Oswald');
      expect(field.decoration?.hintStyle?.fontFamily, 'Oswald');
    }
  });

  testWidgets(
    'F18 pills are 180x34 at 410dp, login button half-width centered',
    (tester) async {
      await _pumpLoginScene(tester);

      final fields = find.byType(TextField);
      final phoneRect = tester.getRect(fields.first);
      final passwordRect = tester.getRect(fields.last);
      expect(phoneRect.width, 180);
      expect(phoneRect.height, 34);
      expect(passwordRect.width, 180);
      expect(passwordRect.height, 34);

      final buttonRect = tester.getRect(
        find.widgetWithText(FilledButton, 'login'),
      );
      expect(buttonRect.width, passwordRect.width / 2);
      expect(buttonRect.height, 34);
      expect(buttonRect.center.dx, passwordRect.center.dx);
    },
  );

  testWidgets(
    'F18 whole login column fits the 410x915 viewport without overflow',
    (tester) async {
      await _pumpLoginScene(tester, brightness: Brightness.light);

      expect(tester.takeException(), isNull);

      // 布局列（图形 + 标题 + 两个胶囊 + 按钮）必须完整落在视口内。
      final column = find
          .ancestor(
            of: find.text('login in / sign up'),
            matching: find.byType(Column),
          )
          .first;
      final columnRect = tester.getRect(column);
      expect(columnRect.left, greaterThanOrEqualTo(0));
      expect(columnRect.right, lessThanOrEqualTo(410));
      expect(columnRect.top, greaterThanOrEqualTo(0));
      expect(columnRect.bottom, lessThanOrEqualTo(915));

      final buttonRect = tester.getRect(
        find.widgetWithText(FilledButton, 'login'),
      );
      expect(buttonRect.bottom, lessThanOrEqualTo(915));
    },
  );

  testWidgets(
    'F15 gradient covers bottom inset, nav bar transparent, bubbles glossed',
    (tester) async {
      await _pumpLoginScene(
        tester,
        padding: const EdgeInsets.only(top: 28, bottom: 34),
      );

      // 背景渐变必须铺满整屏（含底部系统区域），否则露出黑带。
      final background = find.byWidgetPredicate((widget) {
        final decoration = widget is Container ? widget.decoration : null;
        return decoration is BoxDecoration &&
            decoration.gradient is LinearGradient;
      });
      expect(background, findsOneWidget);
      final backgroundRect = tester.getRect(background);
      expect(backgroundRect.top, 0);
      expect(backgroundRect.bottom, 915);

      // 导航栏透明 + 关闭系统对比度 scrim，渐变才能透进底部系统区域。
      final annotation = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
        find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
      );
      expect(
        annotation.value.systemNavigationBarColor,
        const Color(0x00000000),
      );
      expect(annotation.value.systemNavigationBarContrastEnforced, isFalse);

      // P1-4：7 个深色气泡在 radial 底色上再叠内高光（左上白 → 右下深蓝）。
      final bubbles = find.byWidgetPredicate((widget) {
        final decoration = widget is Container ? widget.decoration : null;
        return decoration is BoxDecoration &&
            decoration.gradient is RadialGradient;
      });
      expect(bubbles, findsNWidgets(7));
      for (final element in bubbles.evaluate()) {
        final container = element.widget as Container;
        final foreground = container.foregroundDecoration;
        expect(foreground, isA<BoxDecoration>());
        expect((foreground as BoxDecoration).gradient, isA<LinearGradient>());
      }
    },
  );

  testWidgets('F15 light blob is centered with the bump overhanging left', (
    tester,
  ) async {
    await _pumpLoginScene(tester, brightness: Brightness.light);

    final blob = find.byWidgetPredicate((widget) {
      final decoration = widget is Container ? widget.decoration : null;
      return decoration is BoxDecoration &&
          decoration.color == AppColors.loginBlobViolet &&
          decoration.borderRadius != null;
    });
    expect(blob, findsOneWidget);
    expect(tester.getRect(blob).center.dx, 205);
  });

  // ---- F19：登录接线（真实契约 / 错误 / 恢复码 / 刷新 / 登出） ----

  testWidgets('server 401 shows the message and stays on the login page', (
    tester,
  ) async {
    final stub = _StubAuthService(
      const LoginResult(success: false, message: '手机号或密码错误'),
    );
    await _pumpLogin(tester, authService: stub);

    await _submitPhone(tester, '13800138000');

    expect(stub.loginCalls, 1);
    expect(find.text('手机号或密码错误'), findsOneWidget);
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.byType(AppShell), findsNothing);
  });

  testWidgets('password shorter than 6 bytes is rejected before any request', (
    tester,
  ) async {
    final stub = _StubAuthService(const LoginResult(success: true));
    await _pumpLogin(tester, authService: stub);

    await _submitCredentials(tester, '13800138000', '12345');

    final field = tester.widget<TextField>(find.byType(TextField).last);
    expect(field.decoration?.errorText, '密码长度需为 6-72 字节');
    expect(stub.loginCalls, 0);
    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets('new-account restoreCode is shown once before entering the app', (
    tester,
  ) async {
    const code = 'apple river cloud stone bright maple harbor silver';
    final stub = _StubAuthService(
      const LoginResult(
        success: true,
        user: User(id: '7', username: '13800138000', nickname: 'Max'),
        restoreCode: code,
      ),
    );
    await _pumpLogin(tester, authService: stub);

    await _submitPhone(tester, '13800138000');

    expect(find.text('请保存恢复码'), findsOneWidget);
    final shown = tester.widget<SelectableText>(
      find.byKey(const Key('restore-code')),
    );
    expect(shown.data, code);
    expect(find.byType(AppShell), findsNothing);

    await tester.tap(find.text('我已保存，进入 App'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(AppShell), findsOneWidget);
  });

  test(
    'HttpAuthService sends deviceId and persists tokens (not password)',
    () async {
      final kv = InMemoryKvStore();
      http.Request? loginRequest;
      final client = MockClient((request) async {
        if (request.url.path == '/api/v1/auth/login') {
          loginRequest = request;
          return _jsonResponse(
            200,
            _loginJson(restoreCode: 'apple river cloud stone'),
          );
        }
        return _jsonResponse(404, <String, Object?>{'detail': 'not found'});
      });
      final auth = HttpAuthService(
        client: client,
        kvStore: kv,
        baseUrl: 'http://test',
        deviceId: 'device-abc',
      );

      final result = await auth.login(
        phone: '13800138000',
        password: 'secret123',
      );

      expect(result.success, isTrue);
      expect(result.user?.username, '13800138000');
      expect(result.restoreCode, 'apple river cloud stone');
      expect(auth.cachedAccessToken, 'access-1');

      final body = jsonDecode(loginRequest!.body) as Map<String, dynamic>;
      expect(body['phone'], '13800138000');
      expect(body['deviceId'], 'device-abc');
      expect(body['deviceModel'], isNotEmpty);
      expect(body['appVersion'], isNotEmpty);
      expect(body['password'], 'secret123');

      final stored = kv.getString(KvStore.keyAuthSession);
      expect(stored, isNotNull);
      expect(stored, contains('access-1'));
      expect(stored, contains('refresh-1'));
      expect(stored, isNot(contains('secret123')));
    },
  );

  test('deviceId is generated once and reused on later logins', () async {
    final kv = InMemoryKvStore();
    final seenIds = <String>[];
    http.Client buildClient() => MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      seenIds.add(body['deviceId'] as String);
      return _jsonResponse(200, _loginJson());
    });

    final first = HttpAuthService(
      client: buildClient(),
      kvStore: kv,
      baseUrl: 'http://test',
    );
    await first.login(phone: '13800138000', password: 'secret123');
    final generated = kv.getString(KvStore.keyAuthDeviceId);
    expect(generated, isNotNull);
    expect(generated, isNotEmpty);
    expect(generated!.length, lessThanOrEqualTo(40));

    final second = HttpAuthService(
      client: buildClient(),
      kvStore: kv,
      baseUrl: 'http://test',
    );
    await second.login(phone: '13800138000', password: 'secret123');

    expect(seenIds, hasLength(2));
    expect(seenIds.first, generated);
    expect(seenIds.last, generated);
  });

  test('login 401 surfaces the server message and keeps no session', () async {
    final kv = InMemoryKvStore();
    final client = MockClient(
      (_) async => _jsonResponse(401, <String, Object?>{
        'error': <String, Object?>{
          'code': 'INVALID_CREDENTIALS',
          'message': '手机号或密码错误',
          'requestId': 'req-1',
        },
      }),
    );
    final auth = HttpAuthService(
      client: client,
      kvStore: kv,
      baseUrl: 'http://test',
    );

    final result = await auth.login(
      phone: '13800138000',
      password: 'secret123',
    );

    expect(result.success, isFalse);
    expect(result.message, '手机号或密码错误');
    expect(auth.cachedAccessToken, isNull);
    expect(kv.getString(KvStore.keyAuthSession), isNull);
  });

  test('live error envelope (409 device bound) is surfaced verbatim', () async {
    final client = MockClient(
      (_) async => _jsonResponse(409, <String, Object?>{
        'error': <String, Object?>{
          'code': 'DEVICE_BOUND',
          'message': '该设备已绑定其他账号',
          'requestId': 'req-2',
        },
      }),
    );
    final auth = HttpAuthService(
      client: client,
      kvStore: InMemoryKvStore(),
      baseUrl: 'http://test',
    );

    final result = await auth.login(
      phone: '13800138000',
      password: 'secret123',
    );

    expect(result.success, isFalse);
    expect(result.message, '该设备已绑定其他账号');
  });

  test('login 422 joins FastAPI validation messages', () async {
    final client = MockClient(
      (_) async => _jsonResponse(422, <String, Object?>{
        'detail': [
          <String, Object?>{'msg': '手机号格式不正确'},
          <String, Object?>{'msg': 'deviceId 不能为空且不超过 40 字符'},
        ],
      }),
    );
    final auth = HttpAuthService(
      client: client,
      kvStore: InMemoryKvStore(),
      baseUrl: 'http://test',
    );

    final result = await auth.login(
      phone: '12800138000',
      password: 'secret123',
    );

    expect(result.success, isFalse);
    expect(result.message, '手机号格式不正确；deviceId 不能为空且不超过 40 字符');
  });

  test('expired access token is refreshed before the request', () async {
    final kv = InMemoryKvStore();
    var refreshes = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/auth/login') {
        return _jsonResponse(200, _loginJson(expiresIn: 30));
      }
      if (request.url.path == '/api/v1/auth/refresh') {
        refreshes++;
        return _jsonResponse(
          200,
          _refreshJson(access: 'access-2', refresh: 'refresh-2'),
        );
      }
      return _jsonResponse(404, <String, Object?>{});
    });
    final auth = HttpAuthService(
      client: client,
      kvStore: kv,
      baseUrl: 'http://test',
    );
    await auth.login(phone: '13800138000', password: 'secret123');

    final token = await auth.accessToken();

    expect(refreshes, 1);
    expect(token, 'access-2');
    expect(auth.cachedAccessToken, 'access-2');
  });

  test('401 triggers one refresh and retries with the new token', () async {
    final kv = InMemoryKvStore();
    final authorization = <String?>[];
    final refreshBodies = <String>[];
    final client = MockClient((request) async {
      final path = request.url.path;
      if (path == '/api/v1/auth/login') {
        return _jsonResponse(200, _loginJson());
      }
      if (path == '/api/v1/auth/refresh') {
        refreshBodies.add(
          (jsonDecode(request.body) as Map<String, dynamic>)['refreshToken']
              as String,
        );
        return _jsonResponse(
          200,
          _refreshJson(access: 'access-2', refresh: 'refresh-2'),
        );
      }
      if (path == '/api/v1/practice/progress') {
        final header = request.headers['authorization'];
        authorization.add(header);
        if (header == 'Bearer access-1') {
          return _jsonResponse(401, <String, Object?>{'detail': '登录会话已失效'});
        }
        return _jsonResponse(200, <Object?>[]);
      }
      return _jsonResponse(404, <String, Object?>{});
    });
    final auth = HttpAuthService(
      client: client,
      kvStore: kv,
      baseUrl: 'http://test',
    );
    await auth.login(phone: '13800138000', password: 'secret123');
    final authed = AuthHttpClient(auth: auth, inner: client);

    final response = await authed.get(
      Uri.parse('http://test/api/v1/practice/progress'),
    );

    expect(response.statusCode, 200);
    expect(authorization, <String>['Bearer access-1', 'Bearer access-2']);
    expect(refreshBodies, <String>['refresh-1']);
    expect(auth.cachedAccessToken, 'access-2');
  });

  test('refresh 401 clears the session and notifies the app', () async {
    final kv = InMemoryKvStore();
    var expired = false;
    final client = MockClient((request) async {
      final path = request.url.path;
      if (path == '/api/v1/auth/login') {
        return _jsonResponse(200, _loginJson());
      }
      if (path == '/api/v1/auth/refresh') {
        return _jsonResponse(401, <String, Object?>{'detail': '登录会话已失效，请重新登录'});
      }
      return _jsonResponse(401, <String, Object?>{'detail': 'expired'});
    });
    final auth = HttpAuthService(
      client: client,
      kvStore: kv,
      baseUrl: 'http://test',
    );
    auth.onSessionExpired = () => expired = true;
    await auth.login(phone: '13800138000', password: 'secret123');
    final authed = AuthHttpClient(auth: auth, inner: client);

    final response = await authed.get(
      Uri.parse('http://test/api/v1/practice/progress'),
    );

    expect(response.statusCode, 401);
    expect(expired, isTrue);
    expect(auth.cachedAccessToken, isNull);
    expect(kv.getString(KvStore.keyAuthSession), isNull);
  });

  test('logout posts the bearer token and clears the local session', () async {
    final kv = InMemoryKvStore();
    String? logoutAuthorization;
    final client = MockClient((request) async {
      final path = request.url.path;
      if (path == '/api/v1/auth/login') {
        return _jsonResponse(200, _loginJson());
      }
      if (path == '/api/v1/auth/logout') {
        logoutAuthorization = request.headers['authorization'];
        return _jsonResponse(200, <String, Object?>{'success': true});
      }
      return _jsonResponse(404, <String, Object?>{});
    });
    final auth = HttpAuthService(
      client: client,
      kvStore: kv,
      baseUrl: 'http://test',
    );
    await auth.login(phone: '13800138000', password: 'secret123');

    await auth.logout();

    expect(logoutAuthorization, 'Bearer access-1');
    expect(auth.cachedAccessToken, isNull);
    expect(kv.getString(KvStore.keyAuthSession), isNull);
    expect(await auth.getCurrentUser(), isNull);
  });
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

Map<String, Object?> _loginJson({
  String access = 'access-1',
  String refresh = 'refresh-1',
  int expiresIn = 900,
  String? restoreCode,
}) {
  return <String, Object?>{
    'accessToken': access,
    'refreshToken': refresh,
    'tokenType': 'Bearer',
    'expiresIn': expiresIn,
    'user': <String, Object?>{'id': 7, 'nickname': 'Max', 'avatarUrl': null},
    'restoreCode': ?restoreCode,
  };
}

Map<String, Object?> _refreshJson({
  required String access,
  required String refresh,
}) {
  return <String, Object?>{
    'accessToken': access,
    'refreshToken': refresh,
    'tokenType': 'Bearer',
    'expiresIn': 900,
  };
}

class _StubAuthService extends MockAuthService {
  _StubAuthService(this.result);

  final LoginResult result;
  int loginCalls = 0;

  @override
  Future<LoginResult> login({
    required String phone,
    required String password,
  }) async {
    loginCalls++;
    return result;
  }
}

/// F15 专用画幅：~410dp 宽真机 + 可注入系统 inset / 深浅色。
Future<void> _pumpLoginScene(
  WidgetTester tester, {
  Brightness brightness = Brightness.dark,
  EdgeInsets padding = EdgeInsets.zero,
}) async {
  const size = Size(410, 915);
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: MediaQuery(
        data: MediaQueryData(size: size, padding: padding),
        child: const LoginPage(),
      ),
    ),
  );
  // 顶部图形无限动画，不能 pumpAndSettle，只推一帧。
  await tester.pump();
}
