import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/core/theme.dart';
import 'package:routepass/pages/bank/module_list_page.dart';
import 'package:routepass/pages/knowledge/knowledge_home_page.dart';
import 'package:routepass/pages/knowledge/knowledge_search_page.dart';
import 'package:routepass/widgets/app_search_bar.dart';
import 'package:routepass/widgets/capsule_nav_bar.dart';

import 'test_helpers.dart';

/// 用户 2026-11-14 反馈的两项搜索修复：
/// 1. 题库页搜索条与知识库页同一套样式（形状 / 颜色 / 提示 / 交互）；
/// 2. 子页返回主页面时搜索框不再自动聚焦，只有点按才聚焦。

const _phone = Size(410, 890);

Finder _navTab(String label) =>
    find.descendant(of: find.byType(CapsuleNavBar), matching: find.text(label));

Finder _searchField(Type page) =>
    find.descendant(of: find.byType(page), matching: find.byType(TextField));

bool _hasFocus(WidgetTester tester, Finder field) {
  final editable = tester.widget<EditableText>(
    find.descendant(of: field, matching: find.byType(EditableText)),
  );
  return editable.focusNode.hasFocus;
}

void _setPhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = _phone;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// 搜索条实测样式快照：两页逐项对比用，不写死字号 / 颜色。
class _SearchMetrics {
  const _SearchMetrics({
    required this.width,
    required this.height,
    required this.left,
    required this.right,
    required this.fillColor,
    required this.hintColor,
    required this.hintSize,
    required this.iconColor,
    required this.iconSize,
    required this.isDense,
    required this.filled,
    required this.radius,
    required this.borderWidth,
    required this.borderStyle,
    required this.contentPadding,
    required this.hintText,
  });

  final double width;
  final double height;
  final double left;
  final double right;
  final Color fillColor;
  final Color hintColor;
  final double? hintSize;
  final Color iconColor;
  final double iconSize;
  final bool isDense;
  final bool filled;
  final BorderRadius radius;
  final double borderWidth;
  final BorderStyle borderStyle;
  final EdgeInsets contentPadding;
  final String hintText;
}

_SearchMetrics _metrics(WidgetTester tester) {
  final bar = find.byType(AppSearchBar);
  expect(bar, findsOneWidget);
  final fieldFinder = find.descendant(
    of: bar,
    matching: find.byType(TextField),
  );
  final field = tester.widget<TextField>(fieldFinder);
  final decoration = field.decoration!;
  final border = decoration.border! as OutlineInputBorder;
  final icon = tester.widget<Icon>(
    find.descendant(of: fieldFinder, matching: find.byIcon(Icons.search)),
  );
  final rect = tester.getRect(bar);
  return _SearchMetrics(
    width: rect.width,
    height: rect.height,
    left: rect.left,
    right: rect.right,
    fillColor: decoration.fillColor!,
    hintColor: decoration.hintStyle!.color!,
    hintSize: decoration.hintStyle!.fontSize,
    iconColor: icon.color!,
    iconSize: icon.size!,
    isDense: decoration.isDense!,
    filled: decoration.filled!,
    radius: border.borderRadius,
    borderWidth: border.borderSide.width,
    borderStyle: border.borderSide.style,
    contentPadding: decoration.contentPadding as EdgeInsets,
    hintText: decoration.hintText!,
  );
}

