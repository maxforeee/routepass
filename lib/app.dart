import 'package:flutter/material.dart';

import 'router/app_router.dart';

class RoutePassApp extends StatelessWidget {
  const RoutePassApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RoutePass',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E7D8A)),
      ),
      initialRoute: AppRoutes.splash,
      onGenerateRoute: AppRouter.onGenerateRoute,
      onUnknownRoute: (settings) {
        return AppRouter.onGenerateRoute(
          RouteSettings(
            name: AppRoutes.home,
            arguments: settings.arguments,
          ),
        );
      },
    );
  }
}
