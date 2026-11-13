import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/core/service_locator.dart';
import 'package:routepass/core/theme.dart';
import 'package:routepass/pages/bank/answer_page.dart';
import 'package:routepass/pages/bank/favorites_page.dart';
import 'package:routepass/pages/bank/set_detail_page.dart';
import 'package:routepass/pages/bank/wrong_page.dart';
import 'package:routepass/pages/home/home_content.dart';
import 'package:routepass/widgets/set_row_card.dart';
import 'package:routepass/widgets/user_avatar.dart';

import 'test_helpers.dart';

/// 首页预览卡：标题文字所属的那张 Material 卡（最近的 Material 祖先）。
Finder _previewCard(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(Material)).first;

/// 预览卡条目里用到的样例题干（不手写题干，直接从题库取）。
Future<List<String>> _sampleStems(List<String> ids) async {
  final stems = <String>[];
  for (final id in ids) {
    final q = await ServiceLocator.questionRepository.getQuestionById(id);
    stems.add(q!.stem);
  }
  return stems;
}

/// 完整页“加入日期”用的 MM-dd（与页面同一口径，按今天算）。
String _todayMonthDay() {
  final now = DateTime.now();
  return '${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';
}

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

    // R3：快速 10 题入口卡已删（横幅“开始”按钮直达快速 10 题）。
    expect(find.text('快速 10 题'), findsNothing);
    expect(find.text('100 题套卷'), findsOneWidget);
    expect(find.text('200 题套卷'), findsOneWidget);
    expect(find.text('50 题套卷'), findsOneWidget);

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

  testWidgets('R3 精选题库区：3 个精选套卷行同高 76、同宽，全宽行非方块', (tester) async {
    await loginToHome(tester);
    await tester.pumpAndSettle();

    final rows = find.byType(SetRowCard);
    expect(rows, findsNWidgets(3));
    final sizes = [for (var i = 0; i < 3; i++) tester.getSize(rows.at(i))];
    for (final size in sizes) {
      expect(size.height, 76);
      // 套卷行是长条，不是小方块。
      expect(size.width, greaterThan(size.height * 2));
    }
    expect(sizes.map((size) => size.width).toSet().length, 1);
  });

  testWidgets('R3 精选题库区：3 个精选套卷首屏全部渲染（无懒加载）', (tester) async {
    await loginToHome(tester);
    await tester.pumpAndSettle();

    expect(find.byType(SetRowCard), findsNWidgets(3));
    expect(find.text('100 题套卷'), findsOneWidget);
    expect(find.text('200 题套卷'), findsOneWidget);
    expect(find.text('50 题套卷'), findsOneWidget);
  });

  testWidgets('R3 点按套卷行进套卷详情页', (tester) async {
    await loginToHome(tester);

    await tester.tap(find.text('100 题套卷'));
    await tester.pumpAndSettle();
    expect(find.byType(SetDetailPage), findsOneWidget);
  });

  testWidgets('H2 首页栏目标题为“精选题库”，不再是“题库”', (tester) async {
    await loginToHome(tester);

    expect(find.text('精选题库'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(HomeContentPage),
        matching: find.text('题库'),
      ),
      findsNothing,
    );
  });

  testWidgets('H1 问候语字号 28，昵称字号 32（层级 问候 < 昵称）', (tester) async {
    await loginToHome(tester);

    final greeting = tester.widget<Text>(find.textContaining('好！'));
    expect(greeting.style?.fontSize, 28);
    final nickname = tester.widget<Text>(find.text('Max'));
    expect(nickname.style?.fontSize, AppFontSizes.homeGreetingName);
    expect(AppFontSizes.homeGreetingName, 32);
    expect(greeting.style!.fontSize!, lessThan(nickname.style!.fontSize!));
  });

  testWidgets('F6 预览卡在首页最底部（精选题库下方，错题本在上、收藏在下）', (tester) async {
    // 预览卡在首屏之外，用高视口让它全部挂载。
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await loginToHome(tester);

    final lastRow = tester.getRect(find.byType(SetRowCard).last);
    final wrongCard = tester.getRect(_previewCard('错题本'));
    final favoriteCard = tester.getRect(_previewCard('收藏'));

    expect(wrongCard.top, greaterThan(lastRow.bottom));
    expect(favoriteCard.top, greaterThan(wrongCard.bottom));
  });

  testWidgets('F6 预览卡显示今日数量与今日条目（错题 3 道 / 收藏 2 道）', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await loginToHome(tester);

    expect(find.text('今日新增 3 道'), findsOneWidget);
    expect(find.text('今日收藏 2 道'), findsOneWidget);

    final wrongStems = await _sampleStems([
      'SAMPLE-10',
      'SAMPLE-20',
      'SAMPLE-30',
    ]);
    final favoriteStems = await _sampleStems(['SAMPLE-10', 'SAMPLE-20']);

    final wrongCard = _previewCard('错题本');
    final favoriteCard = _previewCard('收藏');
    for (final stem in wrongStems) {
      final item = find.descendant(of: wrongCard, matching: find.text(stem));
      expect(item, findsOneWidget);
      // 每题一行、超长截断。
      expect(tester.widget<Text>(item).maxLines, 1);
    }
    for (final stem in favoriteStems) {
      expect(
        find.descendant(of: favoriteCard, matching: find.text(stem)),
        findsOneWidget,
      );
    }
    // 错题本第三题不在收藏卡里（两张卡各自独立）。
    expect(
      find.descendant(of: favoriteCard, matching: find.text(wrongStems[2])),
      findsNothing,
    );
  });

  testWidgets('F6 预览卡标题紧跟图标左对齐，不居中', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await loginToHome(tester);

    final cases = <(String, IconData)>[
      ('错题本', Icons.menu_book_outlined),
      ('收藏', Icons.star_border_rounded),
    ];
    for (final (title, icon) in cases) {
      final card = _previewCard(title);
      final cardRect = tester.getRect(card);
      final iconRect = tester.getRect(
        find.descendant(of: card, matching: find.byIcon(icon)),
      );
      final titleRect = tester.getRect(
        find.descendant(of: card, matching: find.text(title)),
      );

      // 标题左边缘在图标右侧（不覆盖图标、也不居中）。
      expect(titleRect.left, greaterThan(iconRect.right));
      // 标题文字块水平中心在卡片中心左侧（左对齐）。
      expect(titleRect.center.dx, lessThan(cardRect.center.dx));
      // 紧贴图标右侧（44 图标 + 12 间距 + 图标内留白以内）。
      expect(titleRect.left - iconRect.right, lessThan(AppSpacing.xxl));
    }
  });

  testWidgets('F6 点错题本预览卡进错题本页，条目带 MM-dd 加入日期', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await loginToHome(tester);

    await tester.tap(find.text('今日新增 3 道'));
    await tester.pumpAndSettle();
    expect(find.byType(WrongPage), findsOneWidget);

    final date = _todayMonthDay();
    final page = find.byType(WrongPage);
    expect(
      find.descendant(of: page, matching: find.text('错 2 次 · 加入 $date')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: page, matching: find.text('错 1 次 · 加入 $date')),
      findsNWidgets(2),
    );
  });

  testWidgets('F6 点收藏预览卡进收藏页，条目带模块与 MM-dd 加入日期', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await loginToHome(tester);

    await tester.tap(find.text('今日收藏 2 道'));
    await tester.pumpAndSettle();
    expect(find.byType(FavoritesPage), findsOneWidget);

    final date = _todayMonthDay();
    // SAMPLE-10 / SAMPLE-20 同属 VLAN 模块。
    expect(find.text('VLAN · 加入 $date'), findsNWidgets(2));
  });

  testWidgets('F6 深色模式：预览卡固定白底深字，标题与条目都可读', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await loginToHome(tester);

    final title = tester.widget<Text>(find.text('错题本'));
    expect(title.style?.color, AppColors.brandTitle);
    expect(title.style?.color, isNot(AppColors.brandSurface));

    final count = tester.widget<Text>(find.text('今日新增 3 道'));
    expect(count.style?.color, AppColors.brandSecondaryText);
    expect(count.style?.color, isNot(AppColors.brandSurface));

    final stems = await _sampleStems(['SAMPLE-10']);
    final item = tester.widget<Text>(
      find
          .descendant(of: _previewCard('错题本'), matching: find.text(stems.first))
          .first,
    );
    expect(item.style?.color, AppColors.previewItemText);
    expect(item.style?.color, isNot(AppColors.brandSurface));
  });
}
