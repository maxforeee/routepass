import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/pages/bank/answer_page.dart';
import 'package:routepass/pages/bank/set_detail_page.dart';
import 'package:routepass/pages/home/home_content.dart';
import 'package:routepass/pages/toolbox/ip_convert_page.dart';
import 'package:routepass/pages/toolbox/toolbox_tools.dart';
import 'package:routepass/widgets/capsule_nav_bar.dart';
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

  testWidgets('G1c 首页工具箱：10 张正方形卡片按注册表顺序排列', (tester) async {
    await loginToHome(tester);

    expect(find.text('工具箱'), findsOneWidget);
    final grid = find.byType(GridView);
    expect(grid, findsOneWidget);
    final squares = find.descendant(
      of: grid,
      matching: find.byType(AspectRatio),
    );
    expect(squares, findsNWidgets(10));

    for (var i = 0; i < toolboxTools.length; i++) {
      final square = squares.at(i);
      final size = tester.getSize(square);
      expect(size.width, size.height);
      expect(tester.widget<AspectRatio>(square).aspectRatio, 1);
      expect(
        find.descendant(of: square, matching: find.text(toolboxTools[i].name)),
        findsOneWidget,
      );
    }

    expect(find.text('章节速览'), findsNothing);
    expect(find.text('今日知识点'), findsNothing);
    expect(find.text('学习统计'), findsNothing);

    // 套卷与入口卡在后续 chunk 处理，本 chunk 保持原样。
    // 工具箱网格把套卷行推到首屏之下，先滚到可见再断言。
    // 工具箱网格把套卷行推到首屏之下，分段向下滚再断言。
    // 测试视口 800 宽时正方形卡片很大，内容约 3300 高，须多滚几段。
    for (var i = 0; i < 8 && find.text('快速 10 题').evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();
    }
    expect(find.text('快速 10 题'), findsOneWidget);
    expect(find.text('100 题套卷'), findsOneWidget);
    expect(find.text('200 题套卷'), findsOneWidget);
    expect(find.text('50 题套卷'), findsOneWidget);
    expect(find.text('错题本'), findsOneWidget);

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

  testWidgets('首页 IP/进制转换方块进 IP 转换页，底栏隐藏', (tester) async {
    await loginToHome(tester);

    await tester.ensureVisible(find.text('IP/进制转换'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('IP/进制转换'));
    await tester.pumpAndSettle();
    expect(find.byType(IpConvertPage), findsOneWidget);
    expect(find.byType(CapsuleNavBar), findsNothing);
  });
}
