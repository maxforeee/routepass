import 'package:flutter/material.dart';

import '../core/theme.dart';

/// RoutePass 品牌 Logo：宝蓝圆角方块 + 白色三节点网络连线（三角形）。
///
/// 启动页（72）与登录页（56）共用同一绘制，圆角与内部几何随 [size] 等比缩放
/// （72 → 圆角 16，56 → 约 12）。颜色固定用品牌 token，不随深浅色模式变化。
class RoutePassLogo extends StatelessWidget {
  const RoutePassLogo({super.key, required this.size});

  /// 逻辑像素边长（正方形，宽 = 高 = size）。
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _RoutePassLogoPainter(),
    );
  }
}

class _RoutePassLogoPainter extends CustomPainter {
  static const double _cornerRadiusRatio = 1 / 4.5;
  static const double _lineWidthRatio = 0.055;
  static const double _nodeRadiusRatio = 0.105;

  // 三个节点构成三角形：顶部居中，左下、右下对称。
  static const List<double> _nodeXs = [0.50, 0.26, 0.74];
  static const List<double> _nodeYs = [0.30, 0.72, 0.72];

  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.width;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(s * _cornerRadiusRatio),
      ),
      Paint()..color = AppColors.brandPrimary,
    );

    final List<Offset> nodes = [
      for (int i = 0; i < _nodeXs.length; i++)
        Offset(s * _nodeXs[i], s * _nodeYs[i]),
    ];

    final Paint linePaint = Paint()
      ..color = AppColors.brandOnPrimary
      ..strokeWidth = s * _lineWidthRatio
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < nodes.length; i++) {
      canvas.drawLine(nodes[i], nodes[(i + 1) % nodes.length], linePaint);
    }

    final Paint nodePaint = Paint()..color = AppColors.brandOnPrimary;
    for (final Offset node in nodes) {
      canvas.drawCircle(node, s * _nodeRadiusRatio, nodePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
