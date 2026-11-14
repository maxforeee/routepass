/// F20 共享动画工具（动画规范 v1.0 §3 通用淡入淡出模式、§4 搜索栏与键盘、
/// §5 按钮、§6 输入框、§7 长按、§8 列表项、§10 空/错状态、加载指示器与
/// 下拉刷新、§11 选择控件与进度条）。
///
/// 本文件提供供 F20 各 chunk 复用的动画组件，全部绑定 chunk 0 在
/// `theme.dart` 定义的时长与缓动 token，业务侧不再写死零散毫秒值：
///  * 时长：[AppDurations.xs] / [AppDurations.s] / [AppDurations.m] /
///    [AppDurations.l]。
///  * 缓动：chunk 0 把曲线 token 定义在 [AppDurations] 上（[AppDurations.enter]
///    进入 decelerate、[AppDurations.exit] 退出 easeIn、[AppDurations.standard]
///    屏幕内状态过渡 fastOutSlowIn），本文件统一引用这些 token。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// 纵向滑动距离（规范 §3「淡入淡出 + 滑动」：TranslationY +16dp → 0）。
const double _slideVerticalDp = 16;

/// 列表项入场纵向滑动距离（规范 §8「Appear on load」：TranslationY +20dp → 0）。
///
/// §8 的列表入场比 §3 通用「淡入淡出 + 滑动」多 4dp，故单独成常量，由
/// [StaggeredListAppear.slideOffsetDp] 传入，不改动 §3 的通用位移。
const double _listSlideVerticalDp = 20;

/// 横向滑动比例（规范 §3「淡入淡出 + 滑动」：横向 +30% → 0，相对子组件宽度）。
const double _slideHorizontalFraction = 0.30;

/// 缩放进入起点（规范 §3「淡入淡出 + 缩放」Enter：Scale 0.85 → 1.0）。
const double _scaleEnter = 0.85;

/// 缩放退出终点（规范 §3「淡入淡出 + 缩放」Exit：Scale 1.0 → 0.90）。
const double _scaleExit = 0.90;

/// 按压缩放目标（规范 §5 按钮 Press：Scale 1.0 → 0.97）。
const double _pressScale = 0.97;

/// 图标/文字按钮按压缩放目标（规范 §5 Text / Icon button：Scale 1.0 → 0.92）。
const double _iconPressScale = 0.92;

/// 卡片按压缩放目标（规范 §8 Tap Press：Scale 1.0 → 0.98）。
const double _cardPressScale = 0.98;

/// 卡片静置 / 按压抬起高度（规范 §8：Elevation 1dp ↔ 4dp）。
const double _cardRestElevation = 1;
const double _cardPressElevation = 4;

/// 长按蓄力缩放目标（规范 §7 Press & Hold：Scale 1.0 → 0.96）。
const double _holdScale = 0.96;

/// 禁用态透明度（规范 §5 Disabled Enter：Alpha 1.0 → 0.38）。
const double _disabledAlpha = 0.38;

/// 搜索容器收起时的横向缩放（规范 §4 Search bar：ScaleX 0.85 ↔ 1.0）。
const double _searchCollapsedScaleX = 0.85;

/// 搜索建议层纵向位移（规范 §4 Search bar：TranslationY -12dp ↔ 0）。
const double _suggestionsSlideDp = -12;

/// 清除按钮显隐的缩放端点（规范 §6 Clear button：Scale 0.5 ↔ 1.0）。
const double _clearButtonScale = 0.5;

/// 报错抖动横向关键帧（规范 §6 Error Enter：0 → -6 → +6 → -3 → 0dp）。
const double _shakeFirstDp = -6;
const double _shakeSecondDp = 6;
const double _shakeThirdDp = -3;

/// 错误文案纵向位移（规范 §6 Error：TranslationY -4dp ↔ 0）。
const double _errorTextSlideDp = -4;

/// 获焦指示线高度（规范 §6 Focus Enter 的底部指示线）。
const double _focusIndicatorHeightDp = 2;

/// 长按触觉阈值 400ms（规范 §7 Haptic）。
///
/// 400ms 不属于 7 级时长阶梯，是规范单独给定的触发阈值，故以命名常量表达
/// （用微秒书写，避免在本文件出现写死的毫秒 Duration）。
const Duration _hapticThreshold = Duration(microseconds: 400000);

/// 交错入场步长 30ms（规范 §8「首屏前 6 项每项依次延迟 +30ms」）。
///
/// 30ms 不属于 7 级时长阶梯，是规范单独给定的交错常量，故以命名常量表达
/// （用微秒书写，避免在本文件出现写死的毫秒 Duration）。
const Duration _staggerStep = Duration(microseconds: 30000);

/// [FadeSlide] 的滑动方向。
enum FadeSlideAxis {
  /// 纵向：TranslationY +16dp → 0（规范 §3）。
  vertical,

  /// 横向：TranslationX +30% → 0（规范 §3，相对子组件宽度）。
  horizontal,
}

/// 纯淡入淡出（规范 §3「Fade Only」）。
///
/// 适用于原地同层级切换（Tab 内容、骨架屏转真实内容、背景遮罩显隐）。
/// 进入：[AppDurations.m]（200ms）+ [AppDurations.enter]，透明度 0 → 1；
/// 退出：[AppDurations.s]（150ms）+ [AppDurations.exit]，透明度 1 → 0。
///
/// [inDuration] / [outDuration] 供个别章节覆写时长：§10 骨架转真实内容的
/// 容器进入为 L 级（250ms），退出仍是 S 级（见 SkeletonToContent）。
///
/// [visible] 为 true 时淡入（首次构建即播放进入动画），false 时淡出；
/// 子组件始终保留在树中，仅透明度变化。
class FadeOnly extends StatelessWidget {
  const FadeOnly({
    super.key,
    required this.child,
    this.visible = true,
    this.inDuration = AppDurations.m,
    this.outDuration = AppDurations.s,
  });

  final Widget child;
  final bool visible;
  final Duration inDuration;
  final Duration outDuration;

