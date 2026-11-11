/// 加载骨架（G-06，第 3 章 §22.2.2）。
///
/// surfaceVariant 色块、圆角 16；不带 shimmer（文档：shimmer 可关）。
library;

import 'package:flutter/material.dart';

class LoadingSkeleton extends StatelessWidget {
  const LoadingSkeleton({
    super.key,
    required this.height,
    this.width,
    this.borderRadius = 16,
  });

  final double height;
  final double? width;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

/// 骨架列表：标题行 + 若干正文行，用于列表页加载态。
class LoadingSkeletonList extends StatelessWidget {
  const LoadingSkeletonList({super.key, this.itemCount = 5});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: itemCount,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        return const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LoadingSkeleton(height: 20, width: 160),
            SizedBox(height: 8),
            LoadingSkeleton(height: 14),
          ],
        );
      },
    );
  }
}
