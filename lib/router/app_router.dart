import 'package:flutter/material.dart';

import '../pages/bank/module_list_page.dart';
import '../pages/base/login_page.dart';
import '../pages/base/profile_page.dart';
import '../pages/base/register_page.dart';
import '../pages/base/settings_page.dart';
import '../pages/base/splash_page.dart';
import '../pages/home/home_page.dart';
import '../pages/knowledge/knowledge_home_page.dart';
import '../pages/toolbox/toolbox_home_page.dart';

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
}

class AppRouter {
  const AppRouter._();

  static Route<void> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case AppRoutes.splash:
        return MaterialPageRoute<void>(
          builder: (_) => const SplashPage(),
          settings: settings,
        );
      case AppRoutes.login:
        return MaterialPageRoute<void>(
          builder: (_) => const LoginPage(),
          settings: settings,
        );
      case AppRoutes.register:
        return MaterialPageRoute<void>(
          builder: (_) => const RegisterPage(),
          settings: settings,
        );
      case AppRoutes.home:
        return MaterialPageRoute<void>(
          builder: (_) => const HomePage(),
          settings: settings,
        );
      case AppRoutes.bankModules:
        return MaterialPageRoute<void>(
          builder: (_) => const BankModuleListPage(),
          settings: settings,
        );
      case AppRoutes.knowledge:
        return MaterialPageRoute<void>(
          builder: (_) => const KnowledgeHomePage(),
          settings: settings,
        );
      case AppRoutes.toolbox:
        return MaterialPageRoute<void>(
          builder: (_) => const ToolboxHomePage(),
          settings: settings,
        );
      case AppRoutes.profile:
        return MaterialPageRoute<void>(
          builder: (_) => const ProfilePage(),
          settings: settings,
        );
      case AppRoutes.settings:
        return MaterialPageRoute<void>(
          builder: (_) => const SettingsPage(),
          settings: settings,
        );
      default:
        return MaterialPageRoute<void>(
          builder: (_) => const HomePage(),
          settings: settings,
        );
    }
  }
}
