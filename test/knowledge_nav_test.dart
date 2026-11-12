import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/pages/knowledge/knowledge_detail_page.dart';
import 'package:routepass/pages/knowledge/knowledge_home_page.dart';
import 'package:routepass/pages/knowledge/knowledge_search_page.dart';
import 'package:routepass/widgets/capsule_nav_bar.dart';

import 'test_helpers.dart';

/// 首页快捷入口也有同名文字，切 tab 必须把 finder 限定在胶囊导航里。
Finder _navTab(String label) =>
    find.descendant(of: find.byType(CapsuleNavBar), matching: find.text(label));

/// 从知识库列表进详情页（点行展开面板，再点“查看详情”）。
Future<void> _openDetailFromList(WidgetTester tester) async {
  await tester.tap(_navTab('知识'));
  await tester.pumpAndSettle();
  // 展开态经 kv 持久化，跨用例可能仍是展开的；此时再点行会收起，故只在未展开时点行。
  if (find.text('查看详情').evaluate().isEmpty) {
    await tester.tap(find.text('样例知识点：VLAN 是什么'));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.text('查看详情'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initTestServices();

  testWidgets('点底栏知识库进列表页', (tester) async {
    await loginToHome(tester);

    await tester.tap(_navTab('知识'));
    await tester.pumpAndSettle();
    expect(find.byType(KnowledgeHomePage), findsOneWidget);
    expect(find.text('样例章节：VLAN 基础'), findsOneWidget);
  });

  testWidgets('点知识点行展开面板，点查看详情进详情页', (tester) async {
    await loginToHome(tester);
    await _openDetailFromList(tester);

    expect(find.byType(KnowledgeDetailPage), findsOneWidget);
    expect(find.text('常用命令'), findsOneWidget);
    expect(find.text('display vlan'), findsOneWidget);
  });

  testWidgets('详情页返回回列表页', (tester) async {
    await loginToHome(tester);
    await _openDetailFromList(tester);

    await tester.tap(find.text('返回知识库'));
    await tester.pumpAndSettle();
    expect(find.text('样例章节：VLAN 基础'), findsOneWidget);
  });

  testWidgets('列表页搜索框提交进搜索页', (tester) async {
    await loginToHome(tester);

    await tester.tap(_navTab('知识'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'VLAN');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.byType(KnowledgeSearchPage), findsOneWidget);
    expect(find.text('样例知识点：VLAN 是什么'), findsOneWidget);
  });

  // G1c: 首页“今日知识点”卡片已移除，改为从知识库列表进详情页。
  testWidgets('知识库列表进知识点详情页', (tester) async {
    await loginToHome(tester);
    await _openDetailFromList(tester);

    expect(find.byType(KnowledgeDetailPage), findsOneWidget);
    expect(find.text('返回知识库'), findsOneWidget);
  });

  // G1c: 首页“章节速览”卡片已移除，直接点底栏知识 tab 进列表页。
  testWidgets('点底栏知识进列表页', (tester) async {
    await loginToHome(tester);

    await tester.tap(_navTab('知识'));
    await tester.pumpAndSettle();
    expect(find.byType(KnowledgeHomePage), findsOneWidget);
    expect(find.text('样例章节：VLAN 基础'), findsOneWidget);
  });
}
