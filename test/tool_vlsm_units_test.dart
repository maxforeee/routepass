import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/pages/toolbox/units_page.dart';
import 'package:routepass/pages/toolbox/vlsm_page.dart';

import 'test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initTestServices();

  testWidgets('VLSM：192.168.1.0/24 拆 50/20/10', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: VlsmPage()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '192.168.1.0/24');
    await tester.enterText(find.byType(TextField).at(1), '50, 20, 10');
    await tester.tap(find.widgetWithText(FilledButton, '规划'));
    await tester.pumpAndSettle();
    expect(find.text('192.168.1.0/26'), findsOneWidget);
    expect(find.text('可用主机 62 台'), findsOneWidget);
    expect(find.text('192.168.1.64/27'), findsOneWidget);
    expect(find.text('可用主机 30 台'), findsOneWidget);
    expect(find.text('192.168.1.96/28'), findsOneWidget);
    expect(find.text('可用主机 14 台'), findsOneWidget);
  });

  testWidgets('VLSM：需求超出母网容量显示错误', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: VlsmPage()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '192.168.1.0/30');
    await tester.enterText(find.byType(TextField).at(1), '10');
    await tester.tap(find.widgetWithText(FilledButton, '规划'));
    await tester.pumpAndSettle();
    expect(find.textContaining('超出母网容量'), findsOneWidget);
  });

  testWidgets('单位换算：1 Gbps = 1000 Mbps', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: UnitsPage()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '1');
    await tester.tap(find.widgetWithText(FilledButton, '换算'));
    await tester.pumpAndSettle();
    expect(find.text('1 Gbps = 1000 Mbps'), findsOneWidget);
  });

  testWidgets('单位换算：1 GB = 1024 MB', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: UnitsPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('容量'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '1');
    await tester.tap(find.widgetWithText(FilledButton, '换算'));
    await tester.pumpAndSettle();
    expect(find.text('1 GB = 1024 MB'), findsOneWidget);
  });

  testWidgets('单位换算：1024 KB = 1 MB', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: UnitsPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('容量'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('KB').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '1024');
    await tester.tap(find.widgetWithText(FilledButton, '换算'));
    await tester.pumpAndSettle();
    expect(find.text('1024 KB = 1 MB'), findsOneWidget);
  });
}
