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

  testWidgets('点套卷卡开始进套卷详情页', (tester) async {
    await loginToHome(tester);

    await tester.tap(_navTab('题库'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '开始').first);
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

  testWidgets('只看错题空态 / 只看未做显示样题列表', (tester) async {
    await loginToHome(tester);
    await tester.tap(_navTab('题库'));
    await tester.pumpAndSettle();

    // Mock 错题本为空：只看错题 -> 空态。
    await tester.tap(find.text('只看错题'));
    await tester.pumpAndSettle();
    expect(find.text('暂无符合条件的题目'), findsOneWidget);

    // 关掉“只看错题”，再开“只看未做”（样题全部未做 -> 列表照常显示）。
    await tester.tap(find.text('只看错题'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('只看未做'));
    await tester.pumpAndSettle();
    expect(find.text('暂无符合条件的题目'), findsNothing);
    expect(find.byType(ListTile), findsWidgets);
  });

  // “快速 10 题直达答题页”已在 set_detail_test.dart（首页套卷卡进详情页，
  // 快速 10 题直达答题页）覆盖；题库页没有“10 题速练”入口，不在此测。

  testWidgets('首页学习统计方块进统计页', (tester) async {
    await loginToHome(tester);

    await tester.ensureVisible(find.text('学习统计'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('学习统计'));
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
