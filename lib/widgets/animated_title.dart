/// F20 §3 共享标题切换动画（动画规范 v1.0 §3「Title Enter / Exit」）。
///
/// 顶部栏标题与内容页头（[PageHeader]）共用这一份标题动效，避免两处重复实现：
///  * 新标题进入：[AppDurations.m]（200ms）+ [AppDurations.enter]（decelerate），
///    Alpha 0 → 1，TranslationY +8dp → 0。
///  * 旧标题退出：[AppDurations.s]（150ms）+ [AppDurations.exit]（accelerate），
///    Alpha 1 → 0，TranslationY 0 → -8dp。
///
/// 时长与缓动一律取 [AppDurations] token，不写死毫秒值。
library;

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// 标题切换的纵向位移（规范 §3：TranslationY ±8dp）。
const double _titleSlideDp = 8;

/// 标题进入 / 退出动画（规范 §3「Title Enter / Exit」）。
///
/// 标题字符串变化时播放「旧标题淡出上移、新标题淡入下移归位」的切换动画；
/// 首次挂载播放进入动画。[AnimatedAppBar] 与 [PageHeader] 共用本组件。
class AnimatedTitle extends StatelessWidget {
  const AnimatedTitle({
    super.key,
    required this.title,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
  });

  final String title;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AppDurations.m,
      reverseDuration: AppDurations.s,
      switchInCurve: AppDurations.enter,
      switchOutCurve: AppDurations.exit,
      transitionBuilder: _titleTransition,
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: AlignmentDirectional.centerStart,
        children: <Widget>[...previousChildren, ?currentChild],
      ),
      child: Text(
        title,
        key: ValueKey<String>(title),
        style: style,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: overflow,
      ),
    );
  }
}

/// 「标题切换」的共享变换：进入 +8dp → 0，退出 0 → -8dp，透明度随动画。
///
/// [AnimatedSwitcher] 对进入 / 退出复用同一个 builder，用动画状态区分方向：
/// 进入子组件的控制器 forward（status forward），退出子组件的控制器 reverse
/// （status reverse / dismissed）。
Widget _titleTransition(Widget child, Animation<double> animation) {
  final bool exiting =
      animation.status == AnimationStatus.reverse ||
      animation.status == AnimationStatus.dismissed;
  final double beginDy = exiting ? -_titleSlideDp : _titleSlideDp;
  return FadeTransition(
    opacity: animation,
    child: AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, beginDy * (1.0 - animation.value)),
          child: child,
        );
      },
    ),
  );
}
