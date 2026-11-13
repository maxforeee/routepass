import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/core/service_locator.dart';
import 'package:routepass/core/theme.dart';
import 'package:routepass/models/bank_manifest.dart';
import 'package:routepass/pages/bank/module_list_page.dart';
import 'package:routepass/pages/knowledge/knowledge_home_page.dart';
import 'package:routepass/pages/toolbox/toolbox_home_page.dart';
import 'package:routepass/services/bank/bank_manifest_service.dart';
import 'package:routepass/services/mock/mock_bank_manifest_service.dart';
import 'package:routepass/widgets/capsule_nav_bar.dart';
import 'package:routepass/widgets/module_tag.dart';
import 'package:routepass/widgets/page_header.dart';
import 'package:routepass/widgets/set_row_card.dart';
import 'package:routepass/widgets/user_avatar.dart';

import 'test_helpers.dart';

/// F3（用户反馈 B1 / H3 / B3 / O1）回归 + F5（练习/考试切换）回归 + F10
/// （题库页两个 tab 接后端 manifest）：题库页标题字号与左对齐、头像只在首页、
/// 套卷行标题与副标题完整显示、两个 tab 切换下方列表。两个视口（手机 410 /
/// 平板 800）各跑一遍。
const _viewports = <Size>[Size(410, 890), Size(800, 1400)];

/// F10：练习 tab 来自 practiceByModule（线上 1 条：H3CNE / 100 题）。
const _practiceTitles = <String>['H3CNE'];

/// F10：考试 tab 来自 exams[]（线上 2 卷）。
const _paperTitles = <String>['H3CNE 模拟卷 A', 'H3CNE 模拟卷 B'];

const _setSubtitle = '100 题 · 含解析';

Future<void> _openBank(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await loginToHome(tester);
  await tester.tap(
    find.descendant(of: find.byType(CapsuleNavBar), matching: find.text('题库')),
  );
  await tester.pumpAndSettle();
  expect(find.byType(BankModuleListPage), findsOneWidget);
}

Finder _inBank(Finder matching) =>
    find.descendant(of: find.byType(BankModuleListPage), matching: matching);

RenderParagraph _paragraph(WidgetTester tester, String text) =>
    tester.renderObject<RenderParagraph>(_inBank(find.text(text)));

/// 单个页头实测值：三页逐项对比用，不写死字号。
class _HeaderMetrics {
  const _HeaderMetrics({
    required this.titleSize,
    required this.titleWeight,
    required this.subtitleSize,
    required this.alignment,
    required this.titleLeft,
    required this.titleTop,
    required this.subtitleLeft,
    required this.subtitleTop,
  });

  final double? titleSize;
  final FontWeight? titleWeight;
  final double? subtitleSize;
  final CrossAxisAlignment alignment;
  final double titleLeft;
  final double titleTop;
  final double subtitleLeft;
  final double subtitleTop;

  double get innerGap => subtitleTop - titleTop;
}

_HeaderMetrics _headerMetrics(
  WidgetTester tester,
  String title,
  String subtitle,
) {
  final header = find.byType(PageHeader);
  expect(header, findsOneWidget);
  final titleFinder = find.descendant(of: header, matching: find.text(title));
  final subtitleFinder = find.descendant(
    of: header,
    matching: find.text(subtitle),
  );
  expect(titleFinder, findsOneWidget);
  expect(subtitleFinder, findsOneWidget);

  final titleText = tester.widget<Text>(titleFinder);
  final subtitleText = tester.widget<Text>(subtitleFinder);
  final column = tester.widget<Column>(
    find.descendant(of: header, matching: find.byType(Column)).first,
  );
  final titleTopLeft = tester.getTopLeft(titleFinder);
  final subtitleTopLeft = tester.getTopLeft(subtitleFinder);
  return _HeaderMetrics(
    titleSize: titleText.style?.fontSize,
    titleWeight: titleText.style?.fontWeight,
    subtitleSize: subtitleText.style?.fontSize,
    alignment: column.crossAxisAlignment,
    titleLeft: titleTopLeft.dx,
    titleTop: titleTopLeft.dy,
    subtitleLeft: subtitleTopLeft.dx,
    subtitleTop: subtitleTopLeft.dy,
  );
}

/// 用与 App 相同的主题单独 pump 一个页面（知识库 / 工具箱不经过底栏）。
Future<void> _pumpStandalonePage(
  WidgetTester tester,
  Size size,
  Widget page,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: page));
  await tester.pumpAndSettle();
}

/// 统计 fetchManifest 调用次数的包装，用于验证下拉刷新确实重新拉清单。
class _CountingManifestService implements BankManifestService {
  _CountingManifestService(this._inner);

  final BankManifestService _inner;
  int fetchCount = 0;

