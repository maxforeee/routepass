import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/pages/toolbox/cli_page.dart';
import 'package:routepass/pages/toolbox/ping_page.dart';
import 'package:routepass/pages/toolbox/portscan_page.dart';

import 'test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initTestServices();

  testWidgets('命令速查显示 4 条样例命令', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: CliPage()));
    await tester.pumpAndSettle();
    expect(find.text('display vlan'), findsOneWidget);
    expect(find.text('vlan 10'), findsOneWidget);
    expect(find.text('display ospf peer'), findsOneWidget);
    expect(find.text('ip address 192.168.1.1 24'), findsOneWidget);
  });

  testWidgets('命令速查搜索 ospf 只剩 1 条', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: CliPage()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'ospf');
    await tester.pumpAndSettle();
    expect(find.text('display ospf peer'), findsOneWidget);
    expect(find.text('display vlan'), findsNothing);
  });

  testWidgets('点命令卡复制出已复制提示', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: CliPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('display vlan'));
    await tester.pumpAndSettle();
    expect(find.text('已复制'), findsOneWidget);
  });

  testWidgets('Ping 开始后显示待接本地服务', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PingPage()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '192.168.1.1');
    await tester.tap(find.widgetWithText(FilledButton, '开始'));
    await tester.pumpAndSettle();
    expect(find.textContaining('待接本地服务'), findsWidgets);
  });

  testWidgets('端口扫描：未确认不能开始，确认后开始显示占位', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PortScanPage()));
    await tester.pumpAndSettle();
    // 进页弹合规确认。
    expect(find.text('合规确认'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(find.text('合规确认'), findsNothing);
    // 未确认时点开始，再弹确认。
    await tester.tap(find.widgetWithText(FilledButton, '开始'));
    await tester.pumpAndSettle();
    expect(find.text('合规确认'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '我已知晓并确认'));
    await tester.pumpAndSettle();
    expect(find.text('合规确认'), findsNothing);
    // 确认后点开始，显示占位。
    await tester.enterText(find.byType(TextField), '192.168.1.1');
    await tester.tap(find.widgetWithText(FilledButton, '开始'));
    await tester.pumpAndSettle();
    expect(find.textContaining('待接本地服务'), findsOneWidget);
  });
}
