/// 页面转场（规格文档第 3 章 §22.3.4）。
///
/// 页面 push：260ms“纸张滑动”（横向滑入 + 淡入）。
/// 减少动效开启时（MediaQuery.disableAnimations）时长为 0。
library;

import 'package:flutter/material.dart';

/// 按“减少动效”设置把时长钳制为 0。
Duration transitionDuration(BuildContext context, Duration duration) {
  return MediaQuery.of(context).disableAnimations ? Duration.zero : duration;
}

/// 纸张滑动路由：新页从右滑入、旧页淡出，默认 260ms。
class SharedAxisPageRoute<T> extends PageRouteBuilder<T> {
  SharedAxisPageRoute({
    required WidgetBuilder builder,
    super.settings,
    super.transitionDuration = const Duration(milliseconds: 260),
  }) : super(
         pageBuilder: (context, animation, secondaryAnimation) =>
             builder(context),
         reverseTransitionDuration: transitionDuration,
         transitionsBuilder: (context, animation, secondaryAnimation, child) {
           final slide =
               Tween<Offset>(
                 begin: const Offset(0.08, 0),
                 end: Offset.zero,
               ).animate(
                 CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
               );
           final fade = Tween<double>(
             begin: 0.0,
             end: 1.0,
           ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut));
           return SlideTransition(
             position: slide,
             child: FadeTransition(opacity: fade, child: child),
           );
         },
       );
}
