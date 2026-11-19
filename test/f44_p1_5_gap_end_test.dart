/// F44 P1-5 回归：大字号无障碍缩放下，legend 缺口右端不得擦掉右上圆角弧线。
///
/// 修复前 `DailyCardBorderPainter.paint` 的 BlendMode.clear 横线直接画到
/// 原始 gapEnd；320dp 视口 + textScale 2.0 时错题本标题缺口约 142dp，
/// 超过方块宽约 137dp，右上角圆弧被一起擦掉。修复后缺口右端夹到
/// size.width - radius（paint 内部，不改构造参数，调用点零改动）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/core/kv_store.dart';
import 'package:routepass/core/service_locator.dart';
import 'package:routepass/core/theme.dart';
import 'package:routepass/pages/home/home_content.dart';

import 'test_helpers.dart';

/// 在给定尺寸下真实执行 paint()，取出擦除缺口的那条 clear 横线端点。
(Offset, Offset) _clearLine(DailyCardBorderPainter painter, Size size) {
  final canvas = TestRecordingCanvas();
  painter.paint(canvas, size);
  final line = canvas.invocations.firstWhere(
    (inv) =>
        inv.invocation.memberName == #drawLine &&
        (inv.invocation.positionalArguments[2] as Paint).blendMode ==
            BlendMode.clear,
  );
  return (
    line.invocation.positionalArguments[0] as Offset,
    line.invocation.positionalArguments[1] as Offset,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initTestServices();

  setUp(() {
    // KvStore 是进程级静态实例，清掉每日一练作答状态，避免测试间串扰。
    ServiceLocator.kvStore.remove(KvStore.keyDailyAnswer);
  });

  test('F44 P1-5 画笔单元：缺口右端夹到 width - radius，gapStart 不变', () {
    // 320dp 视口下方块约 137 宽，2.0 字号下错题本缺口约 142（复现评审数值）。
    const painter = DailyCardBorderPainter(
      color: Color(0xFF123456),
      radius: 16,
      gapStart: 20,
      gapEnd: 142,
    );
    final (start, end) = _clearLine(painter, const Size(137, 137));
    expect(start.dx, 20);
    // 修复前 end.dx == 142，clear 线越过 121 进入右上圆角弧线区。
    expect(end.dx, 137 - 16);
  });

  test('F44 P1-5 画笔单元：正常宽度的缺口不被过度夹取', () {
    const painter = DailyCardBorderPainter(
      color: Color(0xFF123456),
      radius: 16,
      gapStart: 20,
      gapEnd: 80,
    );
    final (start, end) = _clearLine(painter, const Size(300, 100));
    expect(start.dx, 20);
    expect(end.dx, 80);
  });

  testWidgets('F44 P1-5 320dp + textScale 2.0 方块：右上圆角保住，无溢出', (tester) async {
    // 窄视口复现评审场景；高度给足，让每日一练下方的方块同屏挂载。
    tester.view.physicalSize = const Size(320, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await ServiceLocator.authService.logout();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2.0)),
            child: HomeContentPage(onSelectTab: (_) {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 大字号下整页（含两块方块）无布局溢出。
    expect(tester.takeException(), isNull);

    for (final name in ['wrong', 'favorites']) {
      final tile = find.byKey(ValueKey('home-tile-$name'));
      final tileRect = tester.getRect(tile);
      final border =
          tester
                  .widget<CustomPaint>(
                    find
                        .descendant(
                          of: tile,
                          matching: find.byType(CustomPaint),
                        )
                        .first,
                  )
                  .painter!
              as DailyCardBorderPainter;
      final safeEnd = tileRect.width - border.radius;

      if (name == 'wrong') {
        // 回归场景前提：三字标题在 2.0 字号下缺口真的越过圆角安全区，
        // 否则本用例没有复现 bug（修复前 clear 线会擦掉右上圆弧）。
        expect(border.gapEnd, greaterThan(safeEnd));
      }

      // 用方块真实尺寸执行画笔，断言 clear 线的实际落点，而非构造参数。
      final (start, end) = _clearLine(border, tileRect.size);
      expect(start.dx, border.gapStart);
      // 圆角不变量：clear 线永远不进入右上圆弧区 [width - radius, width]。
      expect(end.dx, lessThanOrEqualTo(safeEnd));
      expect(end.dx, border.gapEnd > safeEnd ? safeEnd : border.gapEnd);
    }
  });
}
