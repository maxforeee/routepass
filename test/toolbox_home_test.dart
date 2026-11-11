import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/core/kv_store.dart';
import 'package:routepass/core/service_locator.dart';
import 'package:routepass/pages/toolbox/toolbox_home_page.dart';

void main() {
  testWidgets('工具箱首页显示 10 张工具卡', (tester) async {
    // GridView 懒构建：600 高视口下第 5 行的卡不在树里，改用 1400 高视口。
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(const MaterialApp(home: ToolboxHomePage()));
    await tester.pumpAndSettle();
    for (final name in [
      '子网划分',
      'IP/进制转换',
      'CIDR↔掩码',
      'VLSM 规划',
      '命令速查',
      '单位换算',
      'OSI/TCP-IP 对照',
      '端口速查',
      'Ping',
      '端口扫描',
    ]) {
      expect(find.text(name), findsOneWidget);
    }
  });

  testWidgets('搜索“子网”只剩子网划分', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ToolboxHomePage()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '子网');
    await tester.pumpAndSettle();
    // “子网”命中子网划分（名）与 VLSM 规划（描述含“子网”），其余被滤掉。
    expect(find.text('子网划分'), findsOneWidget);
    expect(find.text('VLSM 规划'), findsOneWidget);
    expect(find.text('Ping'), findsNothing);
  });

  testWidgets('分类“对照”只剩 OSI 卡', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ToolboxHomePage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('对照'));
    await tester.pumpAndSettle();
    expect(find.text('OSI/TCP-IP 对照'), findsOneWidget);
    expect(find.text('子网划分'), findsNothing);
    expect(find.text('命令速查'), findsNothing);
  });

  testWidgets('最近使用行显示 kv 里的工具', (tester) async {
    ServiceLocator.kvStore.setStringList(KvStore.keyToolboxRecent, [
      'ping',
      'subnet',
    ]);
    await tester.pumpWidget(const MaterialApp(home: ToolboxHomePage()));
    await tester.pumpAndSettle();
    expect(find.text('最近使用'), findsOneWidget);
    expect(find.text('Ping'), findsWidgets);
    expect(find.text('子网划分'), findsWidgets);
  });
}
