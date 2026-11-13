import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/app.dart';

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
    // 登录页顶部图形无限动画，不能 pumpAndSettle：显式推帧走完转场。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // 新登录页：标题 + 两个占位胶囊 + 半宽 login 按钮。
    expect(find.text('login in / sign up'), findsOneWidget);
    expect(find.text('phone number'), findsOneWidget);
    expect(find.text('password'), findsOneWidget);
    expect(find.text('login'), findsOneWidget);

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '13800138000');
    await tester.enterText(fields.at(1), 'Demo1234');
    // 默认 800x600 视口下 login 按钮在折叠线以下，先滚进视口再点。
    await tester.ensureVisible(find.text('login'));
    await tester.pump();
    await tester.tap(find.text('login'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
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
}
