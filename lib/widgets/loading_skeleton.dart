/// 加载骨架（G-06，第 3 章 §22.2.2；动画规范 v1.0 §10）。
///
/// surfaceVariant 色块、圆角 16；呼吸脉冲按 §10 Skeleton Pulse：Alpha
/// 0.4 → 0.9 → 0.4，[AppDurations.loop]（1000ms）+ [AppDurations.standard]。
/// 骨架转真实内容见 [SkeletonToContent]。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_animations.dart';
import '../core/theme.dart';

/// 骨架脉冲 Alpha 端点（规范 §10 Skeleton Pulse：0.4 → 0.9 → 0.4）。
const double _pulseMinAlpha = 0.4;
const double _pulseMaxAlpha = 0.9;

class LoadingSkeleton extends StatefulWidget {
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
  State<LoadingSkeleton> createState() => _LoadingSkeletonState();
}

class _LoadingSkeletonState extends State<LoadingSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _animation;
  late final Animation<double> _alpha;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: AppDurations.loop);
    _animation = CurvedAnimation(
      parent: _controller,
      curve: AppDurations.standard,
    );
    // 一次完整往返 0.4 → 0.9 → 0.4 即一个 LOOP 周期（1000ms），
    // 前后半程各按 fastOutSlowIn 缓动。
    _alpha = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: _pulseMinAlpha, end: _pulseMaxAlpha),
        weight: 1,
      ),
      TweenSequenceItem(
        tween: Tween(begin: _pulseMaxAlpha, end: _pulseMinAlpha),
        weight: 1,
      ),
    ]).animate(_animation);
    _controller.repeat();
  }

  @override
  void dispose() {
    _animation.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _alpha,
      child: Container(
        height: widget.height,
        width: widget.width,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(widget.borderRadius),
        ),
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

/// 骨架屏转首次真实内容（规范 §10 Skeleton → First Content Load）。
///
/// [loaded] 由 false 翻 true 时：骨架退出 [AppDurations.s]（150ms）+
/// [AppDurations.exit]，Alpha 1 → 0（复用 [FadeOnly] 的退出）；真实内容同帧
/// 挂载并进入 [AppDurations.l]（250ms）+ [AppDurations.enter]，容器 Alpha
/// 0 → 1（[FadeOnly] 的 inDuration 覆写为 L 级）。内容里的列表项应包
/// [StaggeredListAppear]（slideOffsetDp 传
/// [StaggeredListAppear.listSlideOffsetDp]）：随内容首次挂载即播放交错入场
/// （TranslationY +20dp → 0，前 6 项每项 +30ms）。
///
/// 骨架退出播完后移出树，退出期间不再拦截点击；[loaded] 翻回 false（重新
/// 拉取）时骨架重新挂载、内容移出树。
class SkeletonToContent extends StatefulWidget {
  const SkeletonToContent({
    super.key,
    required this.skeleton,
    required this.loaded,
    required this.child,
  });

  final Widget skeleton;
  final bool loaded;
  final Widget child;

  @override
  State<SkeletonToContent> createState() => _SkeletonToContentState();
}

class _SkeletonToContentState extends State<SkeletonToContent> {
  late bool _skeletonInTree;
  Timer? _removeTimer;

  @override
  void initState() {
    super.initState();
    _skeletonInTree = !widget.loaded;
  }

  @override
  void didUpdateWidget(SkeletonToContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.loaded == widget.loaded) return;
    _removeTimer?.cancel();
    if (widget.loaded) {
      // 骨架留在树里播完 150ms 退出再移除。
      _removeTimer = Timer(AppDurations.s, () {
        if (mounted) setState(() => _skeletonInTree = false);
      });
    } else {
      setState(() => _skeletonInTree = true);
    }
  }

  @override
  void dispose() {
    _removeTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (widget.loaded)
          FadeOnly(inDuration: AppDurations.l, child: widget.child),
        if (_skeletonInTree)
          IgnorePointer(
            ignoring: widget.loaded,
            child: FadeOnly(visible: !widget.loaded, child: widget.skeleton),
          ),
      ],
    );
  }
}
