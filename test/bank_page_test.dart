import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/core/service_locator.dart';
import 'package:routepass/core/theme.dart';
import 'package:routepass/pages/bank/module_list_page.dart';
import 'package:routepass/widgets/capsule_nav_bar.dart';
import 'package:routepass/widgets/module_tag.dart';
import 'package:routepass/widgets/page_header.dart';
import 'package:routepass/widgets/set_row_card.dart';
import 'package:routepass/widgets/user_avatar.dart';

import 'test_helpers.dart';

/// F3（用户反馈 B1 / H3 / B3 / O1）回归 + F5（练习/考试切换、去副标题、
/// 移除错题本/收藏入口）回归：题库页标题字号与左对齐、头像只在首页、套卷行
/// 标题与副标题完整显示、两个 tab 切换下方列表。两个视口（手机 410 / 平板
/// 800）各跑一遍。
const _viewports = <Size>[Size(410, 890), Size(800, 1400)];

const _setTitles = <String>['100 题套卷', '200 题套卷', '50 题套卷', '10 题速练'];

const _setSubtitles = <String>[
  '100 题 · 5 个模块 · 含解析',
  '200 题 · 5 个模块 · 含解析',
  '50 题 · 5 个模块 · 含解析',
  '10 题 · 5 个模块 · 含解析',
];

const _paperTitles = <String>[
  'H3CNE 模拟卷 01',
  'H3CNE 模拟卷 02',
  'H3CNE 模拟卷 03',
  'H3CNE 模拟卷 04',
  'H3CNE 模拟卷 05',
  'H3CNE 模拟卷 06',
];

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initTestServices();

  for (final size in _viewports) {
    final label = '${size.width.toInt()}x${size.height.toInt()}';

    testWidgets('H 题库页头与知识库/工具箱一致（PageHeader 22px + 练习考试）（$label）', (
      tester,
    ) async {
      await _openBank(tester, size);

      expect(_inBank(find.byType(PageHeader)), findsOneWidget);
      final title = tester.widget<Text>(_inBank(find.text('题库')));
      // 与页 3 / 页 4 相同的 titleLarge 字号与粗体。
      expect(title.style?.fontSize, 22);
      expect(title.style?.fontWeight, FontWeight.bold);

      final subtitle = tester.widget<Text>(_inBank(find.text('练习考试')));
      expect(subtitle.style?.fontSize, AppFontSizes.pageSubtitle);

      expect(_inBank(find.byType(UserAvatar)), findsNothing);
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

    testWidgets('O1 四张套卷行标题与副标题不截断（$label）', (tester) async {
      await _openBank(tester, size);

      for (final t in _setTitles) {
        expect(_paragraph(tester, t).didExceedMaxLines, isFalse, reason: t);
      }
      for (final s in _setSubtitles) {
        expect(_paragraph(tester, s).didExceedMaxLines, isFalse, reason: s);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('F5 默认显示 4 张练习套卷卡与练习/考试两个 tab（$label）', (tester) async {
      await _openBank(tester, size);

      expect(_inBank(find.text('搜索题目')), findsOneWidget);
      expect(_inBank(find.text('练习')), findsOneWidget);
      expect(_inBank(find.text('考试')), findsOneWidget);

      for (final t in _setTitles) {
        expect(_inBank(find.text(t)), findsOneWidget);
      }
      for (final t in const ['错题本', '收藏']) {
        expect(_inBank(find.text(t)), findsNothing);
      }
      for (final tag in const ['VLAN', 'OSPF', 'ACL', 'NAT', '子网划分']) {
        expect(_inBank(find.text(tag)), findsWidgets);
      }
      expect(_inBank(find.text('H3CNE 模拟卷 01')), findsNothing);
    });

    testWidgets('F5 点考试显示 6 张模拟卷卡并隐藏练习卡（$label）', (tester) async {
      await _openBank(tester, size);

      await tester.tap(_inBank(find.text('考试')));
      await tester.pumpAndSettle();

      for (final t in _paperTitles) {
        expect(_inBank(find.text(t)), findsOneWidget);
      }
      expect(_inBank(find.text('100 题 · 60 分钟 · 含解析')), findsWidgets);
      for (final tag in const ['综合', 'H3CNE', '模拟', '60分钟', '100题']) {
        expect(_inBank(find.text(tag)), findsWidgets);
      }
      for (final t in _setTitles) {
        expect(_inBank(find.text(t)), findsNothing);
      }
      expect(_inBank(find.text('练习')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('F5 点练习切回 4 张练习套卷卡（$label）', (tester) async {
      await _openBank(tester, size);

      await tester.tap(_inBank(find.text('考试')));
      await tester.pumpAndSettle();
      expect(_inBank(find.text('H3CNE 模拟卷 01')), findsOneWidget);

      await tester.tap(_inBank(find.text('练习')));
      await tester.pumpAndSettle();
      for (final t in _setTitles) {
        expect(_inBank(find.text(t)), findsOneWidget);
      }
      expect(_inBank(find.text('H3CNE 模拟卷 01')), findsNothing);
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
    const darkTitle = Color(0xFFF1F5F9);
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
    final cardTitle = tester.widget<Text>(_inBank(find.text('100 题套卷')));
    final cardSubtitle = tester.widget<Text>(
      _inBank(find.text('100 题 · 5 个模块 · 含解析')),
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
}
