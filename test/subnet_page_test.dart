import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/pages/toolbox/subnet_page.dart';

import 'test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initTestServices();

  testWidgets('计算 192.168.1.10/24 出结果表', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SubnetPage()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '192.168.1.10');
    await tester.enterText(find.byType(TextField).at(1), '24');
    await tester.tap(find.widgetWithText(FilledButton, '计算'));
    await tester.pumpAndSettle();
    expect(find.text('192.168.1.0'), findsOneWidget);
    expect(find.text('192.168.1.255'), findsOneWidget);
    expect(find.text('192.168.1.1 - 192.168.1.254'), findsOneWidget);
    expect(find.text('254'), findsOneWidget);
    expect(find.text('255.255.255.0'), findsOneWidget);
  });

  testWidgets('掩码模式计算', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SubnetPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('点分掩码'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '192.168.1.10');
    await tester.enterText(find.byType(TextField).at(1), '255.255.255.0');
    await tester.tap(find.widgetWithText(FilledButton, '计算'));
    await tester.pumpAndSettle();
    expect(find.text('192.168.1.0'), findsOneWidget);
    expect(find.text('254'), findsOneWidget);
  });

  testWidgets('非法 IP 显示错误', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SubnetPage()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '999.1.1.1');
    await tester.tap(find.widgetWithText(FilledButton, '计算'));
    await tester.pumpAndSettle();
    expect(find.textContaining('IP 格式错误'), findsOneWidget);
  });

  testWidgets('复制按钮显示已复制提示', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SubnetPage()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '192.168.1.10');
    await tester.tap(find.widgetWithText(FilledButton, '计算'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.copy).first);
    await tester.pumpAndSettle();
    expect(find.text('已复制'), findsOneWidget);
  });
}
