/// F49：120Hz 转场卡顿修复的回归测试。
///
/// 三个确认病因都是「每帧变化的动画包装直接坐在静态大子树上，中间没有
/// repaint boundary」，导致整页/整卡显示列表每帧重录。帧率本身无法在
/// widget test 里断言（真机 120Hz 目视才是最终证明，见
/// /workspace/routepass_redo/f49_120hz_note.md），这里断言的是修复的
/// 结构前提：动画包装与静态内容之间必须存在 RepaintBoundary。
/// 每个断言在修复前都会失败（向上先碰到动画包装而不是边界）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/core/app_animations.dart';
import 'package:routepass/core/page_transition.dart';
import 'package:routepass/core/theme.dart';
import 'package:routepass/pages/base/login_page.dart';
import 'package:routepass/widgets/daily_card_border_painter.dart';

import 'test_helpers.dart';

/// 从 [start] 向上走祖先链：先碰到 [boundary] 返回 true，先碰到 [stop]
/// 返回 false。用于断言「边界在动画包装之下」，而不是树里随便某处有边界。
bool _boundaryBefore(
  WidgetTester tester,
  Finder start,
  bool Function(Widget) boundary,
  bool Function(Widget) stop,
) {
  bool found = false;
  tester.element(start).visitAncestorElements((element) {
    if (boundary(element.widget)) {
      found = true;
      return false;
    }
    if (stop(element.widget)) return false;
    return true;
  });
  return found;
}

bool _isRepaintBoundary(Widget widget) => widget is RepaintBoundary;

/// 转场里随 enter.value 每帧变化的阴影 DecoratedBox（AppColors.shadow）。
bool _isTransitionShadowBox(Widget widget) {
  if (widget is! DecoratedBox) return false;
  final decoration = widget.decoration;
  if (decoration is! BoxDecoration) return false;
  final shadows = decoration.boxShadow;
  return shadows != null &&
      shadows.any((shadow) => shadow.color == AppColors.shadow);
}

void main() {
  setUp(initTestServices);

  testWidgets('SharedAxisPageRoute caches the entering page below the '
      'per-frame shadow decoration', (tester) async {
    const pageKey = ValueKey<String>('f49-entering-page');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(tester.element(find.byType(ElevatedButton))).push(
                  SharedAxisPageRoute<void>(
                    builder: (_) =>
                        const SizedBox(key: pageKey, child: Text('page')),
                  ),
                );
              },
              child: const Text('push'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('push'));
    await tester.pump();
    // 转场进行中（XL 300ms 的中段）：阴影装饰每帧变化。
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.byWidgetPredicate(_isTransitionShadowBox),
      findsOneWidget,
      reason: '转场中段应存在随动画变化的阴影 DecoratedBox',
    );
    expect(
      _boundaryBefore(
        tester,
        find.byKey(pageKey),
        _isRepaintBoundary,
        _isTransitionShadowBox,
      ),
      isTrue,
      reason:
          '页面内容必须先被 RepaintBoundary 缓存，再到每帧变化的阴影'
          ' DecoratedBox；否则阴影每帧把整页显示列表重录一遍',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(pageKey), findsOneWidget);
    expect(find.text('page'), findsOneWidget);
  });

  testWidgets('login blob repaints stay inside their own layer (light)', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: LoginPage()));
    await tester.pump();
    // 环境漂移无限循环，只推几帧验证结构，不能 pumpAndSettle。
    await tester.pump(const Duration(milliseconds: 100));
    final blob = find.byWidgetPredicate(
      (widget) =>
          widget is SizedBox && widget.width == 141 && widget.height == 123,
    );
    expect(blob, findsOneWidget);
    expect(
      _boundaryBefore(
        tester,
        blob,
        _isRepaintBoundary,
        (widget) => widget is SingleChildScrollView,
      ),
      isTrue,
      reason:
          'blob 每帧形变/漂移的重绘必须被 RepaintBoundary 隔离在图形层内，'
          '不能冒泡到整页（转场期间登录页是被压栈页，同样被牵连）',
    );
  });

  testWidgets('login bubble repaints stay inside their own layer (dark)', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: const LoginPage(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final cluster = find.byWidgetPredicate(
      (widget) =>
          widget is SizedBox && widget.width == 126 && widget.height == 108,
    );
    expect(cluster, findsOneWidget);
    expect(
      _boundaryBefore(
        tester,
        cluster,
        _isRepaintBoundary,
        (widget) => widget is SingleChildScrollView,
      ),
      isTrue,
      reason:
          '7 个渐变+模糊阴影气泡每帧重建重绘，必须被 RepaintBoundary '
          '隔离在气泡簇层内',
    );
  });

  testWidgets('StaggeredListAppear caches item content below the fade', (
    tester,
  ) async {
    const itemKey = ValueKey<String>('f49-stagger-item');
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StaggeredListAppear(
            index: 0,
            slideOffsetDp: StaggeredListAppear.listSlideOffsetDp,
            child: SizedBox(key: itemKey, child: Text('item')),
          ),
        ),
      ),
    );
    // 入场进行中（L 250ms 的中段）：透明度每帧变化。
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      _boundaryBefore(
        tester,
        find.byKey(itemKey),
        _isRepaintBoundary,
        (widget) => widget is FadeTransition,
      ),
      isTrue,
      reason:
          '交错入场与页面 push 并行；卡片内容必须先被 RepaintBoundary '
          '缓存，FadeTransition 每帧只合成，不重录卡片文字/标签',
    );
    await tester.pumpAndSettle();
    expect(find.text('item'), findsOneWidget);
  });

  group(
    'DailyCardBorderPainter.shouldRepaint (F49 audit: already correct)',
    () {
      const painter = DailyCardBorderPainter(
        color: Color(0xFF2563EB),
        radius: 16,
        gapStart: 24,
        gapEnd: 120,
      );

      test('identical inputs do not repaint', () {
        expect(
          painter.shouldRepaint(
            const DailyCardBorderPainter(
              color: Color(0xFF2563EB),
              radius: 16,
              gapStart: 24,
              gapEnd: 120,
            ),
          ),
          isFalse,
        );
      });

      test('any changed input repaints', () {
        expect(
          painter.shouldRepaint(
            const DailyCardBorderPainter(
              color: Color(0xFF0F172A),
              radius: 16,
              gapStart: 24,
              gapEnd: 120,
            ),
          ),
          isTrue,
        );
        expect(
          painter.shouldRepaint(
            const DailyCardBorderPainter(
              color: Color(0xFF2563EB),
              radius: 12,
              gapStart: 24,
              gapEnd: 120,
            ),
          ),
          isTrue,
        );
        expect(
          painter.shouldRepaint(
            const DailyCardBorderPainter(
              color: Color(0xFF2563EB),
              radius: 16,
              gapStart: 20,
              gapEnd: 120,
            ),
          ),
          isTrue,
        );
        expect(
          painter.shouldRepaint(
            const DailyCardBorderPainter(
              color: Color(0xFF2563EB),
              radius: 16,
              gapStart: 24,
              gapEnd: 140,
            ),
          ),
          isTrue,
        );
      });
    },
  );
}
