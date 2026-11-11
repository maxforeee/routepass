/// 强制升级 dialog（G-05，第 3 章 §22.2.2、§22.10.1）。
///
/// 全屏遮罩；卡圆角 24；仅“去升级” + “退出”；不可关闭，返回键无效，阻断答题。
/// 触发条件：compatibility == 'hard' 或收到 426。
///
/// 本文件只做 UI：Mock 的 checkUpgrade 恒返回 compatibility 'ok'，所以
/// 正常流程下本 dialog 永不弹出；checkAndShowForceUpgrade 供启动流程调用，
/// 命中 hard 时才弹。“去升级”在 Mock 下没有真实升级地址，只给提示。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_snackbar.dart';
import '../core/service_locator.dart';

/// 启动时检查一次：hard 才弹 G-05。返回 true 表示已弹出（调用方应阻断进入业务页）。
Future<bool> checkAndShowForceUpgrade(BuildContext context) async {
  final check = await ServiceLocator.contentService.checkUpgrade();
  if (check.compatibility != 'hard') return false;
  if (!context.mounted) return true;
  await showForceUpgradeDialog(
    context,
    latestVersion: check.latest,
    upgradeUrl: check.upgrade_url,
  );
  return true;
}

/// 显示 G-05：不可关闭（barrierDismissible false + PopScope canPop false）。
Future<void> showForceUpgradeDialog(
  BuildContext context, {
  required String latestVersion,
  required String upgradeUrl,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('需要更新 App'),
          content: Text(
            '当前版本过旧，请更新到 $latestVersion 后继续使用。更新前答题入口已禁用。',
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (upgradeUrl.isEmpty) {
                  showAppSnackBar(dialogContext, '演示模式：升级地址未配置');
                } else {
                  showAppSnackBar(dialogContext, '演示模式：无法打开升级地址');
                }
              },
              child: const Text('去升级'),
            ),
            FilledButton(
              onPressed: () => SystemNavigator.pop(),
              child: const Text('退出'),
            ),
          ],
        ),
      );
    },
  );
}