  @override
  Widget build(BuildContext context) {
    return _FadePattern(
      visible: visible,
      inDuration: inDuration,
      outDuration: outDuration,
      builder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: child,
    );
  }
}

/// 淡入淡出 + 滑动（规范 §3「Fade + Slide」）。
///
/// 适用于有方向来源或层级推进的元素（页面 Push/Pop、列表项交错加载、
/// 搜索结果出现）。进入：[AppDurations.l]（250ms）+ [AppDurations.enter]；
/// 退出：[AppDurations.m]（200ms）+ [AppDurations.exit]。
/// 位移：[FadeSlideAxis.vertical] 为 +16dp，[FadeSlideAxis.horizontal] 为 +30%。
class FadeSlide extends StatelessWidget {
  const FadeSlide({
    super.key,
    required this.child,
    this.visible = true,
    this.axis = FadeSlideAxis.vertical,
  });

  final Widget child;
  final bool visible;
  final FadeSlideAxis axis;

  @override
  Widget build(BuildContext context) {
    return _FadePattern(
      visible: visible,
      inDuration: AppDurations.l,
      outDuration: AppDurations.m,
      builder: (child, animation) =>
          _fadeSlideTransform(child, animation, axis),
      child: child,
    );
  }
}

/// 淡入淡出 + 缩放（规范 §3「Fade + Scale」）。
///
/// 适用于从中心或触发锚点浮现的模态/浮层（Dialog、Context Menu、Tooltip、
/// 空/错误状态插画）。进入：[AppDurations.l]（250ms）+ [AppDurations.enter]，
/// Scale 0.85 → 1.0；退出：[AppDurations.s]（150ms）+ [AppDurations.exit]，
/// Scale 1.0 → 0.90（规范 §3 表格 Exit 行）。
class FadeScale extends StatelessWidget {
  const FadeScale({super.key, required this.child, this.visible = true});

  final Widget child;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    return _FadePattern(
      visible: visible,
      inDuration: AppDurations.l,
      outDuration: AppDurations.s,
      builder: (child, animation) => AnimatedBuilder(
        animation: animation,
        child: child,
        builder: (context, child) {
          final double t = animation.value;
          // 进入 0.85 → 1.0；退出 1.0 → 0.90（t 在退出时由 1 回到 0）。
          final double begin = visible ? _scaleEnter : _scaleExit;
          final double scale = begin + (1.0 - begin) * t;
          return FadeTransition(
            opacity: animation,
            child: Transform.scale(scale: scale, child: child),
          );
        },
      ),
      child: child,
    );
  }
}

