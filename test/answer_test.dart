/// 答题页测试（规格文档第 3 章 §22.6：A-01–A-17，Mock 3 道样例题）。
///
/// 装配方式与 widget_test.dart / shell_test.dart 相同：main() 里的
/// ServiceLocator.init 在测试进程不会执行，这里自行装配一套 Mock；
/// MockAuthService 的登录态跨用例保留，已登录时直接测。
/// AnswerPage 里的关联知识点 chip 会 pushNamed，测试的 MaterialApp 没有
/// 注册命名路由，不要点 chips。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/core/service_locator.dart';
import 'package:routepass/pages/bank/answer_page.dart';
import 'package:routepass/pages/bank/answer_widgets.dart';

import 'test_helpers.dart';

/// 登录态跨用例保留：MockAuthService 已登录则直接测，未登录才演示登录。
Future<void> _ensureLoggedIn() async {
  if (await ServiceLocator.authService.getCurrentUser() != null) return;
  await ServiceLocator.authService.login(
    username: 'demo_user1',
    password: 'Demo1234',
  );
}

/// 快速 10 题进答题页（Mock 只有 3 道样例题）。
Future<void> _pumpAnswerPage(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: AnswerPage(
        args: <String, Object?>{'mode': 'quick', 'drawCount': 10},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initTestServices();

  testWidgets('快速 10 题加载与作答：选中选项、解析卡占位、答题卡跳题', (tester) async {
    await _ensureLoggedIn();
    await _pumpAnswerPage(tester);

    // Mock 只有 3 道样例题。
    expect(find.text('第 1/3 题'), findsOneWidget);

    // 选中第一个选项，点“下一题”提交第 1 题并前进到第 2 题。
    await tester.tap(find.byType(OptionTile).first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '下一题'));
    await tester.pumpAndSettle();
    expect(find.text('第 2/3 题'), findsOneWidget);

    // 解析卡显示在已提交的题目上：回到第 1 题验证“样例数据”占位标注，
    // 再前进回第 2 题。
    await tester.tap(find.widgetWithText(OutlinedButton, '上一题'));
    await tester.pumpAndSettle();
    expect(find.text('样例数据'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '下一题'));
    await tester.pumpAndSettle();
    expect(find.text('第 2/3 题'), findsOneWidget);

    // 答题卡 sheet：打开后点 “3” 直接跳到第 3 题。
    await tester.tap(find.byTooltip('答题卡'));
    await tester.pumpAndSettle();
    expect(find.text('答题卡'), findsOneWidget);
    await tester.tap(find.text('3'));
    await tester.pumpAndSettle();
    expect(find.text('第 3/3 题'), findsOneWidget);
  });

  testWidgets('交卷与结果：答题卡到第 3 题交卷，确认 dialog 后结果 sheet，返回关闭', (tester) async {
    await _ensureLoggedIn();
    await _pumpAnswerPage(tester);
    expect(find.text('第 1/3 题'), findsOneWidget);

    // 用答题卡直接跳到第 3 题（末题按钮为“提交”）。
    await tester.tap(find.byTooltip('答题卡'));
    await tester.pumpAndSettle();
    expect(find.text('答题卡'), findsOneWidget);
    await tester.tap(find.text('3'));
    await tester.pumpAndSettle();
    expect(find.text('第 3/3 题'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '提交'));
    await tester.pumpAndSettle();
    // 交卷 dialog（标题与确认按钮都含“确认交卷”）。
    expect(find.text('确认交卷'), findsWidgets);

    await tester.tap(find.widgetWithText(FilledButton, '确认交卷'));
    await tester.pumpAndSettle();
    // 结果 sheet（Mock 练习不计分，显示“练习完成”）。
    expect(find.text('练习完成'), findsOneWidget);

    // 点“返回”关闭 sheet 并 pop 答题页；home 就是 AnswerPage，pop 后为
    // 空白页属正常，断言 sheet 已消失即可。
    await tester.tap(find.widgetWithText(FilledButton, '返回'));
    await tester.pumpAndSettle();
    expect(find.text('练习完成'), findsNothing);
  });
}
