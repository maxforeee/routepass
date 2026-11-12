import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/pages/bank/module_list_page.dart';
import 'package:routepass/pages/knowledge/knowledge_home_page.dart';
import 'package:routepass/pages/toolbox/toolbox_home_page.dart';
import 'package:routepass/widgets/capsule_nav_bar.dart';

import 'test_helpers.dart';

/// 首页快捷入口也有同名文字，切 tab 必须把 finder 限定在胶囊导航里。
Finder _navTab(String label) =>
    find.descendant(of: find.byType(CapsuleNavBar), matching: find.text(label));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initTestServices();

  testWidgets('tab 切换：知识与工具均已装配，切回首页正常', (tester) async {
    await loginToHome(tester);

    // 4 个 tab 标签都在。
    expect(_navTab('首页'), findsOneWidget);
    expect(_navTab('题库'), findsOneWidget);
    expect(_navTab('知识'), findsOneWidget);
    expect(_navTab('工具'), findsOneWidget);

    await tester.tap(_navTab('知识'));
    await tester.pumpAndSettle();
    expect(find.byType(KnowledgeHomePage), findsOneWidget);
    expect(find.text('样例章节：VLAN 基础'), findsOneWidget);
    expect(find.textContaining('暂未开放'), findsNothing);

    await tester.tap(_navTab('工具'));
    await tester.pumpAndSettle();
    expect(find.byType(ToolboxHomePage), findsOneWidget);
    expect(find.text('子网计算器'), findsOneWidget);
    expect(find.textContaining('暂未开放'), findsNothing);

    await tester.tap(_navTab('首页'));
    await tester.pumpAndSettle();
    expect(find.textContaining('好！'), findsOneWidget);
    expect(find.text('Max'), findsOneWidget);
  });

  testWidgets('题库 tab 已装配：进题库页，不再显示“暂未开放”', (tester) async {
    await loginToHome(tester);

    await tester.tap(_navTab('题库'));
    await tester.pumpAndSettle();
    expect(find.byType(BankModuleListPage), findsOneWidget);
    expect(find.text('100 题套卷'), findsOneWidget);
    expect(find.textContaining('暂未开放'), findsNothing);
  });
}
