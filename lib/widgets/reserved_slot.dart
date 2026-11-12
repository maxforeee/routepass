/// 预留容器（R5：套卷详情页占位组件）。
///
/// 固定高 64、圆角 14、浅灰边框，居中一行提示文字；
/// 现在保持为空，后续在这里加真实内容（不许删除或填充）。
library;

import 'package:flutter/material.dart';

import '../core/theme.dart';

class ReservedSlot extends StatelessWidget {
  const ReservedSlot({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: AppSizes.setDetailReservedSlotHeight,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.pageBackground(context),
        borderRadius: BorderRadius.circular(AppRadii.input),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Text(
        '预留容器 · 以后在这里加内容',
        style: theme.textTheme.bodySmall?.copyWith(
          fontSize: AppFontSizes.pageSubtitle,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
