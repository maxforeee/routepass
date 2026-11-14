import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'router/app_router.dart';

/// 全局导航 key：refreshToken 失效时 AuthService 用它把用户送回登录页
/// （不依赖具体页面的 context）。
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

class RoutePassApp extends StatelessWidget {
  const RoutePassApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RoutePass',
      navigatorKey: appNavigatorKey,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      builder: (context, child) {
        // §22.3：系统字体缩放夹在 1.0–1.5 倍。
        return MediaQuery.withClampedTextScaling(
          minScaleFactor: 1.0,
          maxScaleFactor: 1.5,
          child: child ?? const SizedBox.shrink(),
        );
      },
      initialRoute: AppRoutes.splash,
      onGenerateRoute: AppRouter.onGenerateRoute,
      onUnknownRoute: (settings) {
        return AppRouter.onGenerateRoute(
          RouteSettings(name: AppRoutes.home, arguments: settings.arguments),
        );
      },
    );
  }
}
