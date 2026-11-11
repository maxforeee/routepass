/// 版本/离线条（G-02，第 3 章 §22.2.2、§22.10.1）。
///
/// 高 36；圆角 0；soft = warningContainer；offline = surfaceVariant；
/// hard 不用条，用 G-05 dialog。位置在顶栏下（由外壳放在 tab 内容上方）。
/// soft 可关闭、点击看更新；offline 点击进同步诊断（同步诊断页未建时先给提示）。
///
/// 数据源：ContentService.checkUpgrade（compatibility）+
/// SyncService.getSyncStatus（state）。Mock 下恒为 ok + local_only，条默认隐藏。
library;

import 'package:flutter/material.dart';

import '../core/app_snackbar.dart';
import '../core/service_locator.dart';
import '../core/theme.dart';

/// G-02 的三种可见态之外的“隐藏”态由外壳处理：本 widget 在 ok 时返回空盒。
///
/// 本地 kv 通过 ServiceLocator.kvStore 读写（现在为内存实现，见 kv_store.dart）。
final _kvStore = ServiceLocator.kvStore;

class VersionBanner extends StatefulWidget {
  const VersionBanner({super.key});

  @override
  State<VersionBanner> createState() => _VersionBannerState();
}

class _VersionBannerState extends State<VersionBanner> {
  /// null = 加载中（先隐藏，等结果）；'ok' | 'soft' | 'offline'。
  String? _state;
  bool _dismissed = false;

  /// soft 条关闭后 7 天内不再提示（派生 kv 键，不在 §4.9.1 表内，见注释）。
  static const String _dismissKey = 'ui.softBannerDismissedAt';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final dismissedAt = _kvStore.getString(_dismissKey);
    final dismissedMillis = int.tryParse(dismissedAt ?? '');
    final within7Days =
        dismissedMillis != null &&
        DateTime.now().millisecondsSinceEpoch - dismissedMillis <
            7 * 24 * 60 * 60 * 1000;
    final check = await ServiceLocator.contentService.checkUpgrade();
    final sync = await ServiceLocator.syncService.getSyncStatus();
    if (!mounted) return;
    setState(() {
      _dismissed = within7Days;
      if (check.compatibility == 'soft' && !within7Days) {
        _state = 'soft';
      } else if (sync.state == 'offline') {
        _state = 'offline';
      } else {
        _state = 'ok';
      }
    });
  }

  void _dismissSoft() {
    _kvStore.setString(
      _dismissKey,
      DateTime.now().millisecondsSinceEpoch.toString(),
    );
    setState(() {
      _dismissed = true;
      _state = 'ok';
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_state == null || _state == 'ok' || _dismissed) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    if (_state == 'soft') {
      return Container(
        height: 36,
        color: AppColors.warningContainer(context),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Icon(
              Icons.system_update_outlined,
              size: 18,
              color: AppColors.warning(context),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('新内容可用', style: TextStyle(fontSize: 13)),
            ),
            TextButton(
              onPressed: () => showAppSnackBar(context, '演示模式：暂无可更新内容'),
              child: const Text('看更新'),
            ),
            IconButton(
              onPressed: _dismissSoft,
              icon: const Icon(Icons.close, size: 18),
              tooltip: '关闭',
            ),
          ],
        ),
      );
    }
    return Container(
      height: 36,
      color: scheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: 18,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('离线，进度联网后同步', style: TextStyle(fontSize: 13)),
          ),
          TextButton(
            onPressed: () => showAppSnackBar(context, '离线，进度联网后同步'),
            child: const Text('同步诊断'),
          ),
        ],
      ),
    );
  }
}
