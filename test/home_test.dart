import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/core/kv_store.dart';
import 'package:routepass/core/service_locator.dart';
import 'package:routepass/core/theme.dart';
import 'package:routepass/models/daily_question.dart';
import 'package:routepass/pages/bank/favorites_page.dart';
import 'package:routepass/pages/bank/wrong_page.dart';
import 'package:routepass/pages/home/home_content.dart';
import 'package:routepass/widgets/user_avatar.dart';

import 'test_helpers.dart';

/// 首页错题本 / 收藏方块（key 挂在正方形 AspectRatio 上）。
Finder _squareTile(String name) => find.byKey(ValueKey('home-tile-$name'));

/// 方块边框画笔（与每日一练共用 DailyCardBorderPainter）。
DailyCardBorderPainter _tileBorder(WidgetTester tester, String name) {
  final paint = tester.widget<CustomPaint>(
    find
        .descendant(of: _squareTile(name), matching: find.byType(CustomPaint))
        .first,
  );
  return paint.painter! as DailyCardBorderPainter;
}

/// 方块里用到的样例题干（不手写题干，直接从题库取）。
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

/// 今天的每日一练题（与页面同一取题规则：按日期确定性取题）。
Future<DailyQuestion> _todayDailyQuestion() {
  return ServiceLocator.dailyPracticeService.questionForDate(DateTime.now());
}

/// 每日一练某条选项整条的 Material（整条底色与边框都在它身上）。
Material _dailyOption(WidgetTester tester, String key) {
  return tester.widget<Material>(find.byKey(ValueKey('daily-option-$key')));
}

/// 每日一练某条选项的边框色。
Color? _dailyOptionBorder(WidgetTester tester, String key) {
  final shape = _dailyOption(tester, key).shape as RoundedRectangleBorder;
  return shape.side.color;
}

