import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/core/theme.dart';
import 'package:routepass/pages/bank/module_list_page.dart';
import 'package:routepass/pages/home/home_content.dart';
import 'package:routepass/pages/knowledge/knowledge_home_page.dart';
import 'package:routepass/pages/toolbox/toolbox_home_page.dart';
import 'package:routepass/widgets/account_sheet.dart';
import 'package:routepass/widgets/capsule_nav_bar.dart';
import 'package:routepass/widgets/user_avatar.dart';

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

  // Q1 只隐藏做题页；四个一级页面保持悬浮胶囊导航。
  testWidgets('四个一级页面都保留胶囊导航', (tester) async {
    await loginToHome(tester);
    expect(find.byType(CapsuleNavBar), findsOneWidget);

    for (final label in <String>['题库', '知识', '工具', '首页']) {
      await tester.tap(_navTab(label));
      await tester.pumpAndSettle();
      expect(
        find.byType(CapsuleNavBar),
        findsOneWidget,
        reason: '$label 一级页面应保留导航',
      );
    }
  });

  testWidgets('浮动胶囊导航：extendBody + Stack/Positioned 底部居中', (tester) async {
    await loginToHome(tester);

    // 壳：extendBody，无底部导航条（胶囊是浮动盖住的，非底部导航条）。
    // 4 个 tab 页各有自己的 Scaffold，壳的取“胶囊导航祖先”那一个。
    final scaffoldFinder = find.ancestor(
      of: find.byType(CapsuleNavBar),
      matching: find.byType(Scaffold),
    );
    expect(scaffoldFinder, findsOneWidget);
    final scaffold = tester.widget<Scaffold>(scaffoldFinder);
    expect(scaffold.extendBody, isTrue);
    expect(scaffold.bottomNavigationBar, isNull);

    // 胶囊导航在 Shell 的 Stack / Positioned 覆盖层里，贴屏幕底、水平居中。
    final navFinder = find.byType(CapsuleNavBar);
    expect(navFinder, findsOneWidget);

    final positionedFinder = find.ancestor(
      of: navFinder,
      matching: find.byType(Positioned),
    );
    expect(positionedFinder, findsOneWidget);
    final positioned = tester.widget<Positioned>(positionedFinder);
    expect(positioned.left, equals(0.0));
    expect(positioned.right, equals(0.0));
    // v0.2.4 用户反馈：胶囊整体上移 8px。
    expect(positioned.bottom, equals(AppSpacing.xs));
    expect(positioned.bottom, equals(8.0));

    // 胶囊在 Stack 里的 Positioned 中（盖在内容上方，非底部导航条）。
    expect(
      find.ancestor(of: positionedFinder, matching: find.byType(Stack)),
      findsOneWidget,
    );

    final navRect = tester.getRect(find.byType(CapsuleNavBar));
    final size = tester.getSize(scaffoldFinder);
    // 胶囊比屏幕窄（两侧留白）。
    expect(navRect.left, greaterThan(0.0));
    expect(navRect.right, lessThan(size.width));
    // 胶囊自带 12px 底部内边距 + 整体上移 8px：可见胶囊体浮在屏幕底上方 20px，
    // 而 getRect(CapsuleNavBar) 取到的是含内边距的外层 Padding。
    // 条目高亮底是 AnimatedContainer（同为 Container），胶囊体在树中排最前，取 .first。
    final capsuleRect = tester.getRect(
      find.descendant(of: navFinder, matching: find.byType(Container)).first,
    );
    expect(
      size.height - capsuleRect.bottom,
      equals(AppSpacing.sm + AppSpacing.xs),
    );

    // 首页列表顶部在胶囊顶部之上（内容可滚到胶囊下面）。
    final listFinder = find
        .descendant(
          of: find.byType(HomeContentPage),
          matching: find.byType(ListView),
        )
        .first;
    expect(listFinder, findsOneWidget);
    expect(tester.getRect(listFinder).top, lessThan(navRect.top));

    // 列表底部留白至少 homeBottomPad，底部条目不会被胶囊盖住。
    final listPadding =
        (tester.widget<ListView>(listFinder)).padding as EdgeInsets;
    expect(listPadding.bottom, greaterThanOrEqualTo(AppSizes.homeBottomPad));
  });

  testWidgets('G1 头像面板打开时隐藏胶囊导航，关闭后恢复', (tester) async {
    // 账户面板内容较高，默认 600 高视口会溢出，改用高视口。
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await loginToHome(tester);
    expect(find.byType(CapsuleNavBar), findsOneWidget);

    await tester.tap(find.byType(UserAvatar));
    await tester.pumpAndSettle();
    expect(find.byType(AccountSheet), findsOneWidget);
    expect(find.byType(CapsuleNavBar), findsNothing);

    // 点遮罩关闭面板，导航恢复。
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byType(AccountSheet), findsNothing);
    expect(find.byType(CapsuleNavBar), findsOneWidget);
  });
}
