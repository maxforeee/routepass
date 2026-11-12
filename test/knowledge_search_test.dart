import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/pages/knowledge/knowledge_search_page.dart';

import 'test_helpers.dart';

Future<void> _pumpSearch(
  WidgetTester tester, [
  Map<String, Object?> args = const <String, Object?>{},
]) async {
  await tester.pumpWidget(MaterialApp(home: KnowledgeSearchPage(args: args)));
  await tester.pumpAndSettle();
}

/// 输入关键词，等防抖 300ms 走完并结算。
Future<void> _search(WidgetTester tester, String keyword) async {
  await tester.enterText(find.byType(TextField), keyword);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initTestServices();

  testWidgets('空查询显示提示', (tester) async {
    await _pumpSearch(tester);

    expect(find.text('输入关键词搜索知识点与题目'), findsOneWidget);
    expect(find.text('知识点'), findsNothing);
    expect(find.text('题目'), findsNothing);
  });

  testWidgets('输入 VLAN：知识点区有结果，题目区无结果', (tester) async {
    await _pumpSearch(tester);

    await _search(tester, 'VLAN');
    expect(find.text('知识点'), findsOneWidget);
    expect(find.text('样例知识点：VLAN 是什么'), findsOneWidget);
    expect(find.text('题目'), findsNothing);
  });

  testWidgets('输入 样例：两区都有结果', (tester) async {
    await _pumpSearch(tester);

    await _search(tester, '样例');
    expect(find.text('知识点'), findsOneWidget);
    expect(find.text('题目'), findsOneWidget);
    expect(find.text('样例知识点：子网掩码'), findsOneWidget);
    expect(find.textContaining('样例题'), findsWidgets);
  });

  testWidgets('无结果显示空态', (tester) async {
    await _pumpSearch(tester);

    await _search(tester, '不存在的关键词XYZ');
    expect(find.text('没有找到相关内容'), findsOneWidget);
  });

  testWidgets('初始 query 直接搜', (tester) async {
    await _pumpSearch(tester, const <String, Object?>{'query': '子网'});

    expect(find.text('样例知识点：子网掩码'), findsOneWidget);
    expect(find.text('题目'), findsOneWidget);
  });
}
