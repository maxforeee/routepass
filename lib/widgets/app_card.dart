/// 共享卡片壳（M7 收敛：首页 / 题库 / 工具箱共用）。
///
/// 白底面、圆角 16、outlineVariant 边框（1px）、裁剪抗锯齿、InkWell。
/// 默认内边距 16；内边距不同的卡片调用时传 padding。
library;

import 'package:flutter/material.dart';

import '../core/theme.dart';

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(AppSpacing.md),
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.card),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant,
          width: AppSizes.borderWidth,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