/// 按压缩放反馈（规范 §5 按钮 Press / Release / Disabled、§7 长按蓄力与触觉、
/// §8 卡片 Tap Press / Release）。
///
/// 包裹任意子组件：
///  * 按下缩到 [scale]（主/次按钮默认 0.97；图标/文字按钮传 [Pressable.iconScale]
///    = 0.92；卡片传 [Pressable.cardScale] = 0.98），[AppDurations.xs]（100ms）+
///    [pressCurve]（按钮默认 [AppDurations.enter] decelerate；卡片按 §8 传
///    [AppDurations.standard] fastOutSlowIn）。
///  * 长按蓄力缩到 0.96，[AppDurations.m]（200ms）+ [AppDurations.enter]；按住达
///    400ms 触发 [HapticFeedback.heavyImpact]（规范 §7：瞬时，无额外视觉位移；
///    Flutter 没有 HapticFeedback.longPress，heavyImpact 即长按确认震动）。
///  * 释放回 1.0，[AppDurations.s]（150ms）+ [AppDurations.standard]。
///  * [enabled] 为 false 时整体淡到 0.38（[AppDurations.s] + 线性），并且不响应
///    按压手势（规范 §5「禁用态点击无动画」）。
///
/// 水波纹与 elevation 沿用子组件自带的 Material InkWell / Button，不在这里重造。
/// 规范 §7 的 Context menu / Tooltip 进出动画不适用：应用内长按只触发动作
/// （如知识库长按复制命令），不弹上下文菜单或 Tooltip。
/// 缩放由 [Listener] 的原始指针事件驱动，而不是外层 [GestureDetector] 的
/// onTapDown：包裹 Material 按钮时手势竞技场由最内层的 InkWell 获胜，外层
/// onTapDown 在快速点击下根本不会触发，按压动画会形同虚设。原始指针事件不参与
/// 竞技场，故无论点击落在子按钮还是本组件上都可靠。[onTap] / [onLongPress] 仅作
/// 可选透传（子组件自带 onPressed 时不必再传），长按蓄力仍走 GestureDetector。
///
/// [onPressedChanged] 把按下/释放状态透传给使用方：规范 §8 的卡片除缩放外还要
/// Elevation 1dp ↔ 4dp，而 elevation 属于卡片自己的 Material（本组件不重造卡面），
/// 故由卡片据此回调驱动自身 Material 的 elevation 与 animationDuration。
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = _pressScale,
    this.pressCurve = AppDurations.enter,
    this.enabled = true,
    this.onPressedChanged,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// 按压缩放目标（规范 §5）：默认 0.97，图标/文字按钮用 [iconScale]，
  /// 卡片用 [cardScale]。
  final double scale;

  /// 按压缓动：§5 按钮用 [AppDurations.enter]（decelerate），§8 卡片用
  /// [AppDurations.standard]（fastOutSlowIn）。释放恒为 [AppDurations.standard]。
  final Curve pressCurve;

  /// 是否可用（规范 §5 Disabled Enter / Exit）。
  final bool enabled;

  /// 按下（true）/ 释放（false）状态变化回调，供使用方驱动 elevation 等
  /// 本组件不负责的视觉属性（规范 §8 卡片）。
  final ValueChanged<bool>? onPressedChanged;

  /// 图标/文字按钮的按压缩放 0.92（规范 §5 Text / Icon button）。
  static const double iconScale = _iconPressScale;

  /// 卡片按压缩放 0.98（规范 §8 Tap Press / Release）。
  static const double cardScale = _cardPressScale;

  /// 卡片静置 elevation 1dp（规范 §8）。
  static const double cardRestElevation = _cardRestElevation;

  /// 卡片按压 elevation 4dp（规范 §8）。
  static const double cardPressElevation = _cardPressElevation;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> with TickerProviderStateMixin {
  late final AnimationController _scaleController;
  late final AnimationController _alphaController;
  late final CurvedAnimation _alphaCurve;
  late final Animation<double> _alpha;
  bool _longPressing = false;
  bool _pressed = false;
  int? _pressPointer;
  Timer? _hapticTimer;

  @override
  void initState() {
    super.initState();
    // 规范 §5/§7：控制器值即缩放值。按压/蓄力/释放只换目标、时长与缓动，
    // 不重建 Tween，也不让多条 CurvedAnimation 共用一个控制器互相覆盖。
    _scaleController = AnimationController(
      vsync: this,
      duration: AppDurations.xs,
      value: 1.0,
    );
    _alphaController = AnimationController(
      vsync: this,
      duration: AppDurations.s,
      value: widget.enabled ? 0.0 : 1.0,
    );
    _alphaCurve = CurvedAnimation(
      parent: _alphaController,
      curve: AppDurations.loopCurve,
    );
    _alpha = Tween<double>(
      begin: 1.0,
      end: _disabledAlpha,
    ).animate(_alphaCurve);
  }

  @override
  void didUpdateWidget(Pressable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled == widget.enabled) return;
    if (widget.enabled) {
      _alphaController.reverse();
      return;
    }
    _cancelHaptic();
    _longPressing = false;
    _pressPointer = null;
    _animateScaleTo(1.0, AppDurations.s, AppDurations.standard);
    _notifyPressed(false);
    _alphaController.forward();
  }

  @override
  void dispose() {
    _cancelHaptic();
    _alphaCurve.dispose();
    _scaleController.dispose();
    _alphaController.dispose();
    super.dispose();
  }

  /// 规范 §5/§7：按压与蓄力用 decelerate，释放用 fastOutSlowIn。
  ///
  /// 从当前缩放值插值到 [target]，中途改目标也不会跳回起点。释放只能由
  /// [_handlePointerUp] / [_handlePointerCancel] 触发一次：手势侧的
  /// onLongPressEnd 晚一帧才到，再调一次 [AnimationController.animateTo]
  /// 会把已跑了一半的释放动画从当前值重新计时。
  void _animateScaleTo(double target, Duration duration, Curve curve) {
    _scaleController.animateTo(target, duration: duration, curve: curve);
  }

  /// 规范 §7：按住达 400ms 触发系统长按震动（手势识别本身在 500ms 才判定长按，
  /// 故触觉单独计时，不等 onLongPress）。
  void _startHaptic() {
    _cancelHaptic();
    _hapticTimer = Timer(_hapticThreshold, () {
      if (mounted) HapticFeedback.heavyImpact();
    });
  }

  void _cancelHaptic() {
    _hapticTimer?.cancel();
    _hapticTimer = null;
  }

  /// 规范 §8：把按下/释放透传给使用方（卡片据此抬起 elevation），只在状态
  /// 真正变化时回调一次，避免多指或重复事件把卡面动画重新计时。
  void _notifyPressed(bool pressed) {
    if (_pressed == pressed) return;
    _pressed = pressed;
    widget.onPressedChanged?.call(pressed);
  }

  void _handlePointerDown(PointerDownEvent event) {
    // 只跟手第一根手指，多指触摸不叠加缩放。
    if (_pressPointer != null) return;
    _pressPointer = event.pointer;
    _animateScaleTo(widget.scale, AppDurations.xs, widget.pressCurve);
    _notifyPressed(true);
    if (widget.onLongPress != null) _startHaptic();
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (event.pointer != _pressPointer) return;
    _pressPointer = null;
    _cancelHaptic();
    _animateScaleTo(1.0, AppDurations.s, AppDurations.standard);
    _notifyPressed(false);
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (event.pointer != _pressPointer) return;
    _pressPointer = null;
    _cancelHaptic();
    if (!_longPressing) {
      _animateScaleTo(1.0, AppDurations.s, AppDurations.standard);
    }
    _notifyPressed(false);
  }

  void _handleLongPressStart(LongPressStartDetails details) {
    _longPressing = true;
    _animateScaleTo(_holdScale, AppDurations.m, AppDurations.enter);
  }

  void _handleLongPressEnd(LongPressEndDetails details) {
    // 释放动画归 Listener 的 onPointerUp 独占：本回调晚一帧才到，
    // 再 animateTo(1.0) 会把已跑了一半的释放动画重新计时。
    _longPressing = false;
    _cancelHaptic();
  }

  void _handleLongPressCancel() {
    // 同上，取消时的释放由 Listener 的 onPointerCancel 负责。
    _longPressing = false;
    _cancelHaptic();
  }

  @override
  Widget build(BuildContext context) {
    final bool longPress = widget.enabled && widget.onLongPress != null;
    return FadeTransition(
      opacity: _alpha,
      // translucent：子组件不自带命中区域时（如 SizedBox 占位、透明底），
      // deferToChild 会让整块按压区漏掉指针事件，按压与长按蓄力都不触发；
      // 用 opaque 又会挡住身后组件，故两层都取 translucent。
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: widget.enabled ? _handlePointerDown : null,
        onPointerUp: widget.enabled ? _handlePointerUp : null,
        onPointerCancel: widget.enabled ? _handlePointerCancel : null,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: widget.enabled ? widget.onTap : null,
          onLongPress: widget.enabled ? widget.onLongPress : null,
          onLongPressStart: longPress ? _handleLongPressStart : null,
          onLongPressEnd: longPress ? _handleLongPressEnd : null,
          onLongPressCancel: longPress ? _handleLongPressCancel : null,
          child: ScaleTransition(scale: _scaleController, child: widget.child),
        ),
      ),
    );
  }
}

