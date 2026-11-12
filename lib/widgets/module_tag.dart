/// 共享模块小标签（M7 收敛：首页 / 题库套卷卡共用）。
library;

import 'package:flutter/material.dart';

import '../core/theme.dart';

class ModuleTag extends StatelessWidget {
  const ModuleTag({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppSpacing.xs),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelSmall?.copyWith(
          fontSize: AppFontSizes.setCardTag,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
