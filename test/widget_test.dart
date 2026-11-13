import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/app.dart';
import 'package:routepass/core/service_locator.dart';

import 'test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initTestServices();

  testWidgets('启动判定进登录页；登录后进首页外壳与 4 个 tab', (tester) async {
    await tester.pumpWidget(const RoutePassApp());
    // splash 的异步判定（getCurrentUser + checkUpgrade）+ 约 2 秒停留：
    // pumpAndSettle 不等没有帧调度的 dwell 定时器，需显式把假时间推过 2 秒。
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    // 登录页（已无 AppBar）：'登录 / 注册' 出现在登录按钮上，用 findsWidgets。
    expect(find.text('登录 / 注册'), findsWidgets);

    await tester.enterText(
      find.widgetWithText(TextField, '请输入 11 位手机号码'),
      '13800138000',
    );
    await tester.enterText(
      find.widgetWithText(TextField, '8–32 位，含字母与数字'),
      'Demo1234',
    );
    await tester.tap(find.widgetWithText(FilledButton, '登录 / 注册'));
    await tester.pumpAndSettle();
    // 让 Snackbar 的 4 秒自动消失 Timer 走完，避免测试结束时仍挂定时器。
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    // 首页内容 + 底栏 4 个 tab 标签。
    expect(find.textContaining('好！'), findsOneWidget);
    expect(find.text('Max'), findsOneWidget);
    expect(find.text('首页'), findsWidgets);
    expect(find.text('题库'), findsWidgets);
    expect(find.text('知识'), findsWidgets);
    expect(find.text('工具'), findsWidgets);
  });

  testWidgets('登录页「先看看知识库 / 打开工具箱」直达对应 tab', (tester) async {
    // 前一个用例已登录（MockAuthService 是进程内单例）；先登出，启动页才会停在登录页。
    await ServiceLocator.authService.logout();
    await tester.pumpWidget(const RoutePassApp());
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    // 「先看看知识库」→ 知识库 tab。
    await tester.tap(find.text('先看看知识库'));
    await tester.pumpAndSettle();
    expect(find.text('知识库'), findsWidgets);

    // 全新 App 再走一次登录页，验证「打开工具箱」→ 工具箱 tab。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(const RoutePassApp());
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开工具箱'));
    await tester.pumpAndSettle();
    expect(find.text('工具箱'), findsWidgets);
  });
}