/// 搜索容器展开/收起（规范 §4 Search bar Expand / Collapse）。
///
/// 横向 ScaleX 在 0.85（收起）与 1.0（展开铺满）之间过渡：展开
/// [AppDurations.l]（250ms）、收起 [AppDurations.m]（200ms），均用
/// [AppDurations.standard]（fastOutSlowIn）。锚点取左缘，展开时向右铺满，
/// 页面左侧内边距保持不变。
///
/// [suggestions] 为搜索建议层：随容器展开 Alpha 0 → 1、TranslationY
/// -12dp → 0，收起时反向（同一时长与缓动）；收起期间不拦截点击。为 null 时
/// 只输出容器本身，不额外占位。
class SearchExpand extends StatefulWidget {
  const SearchExpand({
    super.key,
    required this.child,
    required this.expanded,
    this.suggestions,
  });

  final Widget child;
  final bool expanded;
  final Widget? suggestions;

  @override
  State<SearchExpand> createState() => _SearchExpandState();
}

class _SearchExpandState extends State<SearchExpand>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: AppDurations.l);
    _animation = CurvedAnimation(
      parent: _controller,
      curve: AppDurations.standard,
    );
    if (widget.expanded) _controller.forward();
  }

  @override
  void didUpdateWidget(SearchExpand oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expanded == widget.expanded) return;
    _controller.duration = widget.expanded ? AppDurations.l : AppDurations.m;
    if (widget.expanded) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget container = AnimatedBuilder(
      animation: _animation,
      child: widget.child,
      builder: (context, child) {
        final double scaleX =
            _searchCollapsedScaleX +
            (1.0 - _searchCollapsedScaleX) * _animation.value;
        return Transform(
          alignment: Alignment.centerLeft,
          transform: Matrix4.diagonal3Values(scaleX, 1.0, 1.0),
          child: child,
        );
      },
    );
    final Widget? suggestions = widget.suggestions;
    if (suggestions == null) return container;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        container,
        IgnorePointer(
          ignoring: !widget.expanded,
          child: AnimatedBuilder(
            animation: _animation,
            child: suggestions,
            builder: (context, child) => FadeTransition(
              opacity: _animation,
              child: Transform.translate(
                offset: Offset(
                  0,
                  _suggestionsSlideDp * (1.0 - _animation.value),
                ),
                child: child,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 输入框获焦指示线（规范 §6 Focus Enter / Unfocus Exit）。
///
/// 底部指示线 ScaleX 0 → 1、Alpha 0 → 1：获焦 [AppDurations.m]（200ms）、
/// 失焦 [AppDurations.s]（150ms），均用 [AppDurations.standard]。
/// 只负责指示线本身，由使用方摆到输入框底部（不改变输入框尺寸）。
class FocusIndicator extends StatefulWidget {
  const FocusIndicator({
    super.key,
    required this.focused,
    required this.color,
    this.height = _focusIndicatorHeightDp,
  });

  final bool focused;
  final Color color;
  final double height;

  @override
  State<FocusIndicator> createState() => _FocusIndicatorState();
}

class _FocusIndicatorState extends State<FocusIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: AppDurations.m);
    _animation = CurvedAnimation(
      parent: _controller,
      curve: AppDurations.standard,
    );
    if (widget.focused) _controller.forward();
  }

  @override
  void didUpdateWidget(FocusIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focused == widget.focused) return;
    _controller.duration = widget.focused ? AppDurations.m : AppDurations.s;
    if (widget.focused) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) {
        final double t = _animation.value;
        return FadeTransition(
          opacity: _animation,
          // ScaleX 用宽度因子表达，避免 t=0 时出现不可逆的缩放矩阵。
          child: SizedBox(
            height: widget.height,
            child: Align(
              alignment: Alignment.center,
              child: FractionallySizedBox(
                widthFactor: t,
                child: Container(
                  height: widget.height,
                  decoration: BoxDecoration(
                    color: widget.color,
                    borderRadius: BorderRadius.circular(widget.height / 2),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 清除按钮显隐（规范 §6 Clear button Enter / Exit）。
///
/// Alpha 0 ↔ 1、Scale 0.5 ↔ 1.0，进出均 [AppDurations.s]（150ms）；进入
/// [AppDurations.enter]（decelerate）、退出 [AppDurations.exit]（accelerate）。
/// 隐藏期间不拦截点击；退出动画播完触发 [onExited]，使用方据此把子组件移出树。
class ClearButtonReveal extends StatefulWidget {
  const ClearButtonReveal({
    super.key,
    required this.child,
    required this.visible,
    this.onExited,
  });

  final Widget child;
  final bool visible;
  final VoidCallback? onExited;

  @override
  State<ClearButtonReveal> createState() => _ClearButtonRevealState();
}

class _ClearButtonRevealState extends State<ClearButtonReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _animation;
  bool _exitReported = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: AppDurations.s);
    _animation = CurvedAnimation(
      parent: _controller,
      curve: AppDurations.enter,
      reverseCurve: AppDurations.exit,
    );
    _controller.addListener(_handleTick);
    if (widget.visible) _controller.forward();
  }

  @override
  void didUpdateWidget(ClearButtonReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible == widget.visible) return;
    if (widget.visible) {
      _exitReported = false;
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  /// 退出完成以 value 归零判定，而不是 [AnimationStatus.dismissed]：
  /// AnimationController 的 isDone 是 `t > duration`，恰好在时长那一帧值已到
  /// 终点、状态却还停在 reverse，用状态判定会把 onExited 推迟一帧。
  void _handleTick() {
    if (widget.visible || _exitReported || _controller.value > 0.0) return;
    _exitReported = true;
    widget.onExited?.call();
  }

  @override
  void dispose() {
    _controller.removeListener(_handleTick);
    _animation.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !widget.visible,
      child: AnimatedBuilder(
        animation: _animation,
        child: widget.child,
        builder: (context, child) {
          final double scale =
              _clearButtonScale + (1.0 - _clearButtonScale) * _animation.value;
          return FadeTransition(
            opacity: _animation,
            // 三轴同比缩放：Transform.scale 的矩阵 Z 轴恒为 1，
            // getMaxScaleOnAxis() 会一直读到 1.0，量不出真实缩放。
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.diagonal3Values(scale, scale, scale),
              child: child,
            ),
          );
        },
      ),
    );
  }
}

/// 报错抖动（规范 §6 Error State Enter）。
///
/// [hasError] 由 false 变 true 时播放一次横向抖动：TranslationX
/// 0 → -6dp → +6dp → -3dp → 0，[AppDurations.m]（200ms）+
/// [AppDurations.standard]；错误解除不再抖动（文案淡出见 [AnimatedErrorText]）。
class ErrorShake extends StatefulWidget {
  const ErrorShake({super.key, required this.child, required this.hasError});

  final Widget child;
  final bool hasError;

  @override
  State<ErrorShake> createState() => _ErrorShakeState();
}

class _ErrorShakeState extends State<ErrorShake>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _animation;
  late final Animation<double> _offset;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: AppDurations.m);
    _animation = CurvedAnimation(
      parent: _controller,
      curve: AppDurations.standard,
    );
    _offset = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: _shakeFirstDp),
        weight: 1,
      ),
      TweenSequenceItem(
        tween: Tween(begin: _shakeFirstDp, end: _shakeSecondDp),
        weight: 1,
      ),
      TweenSequenceItem(
        tween: Tween(begin: _shakeSecondDp, end: _shakeThirdDp),
        weight: 1,
      ),
      TweenSequenceItem(
        tween: Tween(begin: _shakeThirdDp, end: 0.0),
        weight: 1,
      ),
    ]).animate(_animation);
    if (widget.hasError) _controller.forward();
  }

  @override
  void didUpdateWidget(ErrorShake oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.hasError && widget.hasError) {
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) =>
          Transform.translate(offset: Offset(_offset.value, 0), child: child),
    );
  }
}

