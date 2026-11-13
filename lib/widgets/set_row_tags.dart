/// 共享套卷行右侧模块标签组（首页精选题库 / 题库页共用）。
///
/// 按 canva 参考排成 3 列自动宽度的网格（5 个标签 → 两行 3 + 2，列宽取
/// 该列最宽标签），整块宽度只由标签自身决定，因此不会再把左侧标题挤成省略号。
library;

import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'module_tag.dart';

class SetRowTags extends StatelessWidget {
  const SetRowTags({super.key, required this.labels});

  final List<String> labels;

  /// 网格列数（canva 参考：`grid-template-columns: repeat(3, auto)`）。
  static const int columns = 3;

  @override
  Widget build(BuildContext context) {
    final columnCount = labels.length < columns ? labels.length : columns;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var c = 0; c < columnCount; c++) ...[
          if (c > 0) const SizedBox(width: AppSpacing.xxs),
          IntrinsicWidth(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = c; i < labels.length; i += columns) ...[
                  if (i > c) const SizedBox(height: AppSpacing.xxs),
                  ModuleTag(label: labels[i]),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}
