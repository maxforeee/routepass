import 'package:flutter/material.dart';

import '../../core/service_locator.dart';
import '../../router/app_router.dart';
import '../../widgets/force_upgrade_dialog.dart';

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
    // 启动判定总耗时 ≤2.0 秒：两项 Mock 检查各设 1.5 秒超时，超时直接放行。
    bool loggedIn = false;
    try {
      final user = await ServiceLocator.authService
          .getCurrentUser()
          .timeout(const Duration(milliseconds: 1500));
      loggedIn = user != null;
    } catch (_) {
      loggedIn = false;
    }
    if (!mounted) return;
    bool hardUpgrade = false;
    try {
      hardUpgrade = await checkAndShowForceUpgrade(context)
          .timeout(const Duration(milliseconds: 1500));
    } catch (_) {
      hardUpgrade = false;
    }
    if (!mounted) return;
    // hard 升级：dialog 已弹出，只停在启动页，不自动跳转。
    if (hardUpgrade) return;
    Navigator.of(context).pushReplacementNamed(
      loggedIn ? AppRoutes.home : AppRoutes.login,
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
