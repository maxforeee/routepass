import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/core/theme.dart';
import 'package:routepass/pages/bank/answer_page.dart';
import 'package:routepass/pages/bank/set_detail_page.dart';
import 'package:routepass/widgets/capsule_nav_bar.dart';
import 'package:routepass/widgets/reserved_slot.dart';

import 'test_helpers.dart';

Finder _navTab(String label) =>
    find.descendant(of: find.byType(CapsuleNavBar), matching: find.text(label));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initTestServices();

  testWidgets('套卷详情页 100 题渲染完整', (tester) async {
    await loginToHome(tester);

    await tester.tap(_navTab('题库'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '开始').first);
    await tester.pumpAndSettle();

    expect(find.byType(SetDetailPage), findsOneWidget);
    expect(find.text('100 题套卷'), findsOneWidget);
    expect(find.text('H3CNE 模拟套卷 · 每题含解析'), findsOneWidget);
    expect(find.text('100 题'), findsOneWidget);
    expect(find.text('单选 75 · 多选 25'), findsOneWidget);
    expect(find.text('约 60 分钟'), findsOneWidget);
    expect(find.text('知识点考察'), findsOneWidget);
    expect(find.text('VLAN'), findsOneWidget);
    expect(find.text('OSPF'), findsOneWidget);
    expect(find.text('ACL'), findsOneWidget);
    expect(find.text('NAT'), findsOneWidget);
    expect(find.text('子网划分'), findsOneWidget);
    expect(find.text('20 题 · 0%'), findsNWidgets(5));
    expect(find.byType(ReservedSlot), findsOneWidget);
    expect(find.text('预留容器 · 以后在这里加内容'), findsOneWidget);
    expect(find.text('答题说明'), findsOneWidget);
    expect(find.text('限时 60 分钟，超时自动交卷'), findsOneWidget);
    expect(find.text('交卷后可查看解析与得分'), findsOneWidget);
    expect(find.text('做错的题自动收入错题本'), findsOneWidget);
    expect(find.text('开始答题'), findsOneWidget);
  });

  testWidgets('套卷详情页 开始答题 进答题页', (tester) async {
    await loginToHome(tester);

    await tester.tap(_navTab('题库'));
    await tester.pumpAndSettle();
    // 三张套卷卡的“开始”依次是 100 / 200 / 50 题：进详情页点开始答题，
    // 答题页参数必须是 exam + 对应题量。
    for (final (count, index) in [(100, 0), (200, 1), (50, 2)]) {
      await tester.tap(find.widgetWithText(FilledButton, '开始').at(index));
      await tester.pumpAndSettle();
      await tester.tap(find.text('开始答题'));
      await tester.pumpAndSettle();
      final answer = tester.widget<AnswerPage>(find.byType(AnswerPage));
      expect(answer.args['mode'], 'exam');
      expect(answer.args['drawCount'], count);
      expect(find.text('第 1/3 题'), findsOneWidget);
      // 返回是自定义控件，pageBack 找不到标准 BackButton：答题页点
      // AppBar 的 arrow_back，弹退出确认后点“退出并保留进度”，再点
      // 详情页的 chevron 回题库。
      await tester.tap(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byIcon(Icons.arrow_back),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '退出并保留进度'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('套卷详情页 200 题推导正确', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: SetDetailPage(
          args: <String, Object?>{'mode': 'exam', 'drawCount': 200},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('200 题套卷'), findsOneWidget);
    expect(find.text('200 题'), findsOneWidget);
    expect(find.text('单选 150 · 多选 50'), findsOneWidget);
    expect(find.text('约 120 分钟'), findsOneWidget);
    expect(find.text('40 题 · 0%'), findsNWidgets(5));
    expect(find.text('限时 120 分钟，超时自动交卷'), findsOneWidget);
  });

  testWidgets('套卷详情页 50 题推导正确', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: SetDetailPage(
          args: <String, Object?>{'mode': 'exam', 'drawCount': 50},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('50 题套卷'), findsOneWidget);
    expect(find.text('50 题'), findsOneWidget);
    expect(find.text('单选 37 · 多选 13'), findsOneWidget);
    expect(find.text('约 30 分钟'), findsOneWidget);
    expect(find.text('10 题 · 0%'), findsNWidgets(5));
    expect(find.text('限时 30 分钟，超时自动交卷'), findsOneWidget);
  });

  testWidgets('首页套卷卡进详情页，快速 10 题直达答题页', (tester) async {
    await loginToHome(tester);

    await tester.tap(find.text('100 题套卷'));
    await tester.pumpAndSettle();
    expect(find.byType(SetDetailPage), findsOneWidget);
    expect(find.text('100 题套卷'), findsOneWidget);

    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('快速 10 题'));
    await tester.pumpAndSettle();
    expect(find.text('第 1/3 题'), findsOneWidget);
  });

  testWidgets('410×890 视口无溢出且开始答题按钮可见', (tester) async {
    await tester.binding.setSurfaceSize(const Size(410, 890));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await loginToHome(tester);

    await tester.tap(_navTab('题库'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '开始').first);
    await tester.pumpAndSettle();

    expect(find.byType(SetDetailPage), findsOneWidget);
    expect(tester.takeException(), isNull);

    final buttonRect = tester.getRect(find.text('开始答题'));
    final screenRect = tester.getRect(find.byType(SetDetailPage));
    expect(screenRect.overlaps(buttonRect), isTrue);
    expect(buttonRect.bottom, lessThanOrEqualTo(screenRect.bottom));
  });

  testWidgets('深色模式下统计文字使用深色标签色', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: SetDetailPage(
          args: <String, Object?>{'mode': 'exam', 'drawCount': 100},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final statText = tester.widget<Text>(find.text('100 题'));
    final statColor = statText.style?.color;
    expect(statColor, isNotNull);
    expect(statColor, isNot(const Color(0xFF334155)));
    expect(statColor, const Color(0xFF94A3B8));
  });
}
