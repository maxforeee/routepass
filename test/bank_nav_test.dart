import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/core/kv_store.dart';
import 'package:routepass/core/service_locator.dart';
import 'package:routepass/models/practice.dart';
import 'package:routepass/pages/bank/answer_page.dart';
import 'package:routepass/pages/bank/favorites_page.dart';
import 'package:routepass/pages/bank/module_list_page.dart';
import 'package:routepass/pages/bank/quiz_page.dart';
import 'package:routepass/pages/bank/set_detail_page.dart';
import 'package:routepass/pages/bank/stats_page.dart';
import 'package:routepass/pages/bank/wrong_page.dart';
import 'package:routepass/router/app_router.dart';
import 'package:routepass/widgets/capsule_nav_bar.dart';
import 'package:routepass/widgets/set_row_card.dart';
import 'package:routepass/widgets/user_avatar.dart';

import 'test_helpers.dart';

/// 首页快捷入口也有同名文字，切 tab 必须把 finder 限定在胶囊导航里。
Finder _navTab(String label) =>
    find.descendant(of: find.byType(CapsuleNavBar), matching: find.text(label));

/// F10：练习 tab 唯一一张套卷卡（线上 practiceByModule = H3CNE / 100 题）。
/// 卡片标签里也有 “H3CNE”，首页精选题库也渲染 SetRowCard，所以限定在题库页
/// 内按卡片定位。
Finder get _practiceCard => find.descendant(
  of: find.byType(BankModuleListPage),
  matching: find.widgetWithText(SetRowCard, 'H3CNE'),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initTestServices();

  testWidgets('点底栏题库进题库页', (tester) async {
    await loginToHome(tester);

    await tester.tap(_navTab('题库'));
    await tester.pumpAndSettle();
    expect(find.byType(BankModuleListPage), findsOneWidget);
    // B1：标题“题库”32px 特粗作为页面内容（非 AppBar）；F5 起标题下不再
    // 有“H3CNE N 道 · 每套含解析”副标题。
    expect(
      find.descendant(
        of: find.byType(BankModuleListPage),
        matching: find.text('题库'),
      ),
      findsOneWidget,
    );
    expect(find.text('H3CNE 0 道 · 每套含解析'), findsNothing);
    expect(find.textContaining('每套含解析'), findsNothing);
    // F5：搜索条下方是练习 / 考试切换。
    expect(find.text('练习'), findsOneWidget);
    expect(find.text('考试'), findsOneWidget);
    // H3：头像入口只在首页，题库页不再有 UserAvatar。
    expect(
      find.descendant(
        of: find.byType(BankModuleListPage),
        matching: find.byType(UserAvatar),
      ),
      findsNothing,
    );
    expect(find.text('100 题套卷'), findsNothing);
    // F10：练习 tab 渲染线上清单的唯一套卷卡（H3CNE / 100 题）。
    expect(_practiceCard, findsOneWidget);
    expect(find.text('100 题 · 含解析'), findsOneWidget);
  });

  testWidgets('练习套卷卡进套卷详情页（G2c：不再直达答题页）', (tester) async {
    await loginToHome(tester);

    await tester.tap(_navTab('题库'));
    await tester.pumpAndSettle();
    await tester.tap(_practiceCard);
    await tester.pumpAndSettle();
    expect(find.byType(SetDetailPage), findsOneWidget);
  });

  testWidgets('点套卷卡进套卷详情页', (tester) async {
    await loginToHome(tester);

    await tester.tap(_navTab('题库'));
    await tester.pumpAndSettle();
    await tester.tap(_practiceCard);
    await tester.pumpAndSettle();
    expect(find.byType(SetDetailPage), findsOneWidget);
    // 详情页标题由 drawCount 推导：练习卡 100 题。
    expect(find.text('100 题套卷'), findsOneWidget);
  });

  // Q1：做题前置页（套卷详情）与答题页自动隐藏胶囊导航，返回后恢复。
  testWidgets('套卷详情页隐藏胶囊导航，返回后恢复', (tester) async {
    await loginToHome(tester);
    await tester.tap(_navTab('题库'));
    await tester.pumpAndSettle();
    expect(find.byType(CapsuleNavBar), findsOneWidget);

    await tester.tap(_practiceCard);
    await tester.pumpAndSettle();
    expect(find.byType(SetDetailPage), findsOneWidget);
    expect(find.byType(CapsuleNavBar), findsNothing);

    // 钉住的“开始练习”没有被导航遮挡，直接可点。
    await tester.tap(find.widgetWithText(FilledButton, '开始练习'));
    await tester.pumpAndSettle();
    expect(find.byType(QuizPage), findsOneWidget);
    expect(find.byType(CapsuleNavBar), findsNothing);

    // 未作答直接返回：QuizPage 的返回箭头不弹确认。
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.byType(SetDetailPage), findsOneWidget);
    expect(find.byType(CapsuleNavBar), findsNothing);

    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.byType(SetDetailPage), findsNothing);
    expect(find.byType(CapsuleNavBar), findsOneWidget);
  });

  testWidgets('答题页隐藏胶囊导航，返回后恢复', (tester) async {
    addTearDown(() => ServiceLocator.kvStore.remove(KvStore.keyHomeContinue));
    await loginToHome(tester);
    await tester.tap(_navTab('题库'));
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(BankModuleListPage));
    Navigator.of(context).pushNamed(
      AppRoutes.bankQuiz,
      arguments: <String, Object?>{'mode': 'practice', 'drawCount': 100},
    );
    await tester.pumpAndSettle();
    expect(find.byType(AnswerPage), findsOneWidget);
    expect(find.byType(CapsuleNavBar), findsNothing);

    await tester.tap(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.arrow_back),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '退出并保留进度'));
    await tester.pumpAndSettle();
    expect(find.byType(AnswerPage), findsNothing);
    expect(find.byType(CapsuleNavBar), findsOneWidget);
  });

  testWidgets('错题本路由仍可用（入口已按 F5 从题库页移除）', (tester) async {
    await loginToHome(tester);

    await tester.tap(_navTab('题库'));
    await tester.pumpAndSettle();
    expect(find.text('错题本'), findsNothing);

    final context = tester.element(find.byType(BankModuleListPage));
    Navigator.of(context).pushNamed(AppRoutes.bankWrong);
    await tester.pumpAndSettle();
    expect(find.byType(WrongPage), findsOneWidget);
    // F6：Mock 预置了今天的演示错题，页面显示条目而不是空态。
    expect(find.text('暂无错题'), findsNothing);
    expect(
      find.descendant(
        of: find.byType(WrongPage),
        matching: find.textContaining('加入 '),
      ),
      findsWidgets,
    );
  });

  testWidgets('收藏路由仍可用（入口已按 F5 从题库页移除）', (tester) async {
    await loginToHome(tester);

    await tester.tap(_navTab('题库'));
    await tester.pumpAndSettle();
    expect(find.text('收藏'), findsNothing);

    final context = tester.element(find.byType(BankModuleListPage));
    Navigator.of(context).pushNamed(AppRoutes.bankFavorites);
    await tester.pumpAndSettle();
    expect(find.byType(FavoritesPage), findsOneWidget);
    // F6：Mock 预置了今天的演示收藏，页面显示条目而不是空态。
    expect(find.text('暂无收藏'), findsNothing);
    expect(
      find.descendant(
        of: find.byType(FavoritesPage),
        matching: find.textContaining('加入 '),
      ),
      findsWidgets,
    );
  });

  testWidgets('410 宽视口下套卷卡标签排布不溢出（练习 / 考试两个 tab）', (tester) async {
    tester.view.physicalSize = const Size(410, 890);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await loginToHome(tester);
    await tester.tap(_navTab('题库'));
    await tester.pumpAndSettle();

    // F10 起练习 tab 只有一张卡（H3CNE + 100题 两个标签），考试 tab 两张
    // 卡各三个标签（H3CNE / 模拟 / 100题）。旧 5 个模块标签（VLAN 等）随
    // 占位数据一起删除，这里守住窄视口下标签行不撑破套卷卡。
    expect(find.text('H3CNE'), findsWidgets);
    expect(find.text('100题'), findsWidgets);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('考试'));
    await tester.pumpAndSettle();

    expect(find.byType(SetRowCard), findsNWidgets(2));
    for (final label in const ['H3CNE', '模拟', '100题']) {
      expect(find.text(label), findsWidgets, reason: label);
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
