import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/core/kv_store.dart';
import 'package:routepass/core/service_locator.dart';
import 'package:routepass/pages/toolbox/toolbox_home_page.dart';

void main() {
  testWidgets('工具箱首页显示 10 张工具卡', (tester) async {
    // 高视口保证整页（页头 + 5 行卡片 + 最近使用行）都在树里。
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(const MaterialApp(home: ToolboxHomePage()));
    await tester.pumpAndSettle();
    for (final name in [
      '子网计算器',
      'IP/进制转换',
      'CIDR ↔ 掩码',
      'VLSM 规划',
      '单位换算',
      'OSI/TCP-IP 对照',
      '端口速查',
      '命令速查',
      'Ping',
      '端口扫描',
    ]) {
      expect(find.text(name), findsOneWidget);
    }
  });

  testWidgets('最近使用行显示 kv 里的工具', (tester) async {
    ServiceLocator.kvStore.setStringList(KvStore.keyToolboxRecent, [
      'ping',
      'subnet',
    ]);
    await tester.pumpWidget(const MaterialApp(home: ToolboxHomePage()));
    await tester.pumpAndSettle();
    expect(find.text('最近使用'), findsOneWidget);
    expect(find.text('Ping · 子网计算器'), findsOneWidget);
  });
}
