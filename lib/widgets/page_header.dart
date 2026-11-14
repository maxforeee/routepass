import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'animated_title.dart';

/// 品牌页页头：标题（22 粗体）+ 副标题（13 灰），左对齐。
///
/// 标题复用 [AnimatedTitle]（F20 §3）：标题变化 / 首次挂载时播放与顶部栏一致的
/// 「淡入 + 8dp 下滑归位」进入动画，内容页头与顶部栏标题动效统一。
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedTitle(
          title: title,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: AppFontSizes.pageSubtitle,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