/// 高视口：每日一练卡与其下方的方块入口 / 同步条同屏挂载。
void _useTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initTestServices();

  setUp(() {
    // KvStore 是进程级静态实例，清掉每日一练作答状态，避免测试间串扰。
    ServiceLocator.kvStore.remove(KvStore.keyDailyAnswer);
  });

  testWidgets('G1b 首页问候区：无 AppBar，问候块 + 滚动头像，无顶部同步 chip', (tester) async {
    await loginToHome(tester);

    expect(find.byType(AppBar), findsNothing);
    expect(find.textContaining('好！'), findsOneWidget);
    expect(find.text('Max'), findsOneWidget);
    expect(find.textContaining('今日已完成题目数'), findsOneWidget);
    expect(find.byType(UserAvatar), findsOneWidget);
    expect(find.text('本地模式'), findsNothing);

    // F14c：今日任务横幅已删，首页不再有“开始”按钮。
    expect(find.text('今天还没有完成任务'), findsNothing);
    expect(find.widgetWithText(FilledButton, '开始'), findsNothing);
  });

  testWidgets('F8b 首页问候区让出系统状态栏（顶部偏移 = 安全区 + 内容内边距）', (tester) async {
    // 真机 Android 状态栏约 24–30dp；只留 16dp 内容内边距会让问候语
    // 落在状态栏区域内（16 < 24），被状态栏压住。
    const statusBar = 24.0;
    await ServiceLocator.authService.logout();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(padding: const EdgeInsets.only(top: statusBar)),
            child: HomeContentPage(onSelectTab: (_) {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final greetingTop = tester.getTopLeft(find.textContaining('好！')).dy;
    // 问候语整块在状态栏下方。
    expect(greetingTop, greaterThanOrEqualTo(statusBar));
    // 系统安全区之上仍保留 md 内容内边距，与题库页一致。
    expect(greetingTop, greaterThanOrEqualTo(statusBar + AppSpacing.md));
  });

  testWidgets('R2 首页不显示工具箱标题或工具网格', (tester) async {
    // 每日一练卡把方块入口推到首屏之外，用高视口让下方组件全部挂载。
    _useTallViewport(tester);
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

    // F14c：快速 10 题入口卡与精选题库套卷行都已从首页删除。
    expect(find.text('快速 10 题'), findsNothing);
    expect(find.text('100 题套卷'), findsNothing);
    expect(find.text('200 题套卷'), findsNothing);
    expect(find.text('50 题套卷'), findsNothing);
    expect(find.text('精选题库'), findsNothing);

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

  testWidgets('R1 深色模式：问候语与昵称用深色标题色（#FFFFFF）', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await loginToHome(tester);

    const darkTitle = Color(0xFFFFFFFF);
    final greeting = tester.widget<Text>(find.textContaining('好！'));
    expect(greeting.style?.color, darkTitle);
    final nickname = tester.widget<Text>(find.text('Max'));
    expect(nickname.style?.color, darkTitle);
  });

  testWidgets('E 头像随页面滚动：在可滚动内容里，不是固定 Positioned 覆盖层', (tester) async {
    await loginToHome(tester);

    final avatar = find.byType(UserAvatar);
    expect(avatar, findsOneWidget);
    // 头像是首页 ListView 内容的一部分，滚动时随页面移动。
    expect(
      find.ancestor(of: avatar, matching: find.byType(Scrollable)),
      findsWidgets,
    );
    expect(
      find.ancestor(of: avatar, matching: find.byType(Positioned)),
      findsNothing,
    );
  });

  testWidgets('D 未登录时问候区显示中性占位名，不留空白（浅色 / 深色都可见）', (tester) async {
    for (final brightness in <Brightness>[Brightness.light, Brightness.dark]) {
      await ServiceLocator.authService.logout();
      await tester.pumpWidget(
        MaterialApp(
          theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
          home: HomeContentPage(onSelectTab: (_) {}),
        ),
      );
      await tester.pumpAndSettle();

      final name = find.text('同学');
      expect(name, findsOneWidget, reason: '$brightness 下应有占位名');
      final text = tester.widget<Text>(name);
      final scheme = Theme.of(tester.element(find.byType(HomeContentPage)))
          .colorScheme;
      expect(text.style?.color, scheme.onSurface);
      expect(text.style?.color, isNot(scheme.surface));
    }
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

  testWidgets('F14c 错题本 / 收藏方块并排且为正方形（宽 = 高）', (tester) async {
    _useTallViewport(tester);
    await loginToHome(tester);

    final wrong = tester.getRect(_squareTile('wrong'));
    final favorite = tester.getRect(_squareTile('favorites'));

    // 正方形：宽 = 高，两块同尺寸。
    expect(wrong.width, moreOrLessEquals(wrong.height, epsilon: 0.5));
    expect(favorite.width, moreOrLessEquals(favorite.height, epsilon: 0.5));
    expect(wrong.size, favorite.size);

    // 并排：错题本在左、收藏在右，顶边对齐，中间只留 cardGap。
    expect(wrong.right, lessThan(favorite.left));
    expect(wrong.top, moreOrLessEquals(favorite.top, epsilon: 0.5));
    expect(
      favorite.left - wrong.right,
      moreOrLessEquals(AppSpacing.cardGap, epsilon: 0.5),
    );

    // 两块都在每日一练卡下方（不再是上下堆叠的长预览卡）。
    final daily = tester.getRect(
      find.byKey(const ValueKey('daily-practice-card')),
    );
    expect(wrong.top, greaterThan(daily.bottom));
    expect(favorite.top, greaterThan(daily.bottom));
  });

  testWidgets('F14c 方块只放图标 + 标题 + 今日数量，不列今日条目', (tester) async {
    _useTallViewport(tester);
    await loginToHome(tester);

    final cases = <(String, String, IconData, String)>[
      ('wrong', '错题本', Icons.menu_book_outlined, '今日新增 3 道'),
      ('favorites', '收藏', Icons.star_border_rounded, '今日收藏 2 道'),
    ];
    final stems = await _sampleStems(['SAMPLE-10', 'SAMPLE-20', 'SAMPLE-30']);
    for (final (name, title, icon, countLabel) in cases) {
      final tile = _squareTile(name);
      expect(
        find.descendant(of: tile, matching: find.text(title)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: tile, matching: find.byIcon(icon)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: tile, matching: find.text(countLabel)),
        findsOneWidget,
      );
      // 长预览卡里的今日条目列表（圆点 + 题干）与右侧箭头都已去掉。
      for (final stem in stems) {
        expect(
          find.descendant(of: tile, matching: find.text(stem)),
          findsNothing,
        );
      }
      expect(find.descendant(of: tile, matching: find.text('·')), findsNothing);
      expect(
        find.descendant(of: tile, matching: find.byIcon(Icons.chevron_right)),
        findsNothing,
      );
    }
    // 底部栏目标题也删了（方块自带标题）。
    expect(find.text('错题本 · 收藏'), findsNothing);
  });

  testWidgets('F14c 方块沿用每日一练边框语言：透明卡面 + 标题骑在上边框缺口里', (tester) async {
    _useTallViewport(tester);
    await loginToHome(tester);

    final context = tester.element(find.byType(HomeContentPage));
    final dailyTitle = tester.widget<Text>(find.text('每日一练'));
    final cases = <(String, String)>[('wrong', '错题本'), ('favorites', '收藏')];
    for (final (name, title) in cases) {
      final tile = _squareTile(name);
      final tileRect = tester.getRect(tile);
      final titleFinder = find.descendant(of: tile, matching: find.text(title));
      final titleRect = tester.getRect(titleFinder);

      // 卡面透明（无填充），边框由 CustomPaint 单独绘制，四角同圆角。
      final material = tester.widget<Material>(
        find.descendant(of: tile, matching: find.byType(Material)).first,
      );
      expect(material.type, MaterialType.transparency);
      final border = _tileBorder(tester, name);
      expect(border.color, AppColors.cardBorder(context));
      expect(border.radius, AppRadii.card);
      expect(border.gapStart, greaterThan(0));
      expect(border.gapEnd, greaterThan(border.gapStart));

      // 标题与每日一练同一套字体 / 字重 / 颜色。
      final titleText = tester.widget<Text>(titleFinder);
      expect(titleText.style?.fontSize, dailyTitle.style?.fontSize);
      expect(titleText.style?.fontWeight, dailyTitle.style?.fontWeight);
      expect(titleText.style?.color, dailyTitle.style?.color);
      expect(titleText.style?.color, AppColors.cardTitle(context));

      // fieldset legend：标题纵向跨过上边框，横向靠左不居中，且落在缺口内。
      expect(titleRect.top, lessThan(tileRect.top));
      expect(titleRect.bottom, greaterThan(tileRect.top));
      expect(titleRect.left, greaterThan(tileRect.left));
      expect(titleRect.center.dx, lessThan(tileRect.center.dx));
      expect(
        titleRect.left - tileRect.left,
        greaterThanOrEqualTo(border.gapStart),
      );
      expect(titleRect.right - tileRect.left, lessThanOrEqualTo(border.gapEnd));
    }
  });

  testWidgets('F14c 点错题本方块进错题本页，条目带 MM-dd 加入日期', (tester) async {
    _useTallViewport(tester);
    await loginToHome(tester);

    await tester.tap(_squareTile('wrong'));
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

  testWidgets('F14c 点收藏方块进收藏页，条目带模块与 MM-dd 加入日期', (tester) async {
    _useTallViewport(tester);
    await loginToHome(tester);

    await tester.tap(_squareTile('favorites'));
    await tester.pumpAndSettle();
    expect(find.byType(FavoritesPage), findsOneWidget);

    final date = _todayMonthDay();
    // SAMPLE-10 / SAMPLE-20 同属 VLAN 模块。
    expect(find.text('VLAN · 加入 $date'), findsNWidgets(2));
  });

  testWidgets('F14c/A 深色模式：方块跟随深色主题，不再固定白底', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    _useTallViewport(tester);
    await loginToHome(tester);

    final context = tester.element(find.byType(HomeContentPage));
    final scheme = Theme.of(context).colorScheme;

    final title = tester.widget<Text>(find.text('错题本'));
    expect(title.style?.color, scheme.onSurface);
    expect(title.style?.color, isNot(scheme.surface));

    final count = tester.widget<Text>(find.text('今日新增 3 道'));
    expect(count.style?.color, scheme.onSurfaceVariant);
    expect(count.style?.color, isNot(scheme.surface));

    // 边框与图标底色都用深色模式 token，卡面仍是透明的（不铺白底）。
    expect(_tileBorder(tester, 'wrong').color, AppColors.cardBorder(context));
    expect(
      _tileBorder(tester, 'favorites').color,
      AppColors.cardBorder(context),
    );
    final wrongIcon = find.descendant(
      of: _squareTile('wrong'),
      matching: find.byIcon(Icons.menu_book_outlined),
    );
    final iconChip = tester.widget<Container>(
      find.ancestor(of: wrongIcon, matching: find.byType(Container)).first,
    );
    final decoration = iconChip.decoration! as BoxDecoration;
    expect(decoration.color, AppColors.wrongIconBackground(context));
    expect(decoration.color, isNot(AppColors.brandSurface));
    expect(
      tester.widget<Icon>(wrongIcon).color,
      AppColors.wrongIconForeground(context),
    );
  });

  testWidgets('F7 每日一练卡在方块入口上方，标题骑在卡片上边框上', (tester) async {
    _useTallViewport(tester);
    await loginToHome(tester);

    expect(find.text('每日一练'), findsOneWidget);

    final card = tester.getRect(
      find.byKey(const ValueKey('daily-practice-card')),
    );
    final wrongTile = tester.getRect(_squareTile('wrong'));
    final favoriteTile = tester.getRect(_squareTile('favorites'));

    // F14c：精选题库已删，每日一练下方直接是错题本 / 收藏方块。
    expect(card.bottom, lessThan(wrongTile.top));
    expect(card.bottom, lessThan(favoriteTile.top));

    // fieldset legend 样式：标题纵向跨过卡片上边框，横向靠左不居中。
    final title = tester.getRect(find.text('每日一练'));
    expect(title.top, lessThan(card.top));
    expect(title.bottom, greaterThan(card.top));
    expect(title.left, greaterThan(card.left));
    expect(title.center.dx, lessThan(card.center.dx));
  });

  testWidgets('F7 每日一练显示今日题干与 A–D 四条整条选项', (tester) async {
    _useTallViewport(tester);
    await loginToHome(tester);

    final question = await _todayDailyQuestion();
    expect(find.text(question.stem), findsOneWidget);
    expect(question.options.map((option) => option.key).toList(), <String>[
      'A',
      'B',
      'C',
      'D',
    ]);

    for (final option in question.options) {
      final strip = find.byKey(ValueKey('daily-option-${option.key}'));
      expect(
        find.descendant(of: strip, matching: find.text(option.text)),
        findsOneWidget,
      );
      // 未作答：四条都是主题白底 + 主题边框。
      final context = tester.element(find.byType(HomeContentPage));
      expect(
        _dailyOption(tester, option.key).color,
        AppColors.dailyOptionIdleBackground(context),
      );
      expect(
        _dailyOptionBorder(tester, option.key),
        AppColors.cardBorder(context),
      );
    }

    expect(find.text('已锁定，明天刷新'), findsNothing);
  });

  testWidgets('F7 答对：整条变绿并锁定，再点其他选项无效', (tester) async {
    _useTallViewport(tester);
    await loginToHome(tester);

    final question = await _todayDailyQuestion();
    final correct = question.correctKey;
    final other = question.options
        .firstWhere((option) => option.key != correct)
        .key;

    await tester.tap(find.byKey(ValueKey('daily-option-$correct')));
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(HomeContentPage));
    expect(
      _dailyOption(tester, correct).color,
      AppColors.dailyCorrectBackground(context),
    );
    expect(_dailyOptionBorder(tester, correct), AppColors.success(context));
    expect(find.text('已锁定，明天刷新'), findsOneWidget);

    // 锁定后点另一条：不产生第二次选择，正确的绿条保持不变。
    await tester.tap(find.byKey(ValueKey('daily-option-$other')));
    await tester.pumpAndSettle();

    expect(
      _dailyOption(tester, other).color,
      AppColors.dailyOptionIdleBackground(context),
    );
    expect(
      _dailyOption(tester, correct).color,
      AppColors.dailyCorrectBackground(context),
    );
    expect(find.text('已锁定，明天刷新'), findsOneWidget);
  });

  testWidgets('F7 答错：点的整条变红，同时正确答案那条标绿并锁定', (tester) async {
    _useTallViewport(tester);
    await loginToHome(tester);

    final question = await _todayDailyQuestion();
    final correct = question.correctKey;
    final wrong = question.options
        .firstWhere((option) => option.key != correct)
        .key;

    await tester.tap(find.byKey(ValueKey('daily-option-$wrong')));
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(HomeContentPage));
    expect(
      _dailyOption(tester, wrong).color,
      AppColors.wrongIconBackground(context),
    );
    expect(
      _dailyOptionBorder(tester, wrong),
      AppColors.wrongIconForeground(context),
    );
    expect(
      _dailyOption(tester, correct).color,
      AppColors.dailyCorrectBackground(context),
    );
    expect(_dailyOptionBorder(tester, correct), AppColors.success(context));
    expect(find.text('已锁定，明天刷新'), findsOneWidget);
  });

  testWidgets('F7 作答落盘：重新 _load 后当天仍是锁定状态', (tester) async {
    _useTallViewport(tester);
    await loginToHome(tester);

    final question = await _todayDailyQuestion();
    await tester.tap(
      find.byKey(ValueKey('daily-option-${question.correctKey}')),
    );
    await tester.pumpAndSettle();

    final raw = ServiceLocator.kvStore.getString(KvStore.keyDailyAnswer);
    expect(raw, isNotNull);
    // kv 里按 yyyy-MM-dd 存当天日期，换日自动视为未作答。
    expect(raw, contains(_todayMonthDay()));

    // 重新加载首页（等价于关掉 App 再进来重拉当天状态）。
    final state = tester.state<HomeContentPageState>(
      find.byType(HomeContentPage),
    );
    await state.refresh();
    await tester.pumpAndSettle();

    expect(find.text('已锁定，明天刷新'), findsOneWidget);
    expect(
      _dailyOption(tester, question.correctKey).color,
      AppColors.dailyCorrectBackground(
        tester.element(find.byType(HomeContentPage)),
      ),
    );
  });

  testWidgets('A/F7 深色模式：每日一练跟随深色主题，状态色可区分', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    _useTallViewport(tester);
    await loginToHome(tester);

    final question = await _todayDailyQuestion();
    final context = tester.element(find.byType(HomeContentPage));
    final scheme = Theme.of(context).colorScheme;

    final title = tester.widget<Text>(find.text('每日一练'));
    expect(title.style?.color, scheme.onSurface);

    final stem = tester.widget<Text>(find.text(question.stem));
    expect(stem.style?.color, scheme.onSurface);

    final optionText = tester.widget<Text>(
      find.descendant(
        of: find.byKey(ValueKey('daily-option-${question.options.first.key}')),
        matching: find.text(question.options.first.text),
      ),
    );
    expect(optionText.style?.color, scheme.onSurface);

    // 未作答条用深色抬升层，不再固定白底。
    expect(
      _dailyOption(tester, question.options.first.key).color,
      scheme.surfaceContainerHighest,
    );

    // 答错后：红条 / 绿条都用深色模式的状态色。
    final correct = question.correctKey;
    final wrong = question.options
        .firstWhere((option) => option.key != correct)
        .key;
    await tester.tap(find.byKey(ValueKey('daily-option-$wrong')));
    await tester.pumpAndSettle();

    expect(_dailyOption(tester, wrong).color, scheme.errorContainer);
    expect(
      _dailyOption(tester, correct).color,
      AppColors.dailyCorrectBackground(context),
    );
    expect(
      tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(ValueKey('daily-option-$wrong')),
              matching: find.text(
                question.options.firstWhere((o) => o.key == wrong).text,
              ),
            ),
          )
          .style
          ?.color,
      scheme.onErrorContainer,
    );
  });

  testWidgets('B 每日一练卡透明、标题无底色，上边框在标题处留缺口', (tester) async {
    _useTallViewport(tester);
    await loginToHome(tester);

    final context = tester.element(find.byType(HomeContentPage));
    final cardFinder = find.byKey(const ValueKey('daily-practice-card'));
    final card = tester.widget<Container>(cardFinder);
    // 卡片自身无填充也无边框装饰（边框由 CustomPaint 单独绘制）。
    expect(card.decoration, isNull);

    // 标题透明，没有白底盖住边框。
    expect(
      find.ancestor(of: find.text('每日一练'), matching: find.byType(ColoredBox)),
      findsNothing,
    );

    final border = tester.widget<CustomPaint>(
      find.byKey(const ValueKey('daily-card-border')),
    );
    final painter = border.painter! as DailyCardBorderPainter;
    expect(painter.color, AppColors.cardBorder(context));
    expect(painter.gapStart, greaterThan(0));
    expect(painter.gapEnd, greaterThan(painter.gapStart));

    // 缺口横向覆盖标题（标题落在被擦除的上边框区间内）。
    final cardRect = tester.getRect(cardFinder);
    final titleRect = tester.getRect(find.text('每日一练'));
    expect(
      titleRect.left - cardRect.left,
      greaterThanOrEqualTo(painter.gapStart),
    );
    expect(titleRect.right - cardRect.left, lessThanOrEqualTo(painter.gapEnd));
  });

  testWidgets('F 首页组件视觉间距统一（问候区 → 每日一练 → 方块 → 同步条）', (tester) async {
    _useTallViewport(tester);
    await loginToHome(tester);

    final greeting = tester.getRect(
      find
          .ancestor(of: find.textContaining('好！'), matching: find.byType(Row))
          .first,
    );
    final dailyTitle = tester.getRect(find.text('每日一练'));
    final dailyCard = tester.getRect(
      find.byKey(const ValueKey('daily-practice-card')),
    );
    final wrongTile = tester.getRect(_squareTile('wrong'));
    final favoriteTile = tester.getRect(_squareTile('favorites'));
    final tileTitle = tester.getRect(find.text('错题本'));
    final syncStrip = tester.getRect(
      find
          .ancestor(
            of: find.text('本地模式 · 未连接服务器'),
            matching: find.byType(InkWell),
          )
          .first,
    );

    // F14c 新顺序：问候区 → 每日一练 → 错题本/收藏方块 → 同步条。
    expect(greeting.bottom, lessThan(dailyCard.top));
    expect(dailyCard.bottom, lessThan(wrongTile.top));
    expect(wrongTile.bottom, lessThan(syncStrip.top));

    // 组件之间全部是同一个 md：问候区到“每日一练”标题（不是卡片边框）、
    // 卡片到方块标题、方块到同步条。标题骑在边框上探出的 overhang 已在
    // 组件内部补偿，不算组件间距。
    expect(
      dailyTitle.top - greeting.bottom,
      moreOrLessEquals(AppSpacing.md, epsilon: 0.5),
    );
    expect(
      tileTitle.top - dailyCard.bottom,
      moreOrLessEquals(AppSpacing.md, epsilon: 0.5),
    );
    expect(
      syncStrip.top - wrongTile.bottom,
      moreOrLessEquals(AppSpacing.md, epsilon: 0.5),
    );
    expect(
      syncStrip.top - favoriteTile.bottom,
      moreOrLessEquals(AppSpacing.md, epsilon: 0.5),
    );
  });

  test('F7 每日一练按日期确定性取题（同一天同题，隔天换题）', () async {
    final service = ServiceLocator.dailyPracticeService;
    final today = DateTime(2026, 11, 13);
    final tomorrow = DateTime(2026, 11, 14);

    final first = await service.questionForDate(today);
    final again = await service.questionForDate(today);
    expect(first.id, again.id);

    final next = await service.questionForDate(tomorrow);
    expect(next.id, isNot(first.id));

    // 作答状态按日期隔离：今天答过，明天未答。
    expect(await service.answerForDate(today), isNull);
    await service.saveAnswer(
      date: today,
      questionId: first.id,
      selectedKey: first.correctKey,
    );
    expect(await service.answerForDate(today), first.correctKey);
    expect(await service.answerForDate(tomorrow), isNull);
  });
}
