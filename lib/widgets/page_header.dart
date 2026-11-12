import 'package:flutter/material.dart';

import '../core/theme.dart';

/// 品牌页页头：标题（22 粗体）+ 副标题（13 灰），左对齐。
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
        Text(
          title,
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
