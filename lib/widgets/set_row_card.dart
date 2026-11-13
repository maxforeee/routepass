/// 共享套卷行卡片（首页题库区 / 题库页共用）。
///
/// 白底面、圆角 16、固定高 76（setRowMinHeight）；左 = 标题 + 灰色副标题，
/// 右 = trailing 组件，整行可点按。品牌色固定（不随深浅色模式变化），与
/// mockup 一致。
library;

import 'package:flutter/material.dart';

import '../core/theme.dart';

class SetRowCard extends StatelessWidget {
  const SetRowCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.leading,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final Widget trailing;
  final Widget? leading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final subtitleStyle = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: AppColors.brandCaption);
    return SizedBox(
      height: AppSizes.setRowMinHeight,
      child: Material(
        color: AppColors.brandSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
          side: const BorderSide(
            color: AppColors.brandBorder,
            width: AppSizes.borderWidth,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Row(
              children: [
                if (leading != null) ...[
                  leading!,
                  const SizedBox(width: AppSpacing.sm),
                ],
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: AppFontSizes.entryTitle,
                          fontWeight: FontWeight.bold,
                          color: AppColors.brandTitle,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      // 右侧标签组占位后副标题仍须完整显示：允许折成两行
                      // （76 高卡片内标题 23 + 间距 4 + 两行 36 = 63）。
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: subtitleStyle,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
