import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/pages/toolbox/osi_page.dart';
import 'package:routepass/pages/toolbox/ping_page.dart';
import 'package:routepass/pages/toolbox/portscan_page.dart';
import 'package:routepass/pages/toolbox/subnet_page.dart';
import 'package:routepass/pages/toolbox/toolbox_home_page.dart';
import 'package:routepass/widgets/capsule_nav_bar.dart';

import 'test_helpers.dart';

/// 首页快捷入口也有同名文字，切 tab 必须把 finder 限定在胶囊导航里。
Finder _navTab(String label) =>
    find.descendant(of: find.byType(CapsuleNavBar), matching: find.text(label));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initTestServices();

  testWidgets('点子网卡进子网页，底栏隐藏，返回后最近使用出现', (tester) async {
    await loginToHome(tester);

    await tester.tap(_navTab('工具'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('子网计算器'));
    await tester.pumpAndSettle();
    expect(find.byType(SubnetPage), findsOneWidget);
    expect(find.byType(CapsuleNavBar), findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(ToolboxHomePage), findsOneWidget);
    expect(find.text('最近使用'), findsOneWidget);
    expect(find.text('子网计算器'), findsWidgets);
  });

  testWidgets('点 Ping 卡进 Ping 页', (tester) async {
    // GridView 懒构建：600 高视口下第 4 行起的卡不在树里，改用 1400 高视口。
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await loginToHome(tester);

    await tester.tap(_navTab('工具'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ping'));
    await tester.pumpAndSettle();
    expect(find.byType(PingPage), findsOneWidget);
    expect(find.byType(CapsuleNavBar), findsNothing);
  });

  testWidgets('点端口扫描卡进页弹合规确认，取消后不扫描', (tester) async {
    // GridView 懒构建：600 高视口下第 4 行起的卡不在树里，改用 1400 高视口。
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await loginToHome(tester);

    await tester.tap(_navTab('工具'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('端口扫描'));
    await tester.pumpAndSettle();
    expect(find.byType(PortScanPage), findsOneWidget);
    expect(find.text('合规确认'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(find.text('合规确认'), findsNothing);
    // 取消后页面停留、表单仍在（占位只在点开始后出现）、未开始扫描。
    expect(find.byType(PortScanPage), findsOneWidget);
    expect(find.text('扫描端口'), findsOneWidget);
    expect(find.text('扫描中…'), findsNothing);
  });

  testWidgets('端口扫描确认一次后再次进入不再弹确认', (tester) async {
    // GridView 懒构建：600 高视口下第 4 行起的卡不在树里，改用 1400 高视口。
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await loginToHome(tester);

    await tester.tap(_navTab('工具'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('端口扫描'));
    await tester.pumpAndSettle();
    expect(find.byType(PortScanPage), findsOneWidget);
    // 之前用例若已确认则直接进页；否则先确认一次。
    if (find.text('合规确认').tryEvaluate()) {
      await tester.tap(find.widgetWithText(FilledButton, '我已知晓并确认'));
      await tester.pumpAndSettle();
    }
    expect(find.text('合规确认'), findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('端口扫描'));
    await tester.pumpAndSettle();
    expect(find.byType(PortScanPage), findsOneWidget);
    expect(find.text('合规确认'), findsNothing);
  });

  testWidgets('点 Ping 卡进页，开始后显示待接本地服务占位', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await loginToHome(tester);

    await tester.tap(_navTab('工具'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ping'));
    await tester.pumpAndSettle();
    expect(find.byType(PingPage), findsOneWidget);
    // 空目标点开始只报“请输入目标主机”，先填目标再开始。
    await tester.enterText(find.byType(TextField).at(0), '192.168.1.1');
    await tester.tap(find.widgetWithText(FilledButton, '开始'));
    await tester.pumpAndSettle();
    expect(find.textContaining('待接本地服务'), findsOneWidget);
  });

  testWidgets('点 OSI 卡进对照页', (tester) async {
    // GridView 懒构建：600 高视口下第 4 行起的卡不在树里，改用 1400 高视口。
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await loginToHome(tester);

    await tester.tap(_navTab('工具'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OSI/TCP-IP 对照'));
    await tester.pumpAndSettle();
    expect(find.byType(OsiPage), findsOneWidget);
  });

  testWidgets('首页子网计算器方块进子网页', (tester) async {
    await loginToHome(tester);

    await tester.ensureVisible(find.text('子网计算器'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('子网计算器'));
    await tester.pumpAndSettle();
    expect(find.byType(SubnetPage), findsOneWidget);
    expect(find.byType(CapsuleNavBar), findsNothing);
  });
}
