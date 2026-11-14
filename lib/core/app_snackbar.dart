/// 全局 Snackbar（G-04，第 3 章 §22.2.2；动画规范 v1.0 §12）。
///
/// 高 48、圆角 12、inverseSurface、4 秒自动消失、可带 1 个动作、底栏上 16。
///
/// 进出场动画绑规范 §12：进入 [AppDurations.l]（250ms）+ [AppDurations.enter]
/// （decelerate），退出 [AppDurations.s]（150ms）+ [AppDurations.exit]
/// （accelerate）；TranslationY +100% ↔ 0、Alpha 0 ↔ 1、Elevation 0dp ↔ 6dp。
/// 机制仍走 ScaffoldMessenger（队列、4 秒计时、划走关闭、hideCurrentSnackBar
/// 全不变），只换动画：
///  * showSnackBar 会强制用 messenger 内部控制器替换条的动画
///    （`snackBar.withAnimation(controller)`），构造参数 animation 传了也会被
///    覆盖；故这里覆写 [SnackBar.withAnimation] 截获该控制器，把规范进出场
///    时长绑上去，再由它驱动规范变换，与计时/划走天然同步。
///  * 真实条经 `withAnimation(常量 1)` 整体复制，内置 M3 淡入/高度动画被钉在
///    终点，不叠第二层动画；Elevation 经 SnackBarTheme 逐帧下发（条自己的
///    Material 读 snackBarTheme.elevation），不重造卡面、不叠第二层阴影。
///  * 应用内没有独立 Toast 机制，轻提示统一走 SnackBar，§12 的 Toast 变体
///    （Scale 0.90 ↔ 1.0）不适用。
library;

import 'package:flutter/material.dart';

import 'theme.dart';

/// Snackbar 抬起高度（规范 §12：Elevation 0dp → 6dp）。
const double _snackBarElevationDp = 6;

void showAppSnackBar(
  BuildContext context,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
  bool aboveNav = true,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      _AppSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.fromLTRB(16, 0, 16, aboveNav ? 92 : 16),
          action: actionLabel == null
              ? null
              : SnackBarAction(
                  label: actionLabel,
                  onPressed: onAction ?? () {},
                ),
        ),
      ),
    );
}

/// 规范 §12 动画包装：[_source] 是真实条的字段模板，本组件只负责进出场变换。
class _AppSnackBar extends SnackBar {
  _AppSnackBar(this._source) : super(content: _source.content);

  _AppSnackBar._driven(this._source, Animation<double> animation, {super.key})
    : super(content: _source.content, animation: animation);

  final SnackBar _source;

  @override
  SnackBar withAnimation(Animation<double> newAnimation, {Key? fallbackKey}) {
    // messenger 传入的是它自己的 AnimationController 本体：绑上规范进出场
    // 时长后，队列/计时/划走仍由它驱动，退出自动取 reverseDuration（150ms）。
    final AnimationController controller = newAnimation as AnimationController;
    controller
      ..duration = AppDurations.l
      ..reverseDuration = AppDurations.s;
    return _AppSnackBar._driven(_source, controller, key: key ?? fallbackKey);
  }

  @override
  State<SnackBar> createState() => _AppSnackBarState();
}

class _AppSnackBarState extends State<_AppSnackBar> {
  late final CurvedAnimation _animation;

  @override
  void initState() {
    super.initState();
    // 与 app_animations.dart 的 _FadePattern 同一模式：curve / reverseCurve
    // 按控制器方向自动取进入 decelerate / 退出 accelerate。
    _animation = CurvedAnimation(
      parent: widget.animation!,
      curve: AppDurations.enter,
      reverseCurve: AppDurations.exit,
    );
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 常量 1 把内置淡入/高度动画钉在终点；withAnimation 整体复制全部字段，
    // 不逐字段重造条面。
    final Widget bar = widget._source.withAnimation(
      const AlwaysStoppedAnimation<double>(1.0),
    );
    return AnimatedBuilder(
      animation: _animation,
      child: bar,
      builder: (context, child) {
        final double t = _animation.value;
        return SnackBarTheme(
          data: SnackBarTheme.of(context)
              .copyWith(elevation: _snackBarElevationDp * t),
          child: FractionalTranslation(
            translation: Offset(0, 1 - t),
            child: FadeTransition(opacity: _animation, child: child),
          ),
        );
      },
    );
  }
}
