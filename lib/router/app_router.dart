import 'package:flutter/material.dart';

import '../core/page_transition.dart';
import '../pages/base/login_page.dart';
import '../pages/base/profile_page.dart';
import '../pages/base/register_page.dart';
import '../pages/base/settings_page.dart';
import '../pages/base/splash_page.dart';
import '../pages/shell/app_shell.dart';

class AppRoutes {
  const AppRoutes._();

  static const String splash = '/splash';
  static const String login = '/login';
  static const String register = '/register';
  static const String home = '/home';
  static const String bankModules = '/bank/modules';
  static const String knowledge = '/knowledge';
  static const String toolbox = '/toolbox';
  static const String profile = '/profile';
  static const String settings = '/settings';
  static const String profileDevices = '/profile/devices';
  static const String bankQuiz = '/bank/quiz';
  static const String bankExam = '/bank/exam';
  static const String bankExamResult = '/bank/exam/result';
  static const String bankWrong = '/bank/wrong';
  static const String bankFavorites = '/bank/favorites';
  static const String bankDaily = '/bank/daily';
  static const String bankStats = '/bank/stats';
  static const String knowledgeList = '/knowledge/list';
  static const String knowledgePoint = '/knowledge/point';
  static const String knowledgeSearch = '/knowledge/search';
  static const String toolboxSubnet = '/toolbox/subnet';
  static const String toolboxPing = '/toolbox/ping';
  static const String toolboxPortscan = '/toolbox/portscan';
  static const String toolboxCli = '/toolbox/cli';
}

class AppRouter {
  static const String initialRoute = AppRoutes.splash;

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    final Widget page;
    switch (settings.name) {
      case AppRoutes.splash:
        page = const SplashPage();
      case AppRoutes.login:
        page = const LoginPage();
      case AppRoutes.register:
        page = const RegisterPage();
      case AppRoutes.home:
        page = const AppShell();
      case AppRoutes.profile:
        page = const ProfilePage();
      case AppRoutes.settings:
        page = const SettingsPage();
      default:
        // 未装配的深链/未知路由一律回首页外壳（§4.9.3），不报错。
        page = const AppShell();
    }
    final reduceMotion = WidgetsBinding.instance.platformDispatcher
        .accessibilityFeatures.disableAnimations;
    return SharedAxisPageRoute<void>(
      builder: (_) => page,
      settings: settings,
      transitionDuration:
          reduceMotion ? Duration.zero : const Duration(milliseconds: 260),
    );
  }
}
