import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/core/theme.dart';
import 'package:routepass/pages/bank/module_list_page.dart';
import 'package:routepass/widgets/capsule_nav_bar.dart';
import 'package:routepass/widgets/user_avatar.dart';

import 'test_helpers.dart';

/// F3（用户反馈 B1 / H3 / B3 / O1）回归：题库页标题字号与左对齐、头像只在
/// 首页、套卷行标题与副标题完整显示。两个视口（手机 410 / 平板 800）各跑一遍。
const _viewports = <Size>[Size(410, 890), Size(800, 1400)];

const _setTitles = <String>['100 题套卷', '200 题套卷', '50 题套卷', '10 题速练'];

const _setSubtitles = <String>[
  '100 题 · 5 个模块 · 含解析',
  '200 题 · 5 个模块 · 含解析',
  '50 题 · 5 个模块 · 含解析',
  '10 题 · 5 个模块 · 含解析',
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

    testWidgets('B1 题库标题 32px 且无头像（$label）', (tester) async {
      await _openBank(tester, size);

      final title = tester.widget<Text>(_inBank(find.text('题库')));
      expect(title.style?.fontSize, AppFontSizes.homeGreetingName);
      expect(title.style?.fontSize, 32);

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

    testWidgets('B2 六行入口与搜索条齐全（$label）', (tester) async {
      await _openBank(tester, size);

      expect(_inBank(find.text('搜索题目')), findsOneWidget);
      for (final t in _setTitles) {
        expect(_inBank(find.text(t)), findsOneWidget);
      }
      for (final t in const ['错题本', '收藏']) {
        expect(_inBank(find.text(t)), findsOneWidget);
      }
      for (final tag in const ['VLAN', 'OSPF', 'ACL', 'NAT', '子网划分']) {
        expect(_inBank(find.text(tag)), findsWidgets);
      }
    });
  }
}
