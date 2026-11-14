import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/core/service_locator.dart';
import 'package:routepass/core/theme.dart';
import 'package:routepass/pages/base/login_page.dart';
import 'package:routepass/pages/shell/app_shell.dart';
import 'package:routepass/router/app_router.dart';
import 'package:routepass/services/mock/mock_auth_service.dart';

import 'test_helpers.dart';

Future<void> _pumpLogin(WidgetTester tester) async {
  // 1:1 参考稿的 390x844 画幅，保证两个胶囊与 login 按钮都在视口内。
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: const LoginPage(),
      onGenerateRoute: AppRouter.onGenerateRoute,
    ),
  );
  // 顶部图形无限动画，不能 pumpAndSettle，只推一帧。
  await tester.pump();
}

Future<void> _submitPhone(WidgetTester tester, String phone) async {
  final fields = find.byType(TextField);
  await tester.enterText(fields.at(0), phone);
  await tester.enterText(fields.at(1), 'Demo1234');
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
        username: '13900139000',
        password: 'Demo1234',
      );
      await service.logout();

      final loggedIn = await service.login(
        username: '13900139000',
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
