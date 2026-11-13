import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/core/service_locator.dart';
import 'package:routepass/pages/base/login_page.dart';
import 'package:routepass/pages/shell/app_shell.dart';
import 'package:routepass/router/app_router.dart';
import 'package:routepass/services/mock/mock_auth_service.dart';

import 'test_helpers.dart';

Future<void> _pumpLogin(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: const LoginPage(),
      onGenerateRoute: AppRouter.onGenerateRoute,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _submitPhone(WidgetTester tester, String phone) async {
  final fields = find.byType(TextField);
  await tester.enterText(fields.at(0), phone);
  await tester.enterText(fields.at(1), 'Demo1234');
  await tester.tap(find.widgetWithText(FilledButton, '登录 / 注册'));
  await tester.pumpAndSettle();
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

    expect(find.widgetWithText(FilledButton, '登录 / 注册'), findsOneWidget);
    expect(find.text('注册'), findsNothing);
    expect(find.text('还没有账号？'), findsNothing);
    expect(find.widgetWithText(TextButton, '注册'), findsNothing);
    expect(find.text('手机号码'), findsOneWidget);
    expect(find.text('请输入 11 位手机号码'), findsOneWidget);

    final fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .toList();
    expect(fields, hasLength(2));
    expect(fields.first.keyboardType, TextInputType.phone);
    for (final field in fields) {
      expect(field.decoration?.labelText, isNull);
      expect(field.decoration?.floatingLabelStyle, isNull);
    }
  });
}
