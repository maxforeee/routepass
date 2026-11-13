import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/core/theme.dart';
import 'package:routepass/pages/bank/answer_page.dart';
import 'package:routepass/pages/bank/favorites_page.dart';
import 'package:routepass/pages/bank/set_detail_page.dart';
import 'package:routepass/pages/bank/wrong_page.dart';
import 'package:routepass/pages/home/home_content.dart';
import 'package:routepass/widgets/set_row_card.dart';
import 'package:routepass/widgets/user_avatar.dart';

import 'test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initTestServices();

  testWidgets('G1b 首页问候区：无 AppBar，问候块 + 钉住头像，无顶部同步 chip', (tester) async {
    await loginToHome(tester);

    expect(find.byType(AppBar), findsNothing);
    expect(find.textContaining('好！'), findsOneWidget);
    expect(find.text('Max'), findsOneWidget);
    expect(find.textContaining('今日已完成题目数'), findsOneWidget);
    expect(find.byType(UserAvatar), findsOneWidget);
    expect(find.text('本地模式'), findsNothing);

    // 横幅保留。
    expect(find.text('今天还没有完成任务'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '开始'), findsOneWidget);
  });

  testWidgets('R2 首页不显示工具箱标题或工具网格', (tester) async {
    await loginToHome(tester);

    final home = find.byType(HomeContentPage);
    expect(find.descendant(of: home, matching: find.text('工具箱')), findsNothing);
    expect(
      find.descendant(of: home, matching: find.byType(GridView)),
      findsNothing,
    );
    expect(
      find.descendant(of: home, matching: find.text('IP/进制转换')),
      findsNothing,
    );

    expect(find.text('章节速览'), findsNothing);
    expect(find.text('今日知识点'), findsNothing);
    expect(find.text('学习统计'), findsNothing);

    // R3：快速 10 题入口卡已删（横幅“开始”按钮直达快速 10 题）；错题本改为懒加载行（初始不可见）。
    expect(find.text('快速 10 题'), findsNothing);
    expect(find.text('100 题套卷'), findsOneWidget);
    expect(find.text('200 题套卷'), findsOneWidget);
    expect(find.text('50 题套卷'), findsOneWidget);
    expect(find.text('错题本'), findsNothing);

    // Mock 无继续会话 → H-B1 隐藏。
    expect(find.text('继续学习'), findsNothing);
  });

  testWidgets('本地模式同步提示条：点开同步诊断 sheet', (tester) async {
    // 同步 sheet 内容较高，用小视口会溢出，改用高视口。
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await loginToHome(tester);

    await tester.scrollUntilVisible(
      find.text('本地模式 · 未连接服务器'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('本地模式 · 未连接服务器'), findsOneWidget);
    expect(find.text('学习记录保存在本机，点击查看同步诊断'), findsOneWidget);

    await tester.tap(find.text('本地模式 · 未连接服务器'));
    await tester.pumpAndSettle();
    expect(find.text('同步诊断'), findsOneWidget);
  });

  testWidgets('首页横幅开始直达答题页，不经过套卷详情', (tester) async {
    await loginToHome(tester);

    await tester.tap(
      find.descendant(
        of: find.byType(HomeContentPage),
        matching: find.widgetWithText(FilledButton, '开始'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AnswerPage), findsOneWidget);
    expect(find.byType(SetDetailPage), findsNothing);
  });

  testWidgets('R1 深色模式：问候语与昵称用深色标题色（#F1F5F9）', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await loginToHome(tester);

    const darkTitle = Color(0xFFF1F5F9);
    final greeting = tester.widget<Text>(find.textContaining('好！'));
    expect(greeting.style?.color, darkTitle);
    final nickname = tester.widget<Text>(find.text('Max'));
    expect(nickname.style?.color, darkTitle);
  });

  testWidgets('R1 头像顶部与问候首行平齐（top = homeTopPad + xs = 76）', (tester) async {
    await loginToHome(tester);

    final positioned = tester.widget<Positioned>(
      find.descendant(
        of: find.byType(HomeContentPage),
        matching: find.ancestor(
          of: find.byType(UserAvatar),
          matching: find.byType(Positioned),
        ),
      ),
    );
    expect(positioned.top, AppSizes.homeTopPad + AppSpacing.xs);
    expect(positioned.top, 76);
    expect(positioned.right, AppSpacing.md);
  });

  testWidgets('R3 题库区：5 行 SetRowCard 同高 76、同宽，全宽行非方块', (tester) async {
    await loginToHome(tester);

    await tester.scrollUntilVisible(
      find.text('收藏'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    final rows = find.byType(SetRowCard);
    expect(rows, findsNWidgets(5));
    final sizes = [for (var i = 0; i < 5; i++) tester.getSize(rows.at(i))];
    for (final size in sizes) {
      expect(size.height, 76);
    }
    expect(sizes.map((size) => size.width).toSet().length, 1);
    // 错题本 / 收藏是长条，不是小方块。
    expect(sizes[3].width, greaterThan(sizes[3].height * 2));
    expect(sizes[4].width, greaterThan(sizes[4].height * 2));
  });

  testWidgets('R3 题库区懒加载：初始只渲染 3 行，滚到底部附近再补齐', (tester) async {
    await loginToHome(tester);
    await tester.pumpAndSettle();

    expect(find.byType(SetRowCard), findsNWidgets(3));
    expect(find.text('错题本'), findsNothing);
    expect(find.text('收藏'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('收藏'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.byType(SetRowCard), findsNWidgets(5));
    expect(find.text('错题本'), findsOneWidget);
    expect(find.text('收藏'), findsOneWidget);
  });

  testWidgets('R3 点按套卷行进套卷详情页', (tester) async {
    await loginToHome(tester);

    await tester.tap(find.text('100 题套卷'));
    await tester.pumpAndSettle();
    expect(find.byType(SetDetailPage), findsOneWidget);
  });

  testWidgets('R3 点按错题本行进错题页', (tester) async {
    await loginToHome(tester);

    await tester.scrollUntilVisible(
      find.text('错题本'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('错题本'));
    await tester.pumpAndSettle();
    expect(find.byType(WrongPage), findsOneWidget);
    expect(find.text('暂无错题'), findsOneWidget);
  });

  testWidgets('R3 点按收藏行进收藏页', (tester) async {
    await loginToHome(tester);

    await tester.scrollUntilVisible(
      find.text('收藏'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('收藏'));
    await tester.pumpAndSettle();
    expect(find.byType(FavoritesPage), findsOneWidget);
    expect(find.text('暂无收藏'), findsOneWidget);
  });
}
