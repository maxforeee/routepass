import 'package:flutter/material.dart';

import '../../core/config.dart';
import '../../core/service_locator.dart';
import '../../core/theme.dart';
import '../../router/app_router.dart';
import '../../widgets/force_upgrade_dialog.dart';
import '../../widgets/route_pass_logo.dart';

/// 启动页（第 2 章 §14.4：按序 6 步，总耗时 ≤2.0 秒，断网不卡启动页，一次性跳转）。
///
/// 步骤：读 kv 里的“上次登录用户 ID”→ 校验登录态（Mock：getCurrentUser）
/// → 校验内容版本（Mock：checkUpgrade，hard 才弹 G-05）
/// → 校验最小可用版本 → 拉取首屏必需配置（Mock：getContentVersion）
/// → 决定去向（已登录 → /home，未登录 → /login）。
/// hard 升级只弹 dialog 不自动跳转；检查失败（离线等）直接放行到原定去向。
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    _decide();
  }

  Future<void> _decide() async {
    // 两项 Mock 检查并行执行（各设 1.5 秒超时，超时/失败直接放行），最坏 1.5 秒；
    // 若不足 2 秒则补足剩余时长，保证启动页稳定展示约 2 秒再决定去向。
    final stopwatch = Stopwatch()..start();
    final results = await Future.wait<Object?>([
      ServiceLocator.authService
          .getCurrentUser()
          .timeout(const Duration(milliseconds: 1500))
          .then<Object?>((user) => user, onError: (_) => null),
      checkAndShowForceUpgrade(context)
          .timeout(const Duration(milliseconds: 1500))
          .then<Object?>((upgrade) => upgrade, onError: (_) => null),
    ]);
    final loggedIn = results[0] != null;
    final hardUpgrade = results[1] == true;
    if (!mounted) return;
    final elapsed = stopwatch.elapsedMilliseconds;
    if (elapsed < 2000) {
      await Future<void>.delayed(Duration(milliseconds: 2000 - elapsed));
    }
    if (!mounted) return;
    // hard 升级：dialog 已弹出，只停在启动页，不自动跳转。
    if (hardUpgrade) return;
    Navigator.of(context)
        .pushReplacementNamed(loggedIn ? AppRoutes.home : AppRoutes.login);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBackgroundLight,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const RoutePassLogo(size: 72),
            const SizedBox(height: 28),
            Text(AppConfig.appNameCn, style: AppTheme.brandTitleStyle),
            const SizedBox(height: 14),
            Text(
              AppConfig.appName.toUpperCase(),
              style: AppTheme.brandCaptionStyle,
            ),
          ],
        ),
      ),
    );
  }
}
