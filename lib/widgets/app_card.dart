/// 共享卡片壳（M7 收敛：首页 / 题库 / 工具箱共用）。
///
/// 白底面、圆角 16、outlineVariant 边框（1px）、裁剪抗锯齿、InkWell。
/// 默认内边距 16；内边距不同的卡片调用时传 padding。
/// F20 §8：整卡按压缩到 0.98、elevation 1dp → 4dp（100ms），释放回 1.0 / 1dp
/// （150ms），均 fastOutSlowIn；点按仍由卡内 InkWell 处理，接线不变。
library;

import 'package:flutter/material.dart';

import '../core/app_animations.dart';
import '../core/theme.dart';

class AppCard extends StatefulWidget {
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
  State<AppCard> createState() => _AppCardState();
}

class _AppCardState extends State<AppCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Pressable(
      scale: Pressable.cardScale,
      pressCurve: AppDurations.standard,
      onPressedChanged: (pressed) => setState(() => _pressed = pressed),
      child: Material(
        color: theme.colorScheme.surface,
        elevation: _pressed
            ? Pressable.cardPressElevation
            : Pressable.cardRestElevation,
        animationDuration: _pressed ? AppDurations.xs : AppDurations.s,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
          side: BorderSide(
            color: theme.colorScheme.outlineVariant,
            width: AppSizes.borderWidth,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          child: Padding(padding: widget.padding, child: widget.child),
        ),
      ),
    );
  }
}