/// 错误文案显隐（规范 §6 Error State Enter / Exit）。
///
/// 进入 [AppDurations.m]（200ms）：Alpha 0 → 1、TranslationY -4dp → 0；
/// 退出 [AppDurations.s]（150ms）反向；均用 [AppDurations.standard]。
/// [errorText] 为 null 且退出动画播完后不再占位（返回零尺寸）。
class AnimatedErrorText extends StatefulWidget {
  const AnimatedErrorText({super.key, required this.errorText, this.style});

  final String? errorText;
  final TextStyle? style;

  @override
  State<AnimatedErrorText> createState() => _AnimatedErrorTextState();
}

class _AnimatedErrorTextState extends State<AnimatedErrorText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _animation;
  String? _shownText;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: AppDurations.m);
    _animation = CurvedAnimation(
      parent: _controller,
      curve: AppDurations.standard,
      reverseCurve: AppDurations.standard,
    );
    _controller.addListener(_handleTick);
    _shownText = widget.errorText;
    if (_shownText != null) _controller.forward();
  }

  @override
  void didUpdateWidget(AnimatedErrorText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.errorText == widget.errorText) return;
    if (widget.errorText != null) {
      // didUpdateWidget 在父组件重建期间、本组件 build() 之前调用，直接赋值
      // 即可让同一帧的 build() 读到新文案；setState 会把这次更新推到下一帧，
      // 调用方只 pump 一次就找不到错误文案。
      _shownText = widget.errorText;
      _controller
        ..duration = AppDurations.m
        ..forward();
    } else {
      _controller
        ..duration = AppDurations.s
        ..reverse();
    }
  }

  /// 与 [ClearButtonReveal] 同理：退出动画在 value 归零那一帧就已播完，
  /// [AnimationStatus.dismissed] 还要再等一帧，据此移出树会慢一帧。
  void _handleTick() {
    if (widget.errorText != null ||
        _shownText == null ||
        _controller.value > 0.0) {
      return;
    }
    setState(() => _shownText = null);
  }

  @override
  void dispose() {
    _controller.removeListener(_handleTick);
    _animation.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String? text = _shownText;
    if (text == null) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _animation,
      child: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xs),
        child: Text(text, style: widget.style),
      ),
      builder: (context, child) {
        return FadeTransition(
          opacity: _animation,
          child: Transform.translate(
            offset: Offset(0, _errorTextSlideDp * (1.0 - _animation.value)),
            child: child,
          ),
        );
      },
    );
  }
}

/// 底部操作区随键盘升降（规范 §4 Keyboard Show / Hide）。
///
/// 位移取 `MediaQuery.viewInsetsOf(context).bottom`（真实键盘高度，不写死）：
/// 弹出 [AppDurations.l]（250ms）+ [AppDurations.enter] 上移，收起
/// [AppDurations.m]（200ms）+ [AppDurations.exit] 回落。
///
/// 使用方需关闭所在 Scaffold 的 `resizeToAvoidBottomInset`（或把本组件放在
/// 不被 Scaffold 压缩的区域），否则键盘高度会被让位与本组件各算一次。
class KeyboardFollowBar extends StatefulWidget {
  const KeyboardFollowBar({super.key, required this.child});

  final Widget child;

  @override
  State<KeyboardFollowBar> createState() => _KeyboardFollowBarState();
}

class _KeyboardFollowBarState extends State<KeyboardFollowBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _riseCurve;
  late final CurvedAnimation _fallCurve;
  late Animation<double> _offset;
  double _inset = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: AppDurations.l);
    _riseCurve = CurvedAnimation(
      parent: _controller,
      curve: AppDurations.enter,
    );
    _fallCurve = CurvedAnimation(parent: _controller, curve: AppDurations.exit);
    _offset = Tween<double>(begin: 0.0, end: 0.0).animate(_riseCurve);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final double inset = MediaQuery.viewInsetsOf(context).bottom;
    if (inset == _inset) return;
    final bool rising = inset > _inset;
    setState(() {
      _offset = Tween<double>(
        begin: _inset,
        end: inset,
      ).animate(rising ? _riseCurve : _fallCurve);
    });
    _inset = inset;
    _controller
      ..duration = rising ? AppDurations.l : AppDurations.m
      ..forward(from: 0.0);
  }

  @override
  void dispose() {
    _riseCurve.dispose();
    _fallCurve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) =>
          Transform.translate(offset: Offset(0, -_offset.value), child: child),
    );
  }
}

