/// F20 动画规范 §6（输入框）与 §7（长按）的行为测试。
///
/// 覆盖共享工具 [Pressable] 长按蓄力 / 400ms 触觉、[FocusIndicator] 获焦
/// 指示线、[ClearButtonReveal] 清除按钮显隐、[ErrorShake] 报错抖动、
/// [AnimatedErrorText] 错误文案进出，以及 [AppSearchBar] 的清除按钮与获焦
/// 指示线接线。全部自包含，不依赖服务注入。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/core/app_animations.dart';
import 'package:routepass/widgets/app_search_bar.dart';

void main() {
  testWidgets('§7 Pressable 长按蓄力缩到 0.96，400ms 触发 heavyImpact，释放回 1.0', (
    tester,
  ) async {
    final haptics = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') haptics.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    var longPressed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Pressable(
              onLongPress: () => longPressed = true,
              child: const SizedBox(width: 120, height: 48),
            ),
          ),
        ),
      ),
    );

    double scaleValue() => tester
        .widget<ScaleTransition>(
          find.descendant(
            of: find.byType(Pressable),
            matching: find.byType(ScaleTransition),
          ),
        )
        .scale
        .value;

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(Pressable)),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(haptics, isEmpty, reason: '400ms 阈值未到不应触发触觉');
    await tester.pump(const Duration(milliseconds: 100));
    expect(haptics, hasLength(1));
    expect(haptics.single.arguments, 'HapticFeedbackType.heavyImpact');
    await tester.pump(const Duration(milliseconds: 100));
    expect(longPressed, isTrue, reason: '500ms 手势长按识别');
    await tester.pump(const Duration(milliseconds: 200));
    expect(scaleValue(), moreOrLessEquals(0.96, epsilon: 0.001));
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(scaleValue(), moreOrLessEquals(1.0, epsilon: 0.001));
  });

  testWidgets('§6 FocusIndicator 获焦 200ms 展开、失焦 150ms 收回', (tester) async {
    Widget build(bool focused) => MaterialApp(
      home: Scaffold(
        body: FocusIndicator(focused: focused, color: Colors.blue),
      ),
    );
    double widthFactor() => tester
        .widget<FractionallySizedBox>(find.byType(FractionallySizedBox))
        .widthFactor!;

    await tester.pumpWidget(build(false));
    expect(widthFactor(), 0.0);
    await tester.pumpWidget(build(true));
    await tester.pump(const Duration(milliseconds: 100));
    expect(widthFactor(), greaterThan(0.0));
    expect(widthFactor(), lessThan(1.0));
    await tester.pump(const Duration(milliseconds: 100));
    expect(widthFactor(), moreOrLessEquals(1.0, epsilon: 0.001));
    await tester.pumpWidget(build(false));
    await tester.pump(const Duration(milliseconds: 150));
    expect(widthFactor(), moreOrLessEquals(0.0, epsilon: 0.001));
  });

  testWidgets('§6 ClearButtonReveal 淡入放大出现、淡出缩小收起并回调 onExited', (tester) async {
    var exited = false;
    Widget build(bool visible) => MaterialApp(
      home: Scaffold(
        body: ClearButtonReveal(
          visible: visible,
          onExited: () => exited = true,
          child: const Icon(Icons.clear),
        ),
      ),
    );
    FadeTransition fade() => tester.widget<FadeTransition>(
      find.descendant(
        of: find.byType(ClearButtonReveal),
        matching: find.byType(FadeTransition),
      ),
    );
    double scale() => tester
        .widget<Transform>(
          find.descendant(
            of: find.byType(ClearButtonReveal),
            matching: find.byType(Transform),
          ),
        )
        .transform
        .getMaxScaleOnAxis();

    await tester.pumpWidget(build(false));
    expect(fade().opacity.value, 0.0);
    expect(scale(), moreOrLessEquals(0.5, epsilon: 0.001));
    await tester.pumpWidget(build(true));
    await tester.pump(const Duration(milliseconds: 150));
    expect(fade().opacity.value, moreOrLessEquals(1.0, epsilon: 0.001));
    expect(scale(), moreOrLessEquals(1.0, epsilon: 0.001));
    await tester.pumpWidget(build(false));
    await tester.pump(const Duration(milliseconds: 75));
    expect(fade().opacity.value, lessThan(1.0));
    expect(exited, isFalse, reason: '退出动画未播完不应回调');
    await tester.pump(const Duration(milliseconds: 75));
    expect(exited, isTrue);
    expect(fade().opacity.value, 0.0);
  });

  testWidgets('§6 ErrorShake 报错进入抖动一次，200ms 后回到原位', (tester) async {
    Widget build(bool hasError) => MaterialApp(
      home: Scaffold(
        body: ErrorShake(
          hasError: hasError,
          child: const SizedBox(width: 100, height: 40),
        ),
      ),
    );
    double offsetX() => tester
        .widget<Transform>(
          find.descendant(
            of: find.byType(ErrorShake),
            matching: find.byType(Transform),
          ),
        )
        .transform
        .getTranslation()
        .x;

    await tester.pumpWidget(build(false));
    expect(offsetX(), 0.0);
    await tester.pumpWidget(build(true));
    await tester.pump(const Duration(milliseconds: 50));
    expect(offsetX(), isNonZero);
    await tester.pump(const Duration(milliseconds: 150));
    expect(offsetX(), moreOrLessEquals(0.0, epsilon: 0.001));
  });

  testWidgets('§6 AnimatedErrorText 错误文案淡入上移、解除后移出树', (tester) async {
    Widget build(String? error) => MaterialApp(
      home: Scaffold(body: AnimatedErrorText(errorText: error)),
    );
    FadeTransition fade() => tester.widget<FadeTransition>(
      find.descendant(
        of: find.byType(AnimatedErrorText),
        matching: find.byType(FadeTransition),
      ),
    );

    await tester.pumpWidget(build(null));
    expect(find.text('请输入手机号码'), findsNothing);
    await tester.pumpWidget(build('请输入手机号码'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(fade().opacity.value, greaterThan(0.0));
    expect(fade().opacity.value, lessThan(1.0));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('请输入手机号码'), findsOneWidget);
    expect(fade().opacity.value, moreOrLessEquals(1.0, epsilon: 0.001));
    await tester.pumpWidget(build(null));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('请输入手机号码'), findsNothing);
  });

  testWidgets('§6 AppSearchBar 清除按钮随文本出现、清空时播完退出动画才移除', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppSearchBar(controller: controller, hintText: '搜索'),
        ),
      ),
    );
    expect(find.byIcon(Icons.clear), findsNothing);

    await tester.enterText(find.byType(TextField), '路由');
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.clear), findsOneWidget);
    final indicator = tester.widget<FractionallySizedBox>(
      find.descendant(
        of: find.byType(FocusIndicator),
        matching: find.byType(FractionallySizedBox),
      ),
    );
    expect(indicator.widthFactor, moreOrLessEquals(1.0, epsilon: 0.001));

    await tester.tap(find.byIcon(Icons.clear));
    await tester.pump();
    expect(controller.text, isEmpty);
    expect(
      find.byIcon(Icons.clear),
      findsOneWidget,
      reason: '退出动画播放期间清除按钮仍应在树中',
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.clear), findsNothing);
  });
}
