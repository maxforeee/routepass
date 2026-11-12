import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/pages/knowledge/knowledge_home_page.dart';

import 'test_helpers.dart';

Future<void> _pumpPage(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: KnowledgeHomePage()));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initTestServices();

  testWidgets('加载章节与小节', (tester) async {
    await _pumpPage(tester);

    expect(find.text('样例章节：VLAN 基础'), findsOneWidget);
    expect(find.text('样例小节：VLAN 概念'), findsOneWidget);
    expect(find.text('样例章节：子网划分基础'), findsOneWidget);
    // 每条知识点行右侧各显示“已掌握 0/1”。
    expect(find.text('已掌握 0/1'), findsNWidgets(2));
  });

  testWidgets('点小节折叠/展开知识点行，点行展开面板', (tester) async {
    await _pumpPage(tester);

    // 默认展开：知识点行可见。
    expect(find.text('样例知识点：VLAN 是什么'), findsOneWidget);
    // 点小节 header 折叠，行消失；再点展开，行回来。
    await tester.tap(find.text('样例小节：VLAN 概念'));
    await tester.pumpAndSettle();
    expect(find.text('样例知识点：VLAN 是什么'), findsNothing);
    await tester.tap(find.text('样例小节：VLAN 概念'));
    await tester.pumpAndSettle();
    expect(find.text('样例知识点：VLAN 是什么'), findsOneWidget);
    // 点行展开面板，摘要出现。
    await tester.tap(find.text('样例知识点：VLAN 是什么'));
    await tester.pumpAndSettle();
    expect(find.text('这是一条样例知识点摘要，仅用于界面展示。'), findsOneWidget);
    expect(find.text('练一练'), findsOneWidget);
    expect(find.text('查看详情'), findsOneWidget);
    // 再点行收起面板。
    await tester.tap(find.text('样例知识点：VLAN 是什么'));
    await tester.pumpAndSettle();
    expect(find.text('这是一条样例知识点摘要，仅用于界面展示。'), findsNothing);
  });

  testWidgets('掌握切换更新进度', (tester) async {
    await _pumpPage(tester);

    await tester.tap(find.byIcon(Icons.radio_button_unchecked).first);
    await tester.pumpAndSettle();
    expect(find.text('已掌握 1/1'), findsOneWidget);
    // 再点已掌握的 icon 取消。
    await tester.tap(find.byIcon(Icons.check_circle).first);
    await tester.pumpAndSettle();
    expect(find.text('已掌握 0/1'), findsNWidgets(2));
  });

  testWidgets('掌握态重建后仍保留（kv 持久化）', (tester) async {
    await _pumpPage(tester);

    await tester.tap(find.byIcon(Icons.radio_button_unchecked).first);
    await tester.pumpAndSettle();
    expect(find.text('已掌握 1/1'), findsOneWidget);
    // 重建页面：新 state 从 kv 重读掌握态。
    await _pumpPage(tester);
    expect(find.text('已掌握 1/1'), findsOneWidget);
    // 清理：取消掌握，避免影响后续用例。
    await tester.tap(find.byIcon(Icons.check_circle).first);
    await tester.pumpAndSettle();
    expect(find.text('已掌握 0/1'), findsNWidgets(2));
  });

  testWidgets('搜索过滤：只剩命中点，清空恢复', (tester) async {
    await _pumpPage(tester);

    await tester.enterText(find.byType(TextField), '子网');
    await tester.pumpAndSettle();
    expect(find.text('样例知识点：子网掩码'), findsOneWidget);
    expect(find.text('样例知识点：VLAN 是什么'), findsNothing);
    expect(find.text('样例章节：VLAN 基础'), findsNothing);
    // 清空恢复。
    await tester.tap(find.byIcon(Icons.clear));
    await tester.pumpAndSettle();
    expect(find.text('样例知识点：VLAN 是什么'), findsOneWidget);
    expect(find.text('样例知识点：子网掩码'), findsOneWidget);
  });

  testWidgets('展开态持久化：重建页面后面板仍展开', (tester) async {
    await _pumpPage(tester);

    await tester.tap(find.text('样例知识点：VLAN 是什么'));
    await tester.pumpAndSettle();
    expect(find.text('这是一条样例知识点摘要，仅用于界面展示。'), findsOneWidget);
    // 重建页面（kv 里的展开态应恢复）。
    await _pumpPage(tester);
    expect(find.text('这是一条样例知识点摘要，仅用于界面展示。'), findsOneWidget);
  });
}
