import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/core/kv_store.dart';
import 'package:routepass/core/service_locator.dart';
import 'package:routepass/core/theme.dart';
import 'package:routepass/models/daily_question.dart';
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

/// 高视口：每日一练卡与其下方的精选题库同屏挂载。
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

    // 横幅保留。
    expect(find.text('今天还没有完成任务'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '开始'), findsOneWidget);
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
    // 每日一练卡把精选题库推到首屏之外，用高视口让套卷行全部挂载。
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

  testWidgets('R3 精选题库区：3 个精选套卷行同高 76、同宽，全宽行非方块', (tester) async {
    // 每日一练卡把精选题库推到首屏之外，用高视口让套卷行全部挂载。
    _useTallViewport(tester);
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
    _useTallViewport(tester);
    await loginToHome(tester);
    await tester.pumpAndSettle();

    expect(find.byType(SetRowCard), findsNWidgets(3));
    expect(find.text('100 题套卷'), findsOneWidget);
    expect(find.text('200 题套卷'), findsOneWidget);
    expect(find.text('50 题套卷'), findsOneWidget);
  });

  testWidgets('R3 点按套卷行进套卷详情页', (tester) async {
    _useTallViewport(tester);
    await loginToHome(tester);

    await tester.tap(find.text('100 题套卷'));
    await tester.pumpAndSettle();
    expect(find.byType(SetDetailPage), findsOneWidget);
  });

  testWidgets('H2 首页栏目标题为“精选题库”，不再是“题库”', (tester) async {
    _useTallViewport(tester);
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

  testWidgets('F6/A 深色模式：预览卡跟随深色主题，不再固定白底', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await loginToHome(tester);

    final scheme = Theme.of(tester.element(find.byType(HomeContentPage)))
        .colorScheme;

    final card = _previewCard('错题本');
    final material = tester.widget<Material>(card);
    expect(material.color, scheme.surface);
    expect(material.color, isNot(AppColors.brandSurface));

    final title = tester.widget<Text>(find.text('错题本'));
    expect(title.style?.color, scheme.onSurface);

    final count = tester.widget<Text>(find.text('今日新增 3 道'));
    expect(count.style?.color, scheme.onSurfaceVariant);

    final stems = await _sampleStems(['SAMPLE-10']);
    final item = tester.widget<Text>(
      find
          .descendant(of: _previewCard('错题本'), matching: find.text(stems.first))
          .first,
    );
    expect(item.style?.color, scheme.onSurfaceVariant);
    expect(item.style?.color, isNot(scheme.surface));
  });

  testWidgets('F7 每日一练卡在精选题库上方，标题骑在卡片上边框上', (tester) async {
    _useTallViewport(tester);
    await loginToHome(tester);

    expect(find.text('每日一练'), findsOneWidget);

    final card = tester.getRect(
      find.byKey(const ValueKey('daily-practice-card')),
    );
    final section = tester.getRect(find.text('精选题库'));
    final firstRow = tester.getRect(find.byType(SetRowCard).first);

    // 在横幅下方、精选题库（含第一个套卷行）上方。
    expect(card.bottom, lessThan(section.top));
    expect(card.bottom, lessThan(firstRow.top));

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

  testWidgets('C 预览条目与卡片内容左缘齐平（无缩进）', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await loginToHome(tester);

    final card = _previewCard('错题本');
    final stems = await _sampleStems(['SAMPLE-10']);
    final bullet = find.descendant(of: card, matching: find.text('·')).first;
    final item = find.descendant(of: card, matching: find.text(stems.first));

    // 圆点紧贴卡片内容左缘（卡内左右内边距 = md），不再缩进 56。
    final cardLeft = tester.getTopLeft(card).dx;
    expect(
      tester.getTopLeft(bullet).dx,
      moreOrLessEquals(cardLeft + AppSpacing.md, epsilon: 0.5),
    );
    // 题干在圆点右侧，仍是单行截断。
    expect(
      tester.getTopLeft(item).dx,
      greaterThan(tester.getTopLeft(bullet).dx),
    );
    expect(tester.widget<Text>(item).maxLines, 1);
  });

  testWidgets('F 首页组件视觉间距统一（横幅 → 每日一练 → 精选题库 → 预览卡）', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await loginToHome(tester);

    final banner = tester.getRect(
      find
          .ancestor(
            of: find.text('今天还没有完成任务'),
            matching: find.byType(Container),
          )
          .first,
    );
    final dailyTitle = tester.getRect(find.text('每日一练'));
    final dailyCard = tester.getRect(
      find.byKey(const ValueKey('daily-practice-card')),
    );
    final sectionTitle = tester.getRect(find.text('精选题库'));
    final lastRow = tester.getRect(find.byType(SetRowCard).last);
    final syncStrip = tester.getRect(
      find
          .ancestor(
            of: find.text('本地模式 · 未连接服务器'),
            matching: find.byType(InkWell),
          )
          .first,
    );
    final previewTitle = tester.getRect(find.text('错题本 · 收藏'));

    // 横幅到“每日一练”标题（不是卡片边框）、卡片到底部栏目标题、
    // 套卷行到同步条、同步条到底部栏目标题，全部是同一个 md。
    expect(
      dailyTitle.top - banner.bottom,
      moreOrLessEquals(AppSpacing.md, epsilon: 0.5),
    );
    expect(
      sectionTitle.top - dailyCard.bottom,
      moreOrLessEquals(AppSpacing.md, epsilon: 0.5),
    );
    expect(
      syncStrip.top - lastRow.bottom,
      moreOrLessEquals(AppSpacing.md, epsilon: 0.5),
    );
    expect(
      previewTitle.top - syncStrip.bottom,
      moreOrLessEquals(AppSpacing.md, epsilon: 0.5),
    );

    // 错题本 / 收藏两张预览卡之间也是同一个间距。
    final wrong = tester.getRect(_previewCard('错题本'));
    final favorite = tester.getRect(_previewCard('收藏'));
    expect(
      favorite.top - wrong.bottom,
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
