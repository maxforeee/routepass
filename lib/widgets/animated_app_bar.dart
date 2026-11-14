/// F20 §3 共享顶部栏动画（动画规范 v1.0 §3「Top app bar」）。
///
/// 全 App 的二级子页顶部栏统一用 [AnimatedAppBar]，保证标题与返回箭头动效一致：
///  * 标题进入 / 退出：复用 [AnimatedTitle]（200ms 进 / 150ms 出，±8dp）。
///  * 返回箭头进入（进入子页）：[AppDurations.m]（200ms）+ [AppDurations.enter]，
///    Alpha 0 → 1，Scale 0.8 → 1.0，TranslationX -8dp → 0。
///  * 返回箭头退出（退出子页）：[AppDurations.s]（150ms）+ [AppDurations.exit]，
///    Alpha 1 → 0，Scale 1.0 → 0.8，TranslationX 0 → -8dp。
///
/// 时长与缓动一律取 [AppDurations] token，不写死毫秒值。滚动联动折叠 / FAB
/// 显隐不在本组件内：当前接入页均无可折叠顶栏与 FAB（见 chunk 报告）。
library;

import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'animated_title.dart';

/// 返回箭头的横向位移（规范 §3：TranslationX -8dp → 0）。
const double _backArrowSlideDp = 8;

/// 返回箭头进入的缩放起点（规范 §3：Scale 0.8 → 1.0）。
const double _backArrowScaleBegin = 0.8;

/// 品牌动画顶部栏：标题切换动画 + 返回箭头进出动画（规范 §3）。
///
/// 作为 [Scaffold.appBar] 使用（实现 [PreferredSizeWidget]）。内部仍是标准
/// [AppBar]，仅把标题换成 [AnimatedTitle]、把返回箭头换成 [AnimatedBackButton]，
/// 其余（actions / 背景色 /  elevation / centerTitle）原样透传，不改导航行为。
///
/// 返回箭头在路由可 pop（二级子页）时自动出现；[onBack] 可接管返回逻辑
/// （如答题页的退出确认），[leading] 可完全自定义 leading。
class AnimatedAppBar extends StatelessWidget implements PreferredSizeWidget {
  const AnimatedAppBar({
    super.key,
    required this.title,
    this.titleStyle,
    this.actions,
    this.leading,
    this.onBack,
    this.backgroundColor,
    this.elevation,
    this.centerTitle,
  });

  final String title;
  final TextStyle? titleStyle;
  final List<Widget>? actions;
  final Widget? leading;
  final VoidCallback? onBack;
  final Color? backgroundColor;
  final double? elevation;
  final bool? centerTitle;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final bool canPop = ModalRoute.of(context)?.canPop ?? false;
    Widget? effectiveLeading = leading;
    if (effectiveLeading == null && canPop) {
      effectiveLeading = AnimatedBackButton(onPressed: onBack);
    }
    return AppBar(
      leading: effectiveLeading,
      automaticallyImplyLeading: false,
      title: AnimatedTitle(title: title, style: titleStyle),
      actions: actions,
      backgroundColor: backgroundColor,
      elevation: elevation,
      centerTitle: centerTitle,
    );
  }
}

/// 返回箭头进出动画（规范 §3「Back arrow Enter / Exit」）。
///
/// 挂载时播放进入动画；监听所在路由的动画状态，路由被 pop（动画 reverse）时
/// 播放退出动画。点击默认 [Navigator.maybePop]，可用 [onPressed] 接管。
class AnimatedBackButton extends StatefulWidget {
  const AnimatedBackButton({super.key, this.onPressed, this.tooltip});

  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  State<AnimatedBackButton> createState() => _AnimatedBackButtonState();
}

class _AnimatedBackButtonState extends State<AnimatedBackButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _animation;
  Animation<double>? _routeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: AppDurations.m);
    _animation = CurvedAnimation(
      parent: _controller,
      curve: AppDurations.enter,
      reverseCurve: AppDurations.exit,
    );
    _controller.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final Animation<double>? routeAnimation = ModalRoute.of(context)?.animation;
    if (routeAnimation != _routeAnimation) {
      _routeAnimation?.removeStatusListener(_onRouteStatus);
      _routeAnimation = routeAnimation;
      _routeAnimation?.addStatusListener(_onRouteStatus);
    }
  }

  void _onRouteStatus(AnimationStatus status) {
    if (!mounted) return;
    if (status == AnimationStatus.reverse) {
      // 退出子页：150ms accelerate，Alpha 1→0 / Scale 1→0.8 / X 0→-8dp。
      _controller
        ..duration = AppDurations.s
        ..reverse();
    } else if (status == AnimationStatus.forward) {
      _controller
        ..duration = AppDurations.m
        ..forward();
    }
  }

  @override
  void dispose() {
    _routeAnimation?.removeStatusListener(_onRouteStatus);
    _animation.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      // 用真正的 Material BackButton（而非裸 IconButton），tester.pageBack()
      // 才能识别；onPressed 为 null 时 BackButton 默认 Navigator.maybePop。
      child: BackButton(onPressed: widget.onPressed),
      builder: (context, child) {
        final double t = _animation.value;
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(-_backArrowSlideDp * (1.0 - t), 0),
            child: Transform.scale(
              scale: _backArrowScaleBegin + (1.0 - _backArrowScaleBegin) * t,
              child: child,
            ),
          ),
        );
      },
    );
  }
}
