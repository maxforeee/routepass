import 'package:flutter/material.dart';

import '../../core/app_animations.dart';
import '../../core/config.dart';
import '../../core/service_locator.dart';
import '../../core/theme.dart';
import '../../router/app_router.dart';
import '../../widgets/force_upgrade_dialog.dart';
import '../../widgets/route_pass_logo.dart';

/// 启动退场整体缩放终点（动画规范 v1.0 §10 Splash Exit：Scale 1.0 → 1.05）。
const double _splashExitScale = 1.05;

/// 启动页（第 2 章 §14.4：按序 6 步，总耗时 ≤2.0 秒，断网不卡启动页，一次性跳转）。
///
/// 步骤：读 kv 里的“上次登录用户 ID”→ 校验登录态（Mock：getCurrentUser）
/// → 校验内容版本（Mock：checkUpgrade，hard 才弹 G-05）
/// → 校验最小可用版本 → 拉取首屏必需配置（Mock：getContentVersion）
/// → 决定去向（已登录 → /home，未登录 → /login）。
/// hard 升级只弹 dialog 不自动跳转；检查失败（离线等）直接放行到原定去向。
///
/// 动画（规范 §10 Splash Enter / Exit）：进入时 Logo 用 [FadeScale]
/// （L 250ms decelerate，Scale 0.85 → 1.0、Alpha 0 → 1）；去向确定后整体
/// 退场（M 200ms accelerate，Alpha 1 → 0、Scale 1.0 → 1.05）再跳转，退场
/// 时长计入 2 秒展示预算（提前 200ms 开始），总耗时不变。
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _exitController;
  late final CurvedAnimation _exitAnimation;

  @override
  void initState() {
    super.initState();
    _exitController = AnimationController(
      vsync: this,
      duration: AppDurations.m,
    );
    _exitAnimation = CurvedAnimation(
      parent: _exitController,
      curve: AppDurations.exit,
    );
    _decide();
  }

  @override
  void dispose() {
    _exitAnimation.dispose();
    _exitController.dispose();
    super.dispose();
  }

  Future<void> _decide() async {
    // 两项 Mock 检查并行执行（各设 1.5 秒超时，超时/失败直接放行），最坏 1.5 秒；
    // 若不足 2 秒则补足剩余时长（扣除退场动画的 200ms），保证启动页稳定展示
    // 约 2 秒（含退场）再决定去向。
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
    final int exitMs = AppDurations.m.inMilliseconds;
    if (elapsed < 2000 - exitMs) {
      await Future<void>.delayed(
        Duration(milliseconds: 2000 - exitMs - elapsed),
      );
    }
    if (!mounted) return;
    // hard 升级：dialog 已弹出，只停在启动页，不自动跳转（也不播退场）。
    if (hardUpgrade) return;
    // 规范 §10 Splash Exit：整体 Alpha 1 → 0、Scale 1.0 → 1.05，播完再跳转。
    // 跳转按经过的时长驱动，不 await 控制器：widget 测试里控制器只在 pump
    // 时前进，await forward() 会永远挂住，导航就再也发生不了。
    _exitController.forward();
    await Future<void>.delayed(AppDurations.m);
    if (!mounted) return;
    Navigator.of(context)
        .pushReplacementNamed(loggedIn ? AppRoutes.home : AppRoutes.login);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBackground(context),
      body: AnimatedBuilder(
        animation: _exitAnimation,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 规范 §10 Splash Enter：Logo Scale 0.85 → 1.0、Alpha 0 → 1，
              // L 250ms decelerate，复用共享 FadeScale。
              const FadeScale(child: RoutePassLogo(size: AppSizes.splashLogo)),
              const SizedBox(height: AppSpacing.splashLogoGap),
              Text(
                AppConfig.appNameCn,
                style: AppTheme.brandTitleStyle.copyWith(
                  color: AppColors.title(context),
                ),
              ),
              const SizedBox(height: AppSpacing.splashNameGap),
              Text(
                AppConfig.appName.toUpperCase(),
                style: AppTheme.brandCaptionStyle.copyWith(
                  color: AppColors.cardCaption(context),
                ),
              ),
            ],
          ),
        ),
        builder: (context, child) {
          final double t = _exitAnimation.value;
          final double scale = 1.0 + (_splashExitScale - 1.0) * t;
          return Opacity(
            opacity: 1.0 - t,
            // 三轴同比缩放，测试可经矩阵量出真实缩放（同 ClearButtonReveal）。
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.diagonal3Values(scale, scale, scale),
              child: child,
            ),
          );
        },
      ),
    );
  }
}