Future<void> _pumpPage(WidgetTester tester, Widget page) async {
  _setPhoneViewport(tester);
  await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: page));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initTestServices();

  testWidgets('题库搜索条与知识库搜索条样式 / 尺寸 / 位置逐项一致', (tester) async {
    await _pumpPage(tester, const BankModuleListPage());
    final bank = _metrics(tester);

    await _pumpPage(tester, const KnowledgeHomePage());
    final knowledge = _metrics(tester);

    // 形状与位置：等高、同宽、左右都对齐 md 页边距。
    expect(bank.height, AppSizes.searchBarHeight);
    expect(bank.height, knowledge.height);
    expect(bank.width, knowledge.width);
    expect(bank.left, AppSpacing.md);
    expect(bank.left, knowledge.left);
    expect(bank.right, knowledge.right);

    // 颜色：同一浅灰填充、同一提示 / 图标弱化色，跟随主题。
    final scheme = Theme.of(tester.element(find.byType(AppSearchBar)))
        .colorScheme;
    expect(bank.fillColor, knowledge.fillColor);
    expect(bank.fillColor, scheme.surfaceContainerHighest);
    expect(bank.hintColor, knowledge.hintColor);
    expect(bank.hintColor, scheme.onSurfaceVariant);
    expect(bank.iconColor, knowledge.iconColor);
    expect(bank.iconColor, scheme.onSurfaceVariant);

    // 文字与图标尺寸、圆角、无描边、内边距：完全同一套 token。
    expect(bank.hintSize, knowledge.hintSize);
    expect(bank.iconSize, knowledge.iconSize);
    expect(bank.radius, knowledge.radius);
    expect(bank.radius, BorderRadius.circular(AppRadii.search));
    expect(bank.borderStyle, BorderStyle.none);
    expect(bank.borderWidth, knowledge.borderWidth);
    expect(
      bank.contentPadding,
      EdgeInsets.symmetric(horizontal: AppSpacing.md),
    );
    expect(bank.contentPadding, knowledge.contentPadding);
    expect(bank.isDense, isTrue);
    expect(bank.filled, isTrue);
    expect(bank.hintText, '搜索题目');
    expect(knowledge.hintText, '搜索知识点、命令…');

    // 行为：输入后出现同一个清除按钮，点按清空。
    await tester.enterText(find.byType(TextField), '子网');
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.clear), findsOneWidget);
    await tester.tap(find.byIcon(Icons.clear));
    await tester.pumpAndSettle();
    expect(find.text('样例知识点：VLAN 是什么'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('题库：进子页再返回，搜索框不自动聚焦；点按仍可聚焦', (tester) async {
    _setPhoneViewport(tester);
    await loginToHome(tester);
    await tester.tap(_navTab('题库'));
    await tester.pumpAndSettle();

    final field = _searchField(BankModuleListPage);
    expect(_hasFocus(tester, field), isFalse, reason: '初始不自动聚焦');

    await tester.tap(field);
    await tester.pumpAndSettle();
    expect(_hasFocus(tester, field), isTrue, reason: '点按可聚焦');
    expect(tester.testTextInput.isVisible, isTrue);

    // 进套卷详情（真实返回路径：页内返回按钮）。
    await tester.tap(find.text('H3CNE').first);
    await tester.pumpAndSettle();
    expect(find.byTooltip('返回'), findsOneWidget);

    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(_hasFocus(tester, field), isFalse, reason: '返回不自动聚焦');
    expect(tester.testTextInput.isVisible, isFalse, reason: '返回不弹键盘');

    // 点按仍能聚焦。
    await tester.tap(field);
    await tester.pumpAndSettle();
    expect(_hasFocus(tester, field), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('题库：切到别的 tab 再回来，搜索框不自动聚焦', (tester) async {
    _setPhoneViewport(tester);
    await loginToHome(tester);
    await tester.tap(_navTab('题库'));
    await tester.pumpAndSettle();

    final field = _searchField(BankModuleListPage);
    await tester.tap(field);
    await tester.pumpAndSettle();
    expect(_hasFocus(tester, field), isTrue);

    await tester.tap(_navTab('首页'));
    await tester.pumpAndSettle();
    await tester.tap(_navTab('题库'));
    await tester.pumpAndSettle();

    expect(_hasFocus(tester, field), isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('知识库：搜索页返回后搜索框不自动聚焦；点按仍可聚焦', (tester) async {
    _setPhoneViewport(tester);
    await loginToHome(tester);
    await tester.tap(_navTab('知识'));
    await tester.pumpAndSettle();

    final field = _searchField(KnowledgeHomePage);
    expect(_hasFocus(tester, field), isFalse, reason: '初始不自动聚焦');

    await tester.tap(field);
    await tester.pumpAndSettle();
    expect(_hasFocus(tester, field), isTrue);

    // 提交进搜索页（该页自身仍可 autofocus，属于用户主动搜索）。
    await tester.enterText(field, '子网');
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.byType(KnowledgeSearchPage), findsOneWidget);
    // 搜索页自身的 autofocus（用户主动搜索）不受影响。
    final searchPageField = find.descendant(
      of: find.byType(KnowledgeSearchPage),
      matching: find.byType(TextField),
    );
    expect(_hasFocus(tester, searchPageField), isTrue);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(KnowledgeSearchPage), findsNothing);
    expect(_hasFocus(tester, field), isFalse, reason: '返回不自动聚焦');
    expect(tester.testTextInput.isVisible, isFalse);

    await tester.tap(field);
    await tester.pumpAndSettle();
    expect(_hasFocus(tester, field), isTrue);
    expect(tester.takeException(), isNull);
  });
}