  @override
  Future<BankManifest> fetchManifest() {
    fetchCount++;
    return _inner.fetchManifest();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initTestServices();

  for (final size in _viewports) {
    final label = '${size.width.toInt()}x${size.height.toInt()}';

    testWidgets('H 题库页头与知识库/工具箱逐项一致（$label）', (tester) async {
      await _openBank(tester, size);

      expect(_inBank(find.byType(PageHeader)), findsOneWidget);
      final bank = _headerMetrics(tester, '题库', '练习考试');

      await _pumpStandalonePage(tester, size, const KnowledgeHomePage());
      final knowledge = _headerMetrics(tester, '知识库', 'H3CNE 考点 · 章 / 节 / 知识点');

      await _pumpStandalonePage(tester, size, const ToolboxHomePage());
      final toolbox = _headerMetrics(tester, '工具箱', '网工常用小工具 · 全部本地运行');

      // 三页共用 PageHeader：字号 / 字重 / 左对齐 / 标题与副标题间距逐项相等。
      for (final page in <(String, _HeaderMetrics)>[
        ('知识库', knowledge),
        ('工具箱', toolbox),
      ]) {
        final (name, metrics) = page;
        expect(metrics.titleSize, bank.titleSize, reason: '$name 标题字号');
        expect(metrics.titleWeight, bank.titleWeight, reason: '$name 标题字重');
        expect(metrics.subtitleSize, bank.subtitleSize, reason: '$name 副标题字号');
        expect(metrics.alignment, bank.alignment, reason: '$name 页头对齐');
        expect(metrics.subtitleLeft, metrics.titleLeft, reason: '$name 副标题左对齐');
        expect(metrics.innerGap, bank.innerGap, reason: '$name 标题/副标题间距');
      }
      expect(bank.subtitleLeft, bank.titleLeft, reason: '题库副标题左对齐');
      expect(
        bank.titleSize,
        AppTheme.light.textTheme.titleLarge?.fontSize,
        reason: '题库标题沿用主题 titleLarge 字号',
      );
      expect(bank.titleWeight, FontWeight.bold);

      expect(_inBank(find.byType(UserAvatar)), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('P1-2 题库搜索条深色模式跟随主题（$label）', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: ThemeMode.dark,
          home: const BankModuleListPage(),
        ),
      );
      await tester.pumpAndSettle();

      final searchBar = find
          .ancestor(
            of: find.byType(TextField),
            matching: find.byType(Container),
          )
          .first;
      final decoration =
          tester.widget<Container>(searchBar).decoration! as BoxDecoration;
      final context = tester.element(find.byType(TextField));
      expect(decoration.color, AppColors.cardSurface(context));
      expect(decoration.color, isNot(AppColors.brandSurface));
      expect(
        (decoration.border! as Border).top.color,
        AppColors.cardBorder(context),
      );

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.style?.color, AppColors.cardTitle(context));
      expect(
        textField.decoration?.hintStyle?.color,
        AppColors.cardCaption(context),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('B3 标题左缘与搜索条左缘对齐（$label）', (tester) async {
      await _openBank(tester, size);

      final titleLeft = tester.getTopLeft(_inBank(find.text('题库'))).dx;
      final searchBar = find
          .ancestor(
            of: _inBank(find.byType(TextField)),
            matching: find.byType(Container),
          )
          .first;
      final searchLeft = tester.getTopLeft(searchBar).dx;

      expect(titleLeft, AppSpacing.md);
      expect(searchLeft, AppSpacing.md);
      expect(titleLeft, searchLeft);
    });

    testWidgets('O1 练习套卷行标题与副标题不截断（$label）', (tester) async {
      await _openBank(tester, size);

      expect(_inBank(find.byType(SetRowCard)), findsOneWidget);
      for (final t in _practiceTitles) {
        expect(_inBank(find.text(t)), findsWidgets, reason: t);
      }
      expect(_paragraph(tester, _setSubtitle).didExceedMaxLines, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('F5/F10 默认显示 1 张练习套卷卡与练习/考试两个 tab（$label）', (tester) async {
      await _openBank(tester, size);

      expect(_inBank(find.text('搜索题目')), findsOneWidget);
      expect(_inBank(find.text('练习')), findsOneWidget);
      expect(_inBank(find.text('考试')), findsOneWidget);

      expect(_inBank(find.byType(SetRowCard)), findsOneWidget);
      for (final t in _practiceTitles) {
        expect(_inBank(find.text(t)), findsWidgets);
      }
      expect(_inBank(find.text(_setSubtitle)), findsOneWidget);
      expect(_inBank(find.text('100题')), findsWidgets);
      for (final t in const ['错题本', '收藏']) {
        expect(_inBank(find.text(t)), findsNothing);
      }
      expect(_inBank(find.text('H3CNE 模拟卷 A')), findsNothing);
    });

    testWidgets('F5/F10 点考试显示 2 张真实模拟卷卡并隐藏练习卡（$label）', (tester) async {
      await _openBank(tester, size);

      await tester.tap(_inBank(find.text('考试')));
      await tester.pumpAndSettle();

      expect(_inBank(find.byType(SetRowCard)), findsNWidgets(2));
      for (final t in _paperTitles) {
        expect(_inBank(find.text(t)), findsOneWidget);
      }
      expect(_inBank(find.text(_setSubtitle)), findsNWidgets(2));
      for (final tag in const ['H3CNE', '模拟', '100题']) {
        expect(_inBank(find.text(tag)), findsWidgets);
      }
      // 练习卡不在考试 tab：按卡片标题判，不能按文本判（模拟卷卡的标签
      // 里也有 “H3CNE”）。
      final examCards = tester
          .widgetList<SetRowCard>(_inBank(find.byType(SetRowCard)))
          .toList();
      expect(examCards.map((card) => card.title), _paperTitles);
      expect(_inBank(find.text('练习')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('F5/F10 点练习切回练习套卷卡（$label）', (tester) async {
      await _openBank(tester, size);

      await tester.tap(_inBank(find.text('考试')));
      await tester.pumpAndSettle();
      expect(_inBank(find.text('H3CNE 模拟卷 A')), findsOneWidget);

      await tester.tap(_inBank(find.text('练习')));
      await tester.pumpAndSettle();
      expect(_inBank(find.byType(SetRowCard)), findsOneWidget);
      for (final t in _practiceTitles) {
        expect(_inBank(find.text(t)), findsWidgets);
      }
      expect(_inBank(find.text('H3CNE 模拟卷 A')), findsNothing);
    });

    testWidgets('H 标题下副标题为“练习考试”（$label）', (tester) async {
      await _openBank(tester, size);

      expect(_inBank(find.text('练习考试')), findsOneWidget);
      expect(_inBank(find.textContaining('每套含解析')), findsNothing);
    });

    testWidgets('F5 搜索仍显示题目结果列表（$label）', (tester) async {
      await _openBank(tester, size);

      final samples = await ServiceLocator.questionRepository.drawQuestions(
        mode: 'practice',
        drawCount: 100,
      );
      final searchField = _inBank(find.byType(TextField));
      await tester.enterText(searchField, samples.first.stem);
      await tester.pumpAndSettle();

      expect(_inBank(find.byType(ListTile)), findsWidgets);
      expect(_inBank(find.text('没有找到相关题目')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('A/F5 深色模式：tab 与套卷卡跟随深色主题，不再是固定白底', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await _openBank(tester, const Size(410, 890));

    final scheme = Theme.of(tester.element(find.byType(BankModuleListPage)))
        .colorScheme;
    const darkTitle = Color(0xFFFFFFFF);
    final activeTab = tester.widget<Text>(_inBank(find.text('练习')));
    expect(activeTab.style?.color, darkTitle);
    expect(activeTab.style?.color, scheme.onSurface);

    final inactiveTab = tester.widget<Text>(_inBank(find.text('考试')));
    expect(inactiveTab.style?.color, scheme.onSurfaceVariant);

    // 套卷卡：深色 surface 卡片 + 深色主题文字，文字与底色不得相同。
    final surface = tester
        .widget<Material>(
          find
              .descendant(
                of: find.byType(SetRowCard).first,
                matching: find.byType(Material),
              )
              .first,
        )
        .color;
    expect(surface, scheme.surface);
    expect(surface, isNot(AppColors.brandSurface));
    final card = find.byType(SetRowCard).first;
    final cardTitle = tester.widget<Text>(
      find.descendant(of: card, matching: find.text('H3CNE')).first,
    );
    final cardSubtitle = tester.widget<Text>(
      find.descendant(of: card, matching: find.text(_setSubtitle)),
    );
    expect(cardTitle.style?.color, scheme.onSurface);
    expect(cardSubtitle.style?.color, scheme.onSurfaceVariant);
    expect(cardTitle.style?.color, isNot(surface));
    expect(cardSubtitle.style?.color, isNot(surface));

    // 模块标签：深色 chip 上的浅灰文字同样与 chip 底色不同。
    final firstTag = _inBank(find.byType(ModuleTag)).first;
    final tagBox = tester.widget<Container>(
      find.descendant(of: firstTag, matching: find.byType(Container)).first,
    );
    final tagSurface = (tagBox.decoration! as BoxDecoration).color;
    final tagText = tester.widget<Text>(
      find.descendant(of: firstTag, matching: find.byType(Text)),
    );
    expect(tagText.style?.color, isNot(tagSurface));
  });

  testWidgets('F10 下拉刷新重新拉取练习 / 考试清单', (tester) async {
    tester.view.physicalSize = const Size(410, 890);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final service = _CountingManifestService(MockBankManifestService());
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: BankModuleListPage(manifestService: service),
      ),
    );
    await tester.pumpAndSettle();
    expect(service.fetchCount, 1);
    expect(find.byType(SetRowCard), findsOneWidget);

    // 下拉 -> RefreshIndicator 出现并重新调用 fetchManifest。
    await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();

    expect(service.fetchCount, 2);
    expect(find.byType(RefreshIndicator), findsOneWidget);
    expect(find.byType(SetRowCard), findsOneWidget);
    expect(find.text(_setSubtitle), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
