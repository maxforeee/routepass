/// 共享进度环（M7 收敛：首页居中百分比 / 题库百分比在环上方）。
library;

import 'package:flutter/material.dart';

import '../core/theme.dart';

class AppProgressRing extends StatelessWidget {
  const AppProgressRing({
    super.key,
    required this.value,
    this.percentAbove = false,
  });

  final double value;
  final bool percentAbove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percent = (value * 100).round();
    final label = Text(
      '$percent%',
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
    final ring = SizedBox(
      width: percentAbove ? AppSizes.setProgressRing : AppSizes.progressRing,
      height: percentAbove ? AppSizes.setProgressRing : AppSizes.progressRing,
      child: CircularProgressIndicator(
        value: value,
        strokeWidth: AppSizes.ringStroke,
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
    if (percentAbove) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          label,
          const SizedBox(height: AppSpacing.xxs),
          ring,
        ],
      );
    }
    return SizedBox(
      width: AppSizes.progressRing,
      height: AppSizes.progressRing,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ring,
          Center(child: label),
        ],
      ),
    );
  }
}
