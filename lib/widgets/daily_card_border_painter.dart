/// 每日一练 / 答题记录卡片的圆角边框：上边框在标题位置留出真实缺口
/// （擦除，不用背景色盖住），标题透明地坐在缺口里。
///
/// F19：从 `pages/home/home_content.dart` 原样搬出，供首页每日一练、
/// 错题本 / 收藏方块与答题记录卡共用；`home_content.dart` 保留 export，
/// 旧 import 路径的测试与调用点继续编译，视觉零变化。
library;

import 'package:flutter/material.dart';

class DailyCardBorderPainter extends CustomPainter {
  const DailyCardBorderPainter({
    required this.color,
    required this.radius,
    required this.gapStart,
    required this.gapEnd,
  });

  final Color color;
  final double radius;
  final double gapStart;
  final double gapEnd;

  /// 首页三块 legend 卡片专用描边宽度。比共享的 AppSizes.borderWidth 粗一档，
  /// 且不改动该 token，避免影响 AppCard / SetRowCard 等其他卡片。
  static const double strokeWidth = 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..color = color,
    );
    // 擦掉标题覆盖段的上边框，形成 fieldset-legend 式缺口。
    canvas.drawLine(
      Offset(gapStart, 0),
      Offset(gapEnd, 0),
      Paint()
        ..blendMode = BlendMode.clear
        ..strokeWidth = strokeWidth * 3,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(DailyCardBorderPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.radius != radius ||
        oldDelegate.gapStart != gapStart ||
        oldDelegate.gapEnd != gapEnd;
  }
}
