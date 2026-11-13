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
    await tester.tap(find.text('100 题套卷'));
    await tester.pumpAndSettle();

    expect(find.byType(SetDetailPage), findsOneWidget);
    expect(find.text('100 题套卷'), findsOneWidget);
    expect(find.text('H3CNE-RS+ 模拟套卷 · 含解析'), findsOneWidget);
    expect(find.text('单选 75 · 多选 25'), findsOneWidget);

    // 知识点考察：20px 粗体标题 + 5 个模块行（真实进度 0%）。
    final sectionTitle = tester.widget<Text>(find.text('知识点考察'));
    expect(sectionTitle.style?.fontSize, AppFontSizes.detailSectionTitle);
    expect(sectionTitle.style?.fontWeight, FontWeight.bold);
    expect(sectionTitle.style?.color, AppColors.brandTitle);
    expect(find.text('VLAN'), findsOneWidget);
    expect(find.text('OSPF'), findsOneWidget);
    expect(find.text('ACL'), findsOneWidget);
    expect(find.text('NAT'), findsOneWidget);
    expect(find.text('子网划分'), findsOneWidget);
    expect(find.text('20 题 · 0%'), findsNWidgets(5));
    final progressBars = find.descendant(
      of: find.byType(SetDetailPage),
      matching: find.byType(FractionallySizedBox),
    );
    expect(progressBars, findsNWidgets(5));
    for (final element in progressBars.evaluate()) {
      expect((element.widget as FractionallySizedBox).widthFactor, 0.0);
    }

    expect(find.byType(ReservedSlot), findsOneWidget);
    expect(find.text('预留容器 · 以后在这里加内容'), findsOneWidget);
    expect(find.text('答题说明'), findsOneWidget);
    expect(find.text('限时 60 分钟，超时自动交卷'), findsOneWidget);
    expect(find.text('交卷后可查看解析与得分'), findsOneWidget);
    expect(find.text('做错的题自动收入错题本'), findsOneWidget);
    expect(find.text('开始答题'), findsOneWidget);
  });

  testWidgets('开始答题固定在屏幕底部且不随内容滚动', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: SetDetailPage(
          args: <String, Object?>{'mode': 'exam', 'drawCount': 100},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(SingleChildScrollView),
        matching: find.text('开始答题'),
      ),
      findsNothing,
    );
    final pinned = tester.widget<Positioned>(
      find.descendant(
        of: find.byType(SetDetailPage),
        matching: find.byType(Positioned),
      ),
    );
    expect(pinned.bottom, AppSpacing.md);

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '开始答题'),
    );
    expect(
      button.style?.backgroundColor?.resolve(<WidgetState>{}),
      AppColors.brandPrimary,
    );
    final shape = button.style?.shape?.resolve(<WidgetState>{});
    expect(shape, isA<RoundedRectangleBorder>());
    expect(
      (shape! as RoundedRectangleBorder).borderRadius,
      BorderRadius.circular(AppRadii.setDetailStartButton),
    );
  });

  testWidgets('套卷详情页 开始答题 进答题页', (tester) async {
    await loginToHome(tester);

    await tester.tap(_navTab('题库'));
    await tester.pumpAndSettle();
    // 三套卷卡依次是 100 / 200 / 50 题：点行进详情页点开始答题，
    // 答题页参数必须是 exam + 对应题量。
    for (final (count, title) in [
      (100, '100 题套卷'),
      (200, '200 题套卷'),
      (50, '50 题套卷'),
    ]) {
      await tester.tap(find.text(title));
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
    expect(find.text('H3CNE-RS+ 模拟套卷 · 含解析'), findsOneWidget);
    expect(find.text('单选 150 · 多选 50'), findsOneWidget);
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
    expect(find.text('H3CNE-RS+ 模拟套卷 · 含解析'), findsOneWidget);
    expect(find.text('单选 37 · 多选 13'), findsOneWidget);
    expect(find.text('10 题 · 0%'), findsNWidgets(5));
    expect(find.text('限时 30 分钟，超时自动交卷'), findsOneWidget);
  });

  testWidgets('四套卷共用模板，数字全由 drawCount 推导', (tester) async {
    // 100/200/50/10 同一模板：标题、单选多选、每模块题量、时长
    // 全部按 drawCount 公式推导，不许出现写死的单套数字。
    for (final (count, meta, perModule, minutes)
        in <(int, String, String, String)>[
          (100, '单选 75 · 多选 25', '20 题 · 0%', '限时 60 分钟，超时自动交卷'),
          (200, '单选 150 · 多选 50', '40 题 · 0%', '限时 120 分钟，超时自动交卷'),
          (50, '单选 37 · 多选 13', '10 题 · 0%', '限时 30 分钟，超时自动交卷'),
          (10, '单选 7 · 多选 3', '2 题 · 0%', '限时 6 分钟，超时自动交卷'),
        ]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: SetDetailPage(
            args: <String, Object?>{'mode': 'exam', 'drawCount': count},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('$count 题套卷'),
        findsOneWidget,
        reason: 'drawCount=$count 标题',
      );
      expect(find.text(meta), findsOneWidget, reason: 'drawCount=$count 元信息');
      expect(
        find.text(perModule),
        findsNWidgets(5),
        reason: 'drawCount=$count 每模块题量',
      );
      expect(find.text(minutes), findsOneWidget, reason: 'drawCount=$count 时长');
    }
  });

  testWidgets('首页套卷卡进详情页，快速 10 题直达答题页', (tester) async {
    await loginToHome(tester);

    // R3：题库区改为懒加载行列表，首页有两个 ListView（外层 + 内层
    // shrinkWrap），拖拽须用 Scrollable.first 定位外层。
    for (var i = 0; i < 8 && find.text('100 题套卷').evaluate().isEmpty; i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await tester.pumpAndSettle();
    }
    // 再向上滚一段，让卡片离开底部悬浮导航的遮挡区再点。
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -200));
    await tester.pumpAndSettle();
    await tester.tap(find.text('100 题套卷'));
    await tester.pumpAndSettle();
    expect(find.byType(SetDetailPage), findsOneWidget);
    expect(find.text('100 题套卷'), findsOneWidget);

    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();

    // R3：快速 10 题入口卡已删；横幅“开始”按钮直达快速 10 题答题页。
    // 先向上滚回顶部，让横幅按钮可见再点。
    for (
      var i = 0;
      i < 8 && find.widgetWithText(FilledButton, '开始').evaluate().isEmpty;
      i++
    ) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 300));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.widgetWithText(FilledButton, '开始'));
    await tester.pumpAndSettle();
    expect(find.text('第 1/3 题'), findsOneWidget);
  });

  testWidgets('410×890 视口无溢出且开始答题按钮可见', (tester) async {
    await tester.binding.setSurfaceSize(const Size(410, 890));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await loginToHome(tester);

    await tester.tap(_navTab('题库'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('100 题套卷'));
    await tester.pumpAndSettle();

    expect(find.byType(SetDetailPage), findsOneWidget);
    expect(tester.takeException(), isNull);

    final buttonRect = tester.getRect(
      find.widgetWithText(FilledButton, '开始答题'),
    );
    final screenRect = tester.getRect(find.byType(SetDetailPage));
    expect(screenRect.overlaps(buttonRect), isTrue);
    expect(buttonRect.bottom, lessThanOrEqualTo(screenRect.bottom));
    expect(buttonRect.left, closeTo(screenRect.left + AppSpacing.md, 1));
    expect(buttonRect.right, closeTo(screenRect.right - AppSpacing.md, 1));
    expect(screenRect.bottom - buttonRect.bottom, closeTo(AppSpacing.md, 1));
  });

  testWidgets('深色模式下元信息文字使用品牌说明色', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: SetDetailPage(
          args: <String, Object?>{'mode': 'exam', 'drawCount': 100},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final statText = tester.widget<Text>(find.text('单选 75 · 多选 25'));
    final statColor = statText.style?.color;
    expect(statColor, isNotNull);
    expect(statColor, isNot(const Color(0xFF334155)));
    expect(statColor, const Color(0xFF94A3B8));
  });

  testWidgets('深色模式下套卷详情标题使用自适应浅色', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: SetDetailPage(
          args: <String, Object?>{'mode': 'exam', 'drawCount': 100},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final BuildContext context = tester.element(find.text('100 题套卷'));
    for (final title in <String>['100 题套卷', '知识点考察', 'VLAN', '答题说明']) {
      final text = tester.widget<Text>(find.text(title));
      expect(text.style?.color, AppColors.title(context));
      expect(text.style?.color, isNot(AppColors.brandTitle));
    }
    expect(AppColors.title(context), const Color(0xFFF1F5F9));
  });
}