/// 列表项交错入场（规范 §8「Appear on load」）。
///
/// 包裹列表项，按 [index] 施加延迟后播放「淡入淡出 + 滑动」进入动画：
/// 单项 [AppDurations.l]（250ms）+ [AppDurations.enter]，TranslationY
/// [slideOffsetDp] → 0（列表项按 §8 传 [listSlideOffsetDp] = 20dp，默认沿用
/// §3 通用模式的 16dp）。前 6 项（index 0–5）每项依次延迟 +30ms（见
/// [staggerDelayForIndex]），第 7 项起（index ≥ 6）无延迟立即入场。
/// 仅在挂载时播放一次（首次加载语义）：页面 Pop 恢复或原地刷新重建时本组件
/// State 保留，不会重复触发交错入场（规范 §1「内部列表项不重复触发」）。
class StaggeredListAppear extends StatefulWidget {
  const StaggeredListAppear({
    super.key,
    required this.index,
    required this.child,
    this.axis = FadeSlideAxis.vertical,
    this.slideOffsetDp = _slideVerticalDp,
  });

  final int index;
  final Widget child;
  final FadeSlideAxis axis;

  /// 纵向入场位移（dp）：§3 通用模式 16，§8 列表项 [listSlideOffsetDp] = 20。
  /// 仅在 [FadeSlideAxis.vertical] 下生效。
  final double slideOffsetDp;

  /// 参与交错的前 N 项（规范 §8：首屏前 6 项）。
  static const int staggeredItemCount = 6;

  /// 列表项入场位移 20dp（规范 §8「Appear on load」TranslationY +20dp → 0）。
  static const double listSlideOffsetDp = _listSlideVerticalDp;

  /// 计算给定 [index] 的交错延迟。
  ///
  /// index 0–5 返回 index × 30ms；index ≥ 6（及负值）返回 [Duration.zero]，
  /// 即无延迟立即入场（规范 §8「第 7 项起无延迟」）。
  static Duration staggerDelayForIndex(int index) {
    if (index <= 0 || index >= staggeredItemCount) {
      return Duration.zero;
    }
    return _staggerStep * index;
  }

  @override
  State<StaggeredListAppear> createState() => _StaggeredListAppearState();
}

class _StaggeredListAppearState extends State<StaggeredListAppear>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _animation;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: AppDurations.l);
    _animation = CurvedAnimation(
      parent: _controller,
      curve: AppDurations.enter,
    );
    final Duration delay = StaggeredListAppear.staggerDelayForIndex(
      widget.index,
    );
    if (delay == Duration.zero) {
      _controller.forward();
    } else {
      _timer = Timer(delay, () {
        if (mounted) {
          _controller.forward();
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _animation.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _fadeSlideTransform(
      widget.child,
      _animation,
      widget.axis,
      verticalDp: widget.slideOffsetDp,
    );
  }
}

/// 「淡入淡出 + 滑动」的共享变换：透明度随 [animation]，位移按 [axis] 从
/// +[verticalDp]（纵向，默认 16dp）或 +30%（横向）回到 0。[FadeSlide] 与
/// [StaggeredListAppear] 共用，避免两处重复实现（规范 §3 / §8）。
Widget _fadeSlideTransform(
  Widget child,
  Animation<double> animation,
  FadeSlideAxis axis, {
  double verticalDp = _slideVerticalDp,
}) {
  return AnimatedBuilder(
    animation: animation,
    child: child,
    builder: (context, child) {
      final double remain = 1.0 - animation.value;
      final Widget faded = FadeTransition(opacity: animation, child: child!);
      if (axis == FadeSlideAxis.vertical) {
        return Transform.translate(
          offset: Offset(0, verticalDp * remain),
          child: faded,
        );
      }
      return FractionalTranslation(
        translation: Offset(_slideHorizontalFraction * remain, 0),
        child: faded,
      );
    },
  );
}

/// 三种淡入淡出模式共享的控制器实现：进入用 [inDuration] + [AppDurations.enter]，
/// 退出用 [outDuration] + [AppDurations.exit]，由 [CurvedAnimation] 的
/// curve / reverseCurve 自动按方向取曲线。[builder] 负责各模式的具体变换。
class _FadePattern extends StatefulWidget {
  const _FadePattern({
    required this.child,
    required this.visible,
    required this.inDuration,
    required this.outDuration,
    required this.builder,
  });

  final Widget child;
  final bool visible;
  final Duration inDuration;
  final Duration outDuration;
  final Widget Function(Widget child, Animation<double> animation) builder;

  @override
  State<_FadePattern> createState() => _FadePatternState();
}

class _FadePatternState extends State<_FadePattern>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.inDuration);
    _animation = CurvedAnimation(
      parent: _controller,
      curve: AppDurations.enter,
      reverseCurve: AppDurations.exit,
    );
    if (widget.visible) {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(_FadePattern oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible != widget.visible) {
      _controller.duration = widget.visible
          ? widget.inDuration
          : widget.outDuration;
      if (widget.visible) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(widget.child, _animation);
  }
}

/// 遮罩目标不透明度（规范 §9 Dialog / Bottom sheet：Scrim Alpha 0 → 0.5）。
const double _scrimAlpha = 0.5;

/// 弹窗抬起高度（规范 §9 Dialog：Elevation 0dp → 6dp）。
const double _dialogElevationDp = 6;

/// 规范 §9 的遮罩色：取主题 scrim 色叠 0.5 不透明度，由 Flutter 的 barrier
/// 动画负责 Alpha 0 ↔ 0.5，不在这里再叠一层遮罩。
Color appScrimColor(BuildContext context) {
  return Theme.of(context).colorScheme.scrim.withValues(alpha: _scrimAlpha);
}

/// 按方向取规范缓动：进入 [AppDurations.enter]（decelerate），退出
/// [AppDurations.exit]（accelerate，Flutter 无该 getter，token 绑定 easeIn）。
///
/// 路由动画退出时 value 由 1 回到 0，与 [CurvedAnimation] 的 reverseCurve
/// 语义一致；这里直接 transform，避免每帧新建需要 dispose 的 CurvedAnimation。
double _directionalCurve(Animation<double> animation) {
  final Curve curve = animation.status == AnimationStatus.reverse
      ? AppDurations.exit
      : AppDurations.enter;
  return curve.transform(animation.value);
}

/// 规范 §9 弹窗进出场变换（Dialog Enter / Exit），供 showDialog 的
/// transitionBuilder 使用。
///
/// 进入 [AppDurations.l]（250ms）：Scale 0.85 → 1.0、Alpha 0 → 1、
/// Elevation 0dp → 6dp；退出 [AppDurations.s]（150ms）：Scale 1.0 → 0.90、
/// Alpha 1 → 0、Elevation 6dp → 0dp。时长由 [showAppDialog] 绑定，本函数只
/// 负责缓动与端点。
///
/// Elevation 经 DialogTheme 下发给弹窗自己的 Material（AlertDialog 读
/// dialogTheme.elevation），不重造卡面、不叠第二层阴影。
Widget appDialogTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  return AnimatedBuilder(
    animation: animation,
    child: child,
    builder: (context, child) {
      final double t = _directionalCurve(animation);
      final bool exiting = animation.status == AnimationStatus.reverse;
      final double begin = exiting ? _scaleExit : _scaleEnter;
      final double scale = begin + (1.0 - begin) * t;
      return DialogTheme(
        data: DialogTheme.of(context)
            .copyWith(elevation: _dialogElevationDp * t),
        child: Opacity(
          opacity: t,
          child: Transform.scale(scale: scale, child: child),
        ),
      );
    },
  );
}

