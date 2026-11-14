/// 页面转场（规格文档第 3 章 §22.3.4、动画规范 v1.0 §1）。
///
/// Push（XL 300ms，standard）：子页 TranslationX +30% → 0%、Alpha 0 → 1、
/// Elevation 0 → 4dp；被压栈的主页 TranslationX 0% → -10%、Alpha 1 → 0.85。
/// Pop（L 250ms）：子页按 exit 曲线原路滑出（+30%、Alpha → 0、Elevation → 0），
/// 主页按 enter 曲线从 -10%/0.85 恢复到 0%/1.0。
/// 减少动效开启时（MediaQuery.disableAnimations）时长为 0。
library;

import 'package:flutter/material.dart';

import 'theme.dart';

/// 子页横向滑动比例（规范 §1：TranslationX +30% → 0%，相对子页宽度）。
const double _childSlideFraction = 0.30;

/// 主页被压栈时的横向退后比例（规范 §1：TranslationX 0% → -10%）。
const double _behindSlideFraction = -0.10;

/// 主页被压栈时的透明度（规范 §1：Alpha 1.0 → 0.85）。
const double _behindDimAlpha = 0.85;

/// 子页阴影高度（规范 §1：Elevation 0dp → 4dp，Pop 时回到 0dp）。
const double _childElevationDp = 4;

/// 按“减少动效”设置把时长钳制为 0。
Duration transitionDuration(BuildContext context, Duration duration) {
  return MediaQuery.of(context).disableAnimations ? Duration.zero : duration;
}

/// 纸张滑动路由：新页从右滑入并抬起阴影、旧页向左退后并压暗。
///
/// Push 默认 XL 300ms、Pop 默认 L 250ms；主页退后/恢复由 [secondaryAnimation]
/// 驱动，时长自动跟随压在它上面的那条路由（同为 XL/L）。
class SharedAxisPageRoute<T> extends PageRouteBuilder<T> {
  SharedAxisPageRoute({
    required WidgetBuilder builder,
    super.settings,
    super.transitionDuration = AppDurations.xl,
    super.reverseTransitionDuration = AppDurations.l,
  }) : super(
         pageBuilder: (context, animation, secondaryAnimation) =>
             builder(context),
         transitionsBuilder: (context, animation, secondaryAnimation, child) {
           // 子页：进入 standard、退出 exit（规范 §1 Push/Pop 子页两行）。
           final enter = CurvedAnimation(
             parent: animation,
             curve: AppDurations.standard,
             reverseCurve: AppDurations.exit,
           );
           // 主页：压栈 standard、恢复 enter（规范 §1 主页两行）。
           final behind = CurvedAnimation(
             parent: secondaryAnimation,
             curve: AppDurations.standard,
             reverseCurve: AppDurations.enter,
           );
           final Widget entering = SlideTransition(
             position: Tween<Offset>(
               begin: const Offset(_childSlideFraction, 0),
               end: Offset.zero,
             ).animate(enter),
             child: FadeTransition(
               opacity: enter,
               child: AnimatedBuilder(
                 animation: enter,
                 child: child,
                 builder: (context, child) => DecoratedBox(
                   decoration: BoxDecoration(
                     boxShadow: <BoxShadow>[
                       BoxShadow(
                         color: AppColors.shadow,
                         blurRadius: _childElevationDp * enter.value * 2,
                         offset: Offset(0, _childElevationDp * enter.value / 2),
                       ),
                     ],
                   ),
                   child: child!,
                 ),
               ),
             ),
           );
           // 只包变换、不重建子树：主页内部的列表交错入场只在 initState 播放，
           // 恢复前台时不会重复触发（规范 §1「内部列表项不重复触发交错入场」）。
           return SlideTransition(
             position: Tween<Offset>(
               begin: Offset.zero,
               end: const Offset(_behindSlideFraction, 0),
             ).animate(behind),
             child: FadeTransition(
               opacity: Tween<double>(
                 begin: 1.0,
                 end: _behindDimAlpha,
               ).animate(behind),
               child: entering,
             ),
           );
         },
       );
}
