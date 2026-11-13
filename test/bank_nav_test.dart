import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/core/kv_store.dart';
import 'package:routepass/core/service_locator.dart';
import 'package:routepass/models/practice.dart';
import 'package:routepass/pages/bank/favorites_page.dart';
import 'package:routepass/pages/bank/module_list_page.dart';
import 'package:routepass/pages/bank/set_detail_page.dart';
import 'package:routepass/pages/bank/stats_page.dart';
import 'package:routepass/pages/bank/wrong_page.dart';
import 'package:routepass/router/app_router.dart';
import 'package:routepass/widgets/capsule_nav_bar.dart';

import 'test_helpers.dart';

/// 首页快捷入口也有同名文字，切 tab 必须把 finder 限定在胶囊导航里。
Finder _navTab(String label) =>
    find.descendant(of: find.byType(CapsuleNavBar), matching: find.text(label));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initTestServices();

  testWidgets('点底栏题库进题库页', (tester) async {
    await loginToHome(tester);

    await tester.tap(_navTab('题库'));
    await tester.pumpAndSettle();
    expect(find.byType(BankModuleListPage), findsOneWidget);
    expect(find.text('H3CNE 300 道 · 每套含解析'), findsOneWidget);
    expect(find.text('100 题套卷'), findsOneWidget);
  });

  testWidgets('点套卷卡进套卷详情页', (tester) async {
    await loginToHome(tester);

    await tester.tap(_navTab('题库'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('100 题套卷'));
    await tester.pumpAndSettle();
    expect(find.byType(SetDetailPage), findsOneWidget);
    expect(find.text('100 题套卷'), findsOneWidget);
  });

  testWidgets('错题本入口进错题本页（空态）', (tester) async {
    // 入口行在 600 高默认视口下首屏外（ListView 懒构建，滚不到）；用 1400 高视口。
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await loginToHome(tester);

    await tester.tap(_navTab('题库'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('错题本'));
    await tester.pumpAndSettle();
    expect(find.byType(WrongPage), findsOneWidget);
    expect(find.text('暂无错题'), findsOneWidget);
  });

  testWidgets('收藏入口进收藏页（空态）', (tester) async {
    // 同错题本：入口行在默认视口下首屏外，用 1400 高视口。
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await loginToHome(tester);

    await tester.tap(_navTab('题库'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('收藏'));
    await tester.pumpAndSettle();
    expect(find.byType(FavoritesPage), findsOneWidget);
    expect(find.text('暂无收藏'), findsOneWidget);
  });

  testWidgets('410 宽视口下套卷卡模块标签单行不溢出', (tester) async {
    tester.view.physicalSize = const Size(410, 890);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await loginToHome(tester);
    await tester.tap(_navTab('题库'));
    await tester.pumpAndSettle();

    // 5 个模块标签都渲染；若标签换行会撑破套卷卡 104 固定高，触发 RenderFlex 溢出。
    for (final label in const ['VLAN', 'OSPF', 'ACL', 'NAT', '子网划分']) {
      expect(find.text(label), findsWidgets);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('搜索框按题干过滤；无匹配显示空态', (tester) async {
    await loginToHome(tester);
    await tester.tap(_navTab('题库'));
    await tester.pumpAndSettle();

    // canva 参考保留搜索条；筛选 chips 已移除。
    expect(find.text('搜索题目'), findsOneWidget);
    expect(find.text('只看错题'), findsNothing);
    expect(find.text('只看未做'), findsNothing);

    final searchField = find.descendant(
      of: find.byType(BankModuleListPage),
      matching: find.byType(TextField),
    );
    final resultTiles = find.descendant(
      of: find.byType(BankModuleListPage),
      matching: find.byType(ListTile),
    );

    // 命中题干：切换到题目结果列表。
    final samples = await ServiceLocator.questionRepository.drawQuestions(
      mode: 'practice',
      drawCount: 100,
    );
    await tester.enterText(searchField, samples.first.stem);
    await tester.pumpAndSettle();
    expect(resultTiles, findsWidgets);
    expect(find.text('没有找到相关题目'), findsNothing);

    // 无匹配：空态。
    await tester.enterText(searchField, '不存在的题干关键词');
    await tester.pumpAndSettle();
    expect(find.text('没有找到相关题目'), findsOneWidget);
    expect(resultTiles, findsNothing);
  });

  // “快速 10 题直达答题页”已在 set_detail_test.dart（首页套卷卡进详情页，
  // 快速 10 题直达答题页）覆盖；题库页没有“10 题速练”入口，不在此测。

  // G1c: 首页“学习统计”方块已移除，统计页改为直接走路由验证。
  testWidgets('统计页路由仍可用（首页统计方块已随 G1c 移除）', (tester) async {
    await loginToHome(tester);
    await tester.tap(_navTab('题库'));
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(BankModuleListPage));
    Navigator.of(context).pushNamed(AppRoutes.bankStats);
    await tester.pumpAndSettle();
    expect(find.byType(StatsPage), findsOneWidget);
  });

  testWidgets('kv 有进度指针时首页不再显示继续学习', (tester) async {
    ServiceLocator.kvStore.setString(
      KvStore.keyHomeContinue,
      jsonEncode(
        const ContinueSession(
          mode: 'practice',
          answeredCount: 2,
          totalCount: 10,
          questionId: 'SAMPLE-20',
        ).toJson(),
      ),
    );
    addTearDown(() => ServiceLocator.kvStore.remove(KvStore.keyHomeContinue));

    await loginToHome(tester);
    expect(find.text('继续学习'), findsNothing);
  });
}