/// 规范 §9 弹窗统一入口：把 [appDialogTransition] 绑到弹窗路由上，进入
/// [AppDurations.l]（250ms）、退出 [AppDurations.s]（150ms），遮罩取
/// [appScrimColor]（Alpha 0 → 0.5，由 barrier 动画负责）。
///
/// 本版 Flutter 的 showDialog 不再暴露 transitionBuilder / transitionDuration
/// （只留 animationStyle，且其 reverseDuration 对 DialogRoute 无效），故直接
/// 推 showDialog 内部用的同一条 DialogRoute，由 [_AppDialogRoute] 覆写进出场
/// 时长与变换。barrierDismissible / builder / 返回值与 showDialog 一致。
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  bool useRootNavigator = true,
}) {
  final NavigatorState navigator = Navigator.of(
    context,
    rootNavigator: useRootNavigator,
  );
  return navigator.push<T>(
    _AppDialogRoute<T>(
      context: context,
      builder: builder,
      barrierDismissible: barrierDismissible,
      barrierColor: appScrimColor(context),
      themes: InheritedTheme.capture(from: context, to: navigator.context),
      traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
    ),
  );
}

/// [showAppDialog] 的路由：进入 [AppDurations.l]、退出 [AppDurations.s]，
/// 变换交给 [appDialogTransition]（不叠 DialogRoute 自带的第二层淡入缩放）。
class _AppDialogRoute<T> extends DialogRoute<T> {
  _AppDialogRoute({
    required super.context,
    required super.builder,
    super.themes,
    super.barrierDismissible,
    super.barrierColor,
    super.traversalEdgeBehavior,
  }) : super(animationStyle: AnimationStyle(duration: AppDurations.l));

  @override
  Duration get reverseTransitionDuration => AppDurations.s;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return appDialogTransition(context, animation, secondaryAnimation, child);
  }
}

/// 底部面板抬起高度（规范 §9 Bottom sheet：Elevation 0dp → 8dp）。
const double _sheetElevationDp = 8;

/// 规范 §9 底部面板进出场（Bottom sheet Enter / Exit）。
///
/// 进入 [AppDurations.xl]（300ms）+ [AppDurations.enter]（decelerate），退出
/// [AppDurations.l]（250ms）+ [AppDurations.exit]（accelerate）。面板的
/// TranslationY +100% ↔ 0 由 ModalBottomSheetRoute 自带的 FractionalTranslation
/// 负责，这里只把时长与缓动绑到规范 token。
const AnimationStyle _sheetAnimation = AnimationStyle(
  duration: AppDurations.xl,
  reverseDuration: AppDurations.l,
  curve: AppDurations.enter,
  reverseCurve: AppDurations.exit,
);

/// 规范 §9 底部面板统一入口：showModalBottomSheet 不接受 transitionBuilder，
/// 故用其内置的 [showModalBottomSheet] `sheetAnimationStyle` 钩子绑定
/// [_sheetAnimation]（进出场时长与缓动），遮罩取 [appScrimColor]
/// （Alpha 0 → 0.5，由 barrier 动画负责），面板 elevation 取规范 8dp。
///
/// elevation 只能给到终点值：Flutter 的 BottomSheet 卡面 elevation 由路由静态
/// 下发，公开钩子无法逐帧插值，故不重造卡面、不叠第二层阴影。
/// showDragHandle / isScrollControlled / constraints / shape / builder / 返回值
/// 原样透传，调用方行为不变。
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool? showDragHandle,
  bool isScrollControlled = false,
  BoxConstraints? constraints,
  ShapeBorder? shape,
}) {
  return showModalBottomSheet<T>(
    context: context,
    builder: builder,
    showDragHandle: showDragHandle,
    isScrollControlled: isScrollControlled,
    constraints: constraints,
    shape: shape,
    elevation: _sheetElevationDp,
    barrierColor: appScrimColor(context),
    sheetAnimationStyle: _sheetAnimation,
  );
}

/// 空/错状态进入缩放起点（规范 §10 Empty / Error Enter：Scale 0.90 → 1.0）。
const double _emptyErrorScaleEnter = 0.90;

/// 空/错状态退出缩放终点（规范 §10 Empty / Error Exit：Scale 1.0 → 0.95）。
const double _emptyErrorScaleExit = 0.95;

