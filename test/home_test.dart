import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/pages/bank/answer_page.dart';
import 'package:routepass/pages/bank/set_detail_page.dart';
import 'package:routepass/pages/home/home_content.dart';
import 'package:routepass/pages/toolbox/ip_convert_page.dart';
import 'package:routepass/widgets/capsule_nav_bar.dart';

import 'test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initTestServices();

  testWidgets('首页 10 卡片瀑布流：关键卡片齐全，继续学习（H-B1）隐藏', (tester) async {
    await loginToHome(tester);

    expect(find.text('快速 10 题'), findsOneWidget);
    expect(find.text('100 题套卷'), findsOneWidget);
    expect(find.text('200 题套卷'), findsOneWidget);
    expect(find.text('50 题套卷'), findsOneWidget);
    expect(find.text('100 题 · 约 60 分钟'), findsOneWidget);
    expect(find.text('200 题 · 约 120 分钟'), findsOneWidget);
    expect(find.text('50 题 · 约 30 分钟'), findsOneWidget);
    expect(find.text('错题本'), findsOneWidget);
    expect(find.text('章节速览'), findsOneWidget);
    expect(find.text('VLAN 基础'), findsOneWidget);
    expect(find.text('已掌握 0/2'), findsOneWidget);
    expect(find.text('今日知识点'), findsOneWidget);
    expect(find.text('子网计算器'), findsOneWidget);
    expect(find.text('IP/进制转换'), findsOneWidget);
    expect(find.text('学习统计'), findsOneWidget);

    // Mock 无继续会话 → H-B1 隐藏。
    expect(find.text('继续学习'), findsNothing);

    // 横幅标题（今日未完成任务）。
    expect(find.text('今天还没有完成任务'), findsOneWidget);
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
