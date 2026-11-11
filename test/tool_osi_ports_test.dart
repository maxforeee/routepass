import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/pages/toolbox/osi_page.dart';
import 'package:routepass/pages/toolbox/ports_page.dart';

void main() {
  testWidgets('OSI 页显示七层与 TCP/IP 映射', (tester) async {
    // ListView 懒构建：600 高视口下第 4 层起不在树里，改用 1400 高视口。
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(const MaterialApp(home: OsiPage()));
    await tester.pumpAndSettle();
    expect(find.text('第 4 层 · 传输层'), findsOneWidget);
    expect(find.text('协议：TCP、UDP'), findsOneWidget);
    expect(find.text('第 3 层 · 网络层'), findsOneWidget);
    expect(find.text('网际层'), findsOneWidget);
    expect(find.text('OSI 第 3 层'), findsOneWidget);
  });

  testWidgets('OSI 搜索 DNS 只剩应用层', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: OsiPage()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'DNS');
    await tester.pumpAndSettle();
    expect(find.text('第 7 层 · 应用层'), findsOneWidget);
    expect(find.text('第 4 层 · 传输层'), findsNothing);
  });

  testWidgets('端口页显示常用端口', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PortsPage()));
    await tester.pumpAndSettle();
    // 首屏只建到约第 7 行，深处条目（443 等）由搜索用例覆盖。
    expect(find.text('53'), findsOneWidget);
    expect(find.text('DNS'), findsOneWidget);
    expect(find.text('22'), findsOneWidget);
    expect(find.text('SSH'), findsOneWidget);
  });

  testWidgets('端口搜索 3389 只剩 RDP', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PortsPage()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '3389');
    await tester.pumpAndSettle();
    // '3389' 同时是搜索框里的文字，用 ListTile 限定只找结果行。
    expect(
      find.descendant(
        of: find.byType(ListTile),
        matching: find.text('3389'),
      ),
      findsOneWidget,
    );
    expect(find.text('RDP'), findsOneWidget);
    expect(find.text('HTTPS'), findsNothing);
  });
}