/// 空/错状态进入纵向位移（规范 §10：TranslationY +12dp → 0）。
const double _emptyErrorSlideDp = 12;

/// 空/错状态进出场（规范 §10 Empty / Error State Enter & Exit）。
///
/// 包裹空态/错误态的插画与文案：进入 [AppDurations.l]（250ms）+
/// [AppDurations.enter]，Alpha 0 → 1、Scale 0.90 → 1.0、TranslationY
/// +12dp → 0；退出 [AppDurations.s]（150ms）+ [AppDurations.exit]，
/// Alpha 1 → 0、Scale 1.0 → 0.95（退出无位移）。
///
/// [visible] 为 true 时首次构建即播放进入；false 时播放退出，子组件保留在
/// 树中（由使用方在退出播完后移出树）。应用内暂无共享空/错视图组件，
/// 各页面的空态/错误态用本组件包裹即可获得规范进出场。
class EmptyErrorState extends StatelessWidget {
  const EmptyErrorState({super.key, required this.child, this.visible = true});

  final Widget child;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    return _FadePattern(
      visible: visible,
      inDuration: AppDurations.l,
      outDuration: AppDurations.s,
      builder: (child, animation) => AnimatedBuilder(
        animation: animation,
        child: child,
        builder: (context, child) {
          final double t = animation.value;
          // 进入 0.90 → 1.0；退出 1.0 → 0.95（t 在退出时由 1 回到 0）。
          final double begin = visible
              ? _emptyErrorScaleEnter
              : _emptyErrorScaleExit;
          final double scale = begin + (1.0 - begin) * t;
          // 位移只属于进入（+12dp → 0）；退出按规范只有 Alpha 与 Scale。
          final double dy = visible ? _emptyErrorSlideDp * (1.0 - t) : 0.0;
          return FadeTransition(
            opacity: animation,
            child: Transform.translate(
              offset: Offset(0, dy),
              // 三轴同比缩放：Transform.scale 的矩阵 Z 轴恒为 1，
              // getMaxScaleOnAxis() 量不出真实缩放（同 ClearButtonReveal）。
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.diagonal3Values(scale, scale, scale),
                child: child,
              ),
            ),
          );
        },
      ),
      child: child,
    );
  }
}

/// 加载指示器（规范 §10 Loading Spinner）。
///
/// 持续旋转 0° → 360°：[AppDurations.loop]（1000ms）+ [AppDurations.loopCurve]
/// （linear）；出现/消失 [AppDurations.s]（150ms），Scale 0 ↔ 1、Alpha 0 ↔ 1
/// （进入 [AppDurations.enter]、退出 [AppDurations.exit]）。
///
/// [child] 为指示器本体，缺省 [CircularProgressIndicator]（规范 §10 圆形加载
/// 指示器）；旋转施加在 child 上，自定义指示器同样生效。完全隐藏后停转，
/// 避免闲置循环空转。
class LoadingSpinner extends StatefulWidget {
  const LoadingSpinner({super.key, this.child, this.visible = true});

  final Widget? child;
  final bool visible;

  @override
  State<LoadingSpinner> createState() => _LoadingSpinnerState();
}

class _LoadingSpinnerState extends State<LoadingSpinner>
    with TickerProviderStateMixin {
  late final AnimationController _spinController;
  late final CurvedAnimation _spinCurve;
  late final Animation<double> _turns;
  late final AnimationController _appearController;
  late final CurvedAnimation _appear;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      vsync: this,
      duration: AppDurations.loop,
    );
    _spinCurve = CurvedAnimation(
      parent: _spinController,
      curve: AppDurations.loopCurve,
    );
    _turns = Tween<double>(begin: 0.0, end: 1.0).animate(_spinCurve);
    _appearController = AnimationController(
      vsync: this,
      duration: AppDurations.s,
    );
    _appear = CurvedAnimation(
      parent: _appearController,
      curve: AppDurations.enter,
      reverseCurve: AppDurations.exit,
    );
    _appearController.addStatusListener(_handleAppearStatus);
    if (widget.visible) {
      _appearController.forward();
      _spinController.repeat();
    }
  }

  void _handleAppearStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed) _spinController.stop();
  }

  @override
  void didUpdateWidget(LoadingSpinner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible == widget.visible) return;
    if (widget.visible) {
      if (!_spinController.isAnimating) _spinController.repeat();
      _appearController.forward();
    } else {
      _appearController.reverse();
    }
  }

  @override
  void dispose() {
    _appearController.removeStatusListener(_handleAppearStatus);
    _appear.dispose();
    _spinCurve.dispose();
    _appearController.dispose();
    _spinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _appear,
      child: RotationTransition(
        turns: _turns,
        child: widget.child ?? const CircularProgressIndicator(),
      ),
      builder: (context, child) {
        final double t = _appear.value;
        return FadeTransition(
          opacity: _appear,
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.diagonal3Values(t, t, t),
            child: child,
          ),
        );
      },
    );
  }
}

/// 下拉刷新位移（规范 §10 Pull-to-refresh：TranslationY 0 → +64dp）。
const double _refreshDisplacementDp = 64;

/// 下拉刷新（规范 §10 Pull-to-refresh Enter / Exit）。
///
/// 用系统 [RefreshIndicator]，不自造下拉手势。位移绑到规范 64dp
/// （[RefreshIndicator.displacement]）；进入/退出 200ms（M，decelerate 进 /
/// accelerate 出）与 Scale 0.5 → 1.0、Alpha 0 → 1 为 RefreshIndicator 内置
/// 行为（SDK refresh_indicator.dart 的 _kIndicatorScaleDuration = 200ms，
/// 与 [AppDurations.m] 一致）：本版 Flutter 未公开时长/缓动参数，无法在不
/// 重造手势与动画的前提下进一步绑定，内置值已符合规范。
class AppRefreshIndicator extends StatelessWidget {
  const AppRefreshIndicator({
    super.key,
    required this.onRefresh,
    required this.child,
  });

  final RefreshCallback onRefresh;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      displacement: _refreshDisplacementDp,
      child: child,
    );
  }
}
