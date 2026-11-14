/// 账户 Sheet（G-03，第 3 章 §22.2.2）。
///
/// 顶部圆角 24；高 ≤70% 屏；列表项高 56。仅首页头像或深链 `/account` 触发。
/// 内容：登录 / 注册（未登录时）/ 同步状态 / 设备列表 / 恢复码 / 登出 /
/// 清除本机数据。数据全部走 ServiceLocator 里的 Mock 服务。
///
/// “清除本机数据”在 Mock 下只清除本地 kv 的 4 个 UI 状态键
///（kb.expandedIds、toolbox.recent、home.continue、ui.lastTab），
/// 不删任何账号数据（后端未接，本来也没有）。
library;

import 'package:flutter/material.dart';

import '../core/app_snackbar.dart';
import '../core/config.dart';
import '../core/kv_store.dart';
import '../core/service_locator.dart';
import '../models/content.dart';
import '../models/sync.dart';
import '../models/user.dart';
import '../router/app_router.dart';

/// 从任何页面打开 G-03。调用方只传 context 即可。
Future<void> showAccountSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.of(context).size.height * 0.7,
    ),
    builder: (sheetContext) => const AccountSheet(),
  );
}

class AccountSheet extends StatefulWidget {
  const AccountSheet({super.key});

  @override
  State<AccountSheet> createState() => _AccountSheetState();
}

class _AccountSheetState extends State<AccountSheet> {
  User? _user;
  SyncStatus? _syncStatus;
  ContentVersion? _contentVersion;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = await ServiceLocator.authService.getCurrentUser();
    final sync = await ServiceLocator.syncService.getSyncStatus();
    final version = await ServiceLocator.contentService.getContentVersion();
    if (!mounted) return;
    setState(() {
      _user = user;
      _syncStatus = sync;
      _contentVersion = version;
      _loading = false;
    });
  }

  String _syncText() {
    return switch (_syncStatus?.state) {
      'synced' => '已同步',
      'pending' => '有 ${_syncStatus?.pendingCount ?? 0} 项待同步',
      'offline' => '离线',
      _ => '本地模式，未同步',
    };
  }

  Future<void> _showDevices() async {
    final devices = await ServiceLocator.authService.getDevices();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('设备列表'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final d in devices)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.smartphone_outlined),
                  title: Text(d.name),
                  subtitle: Text(d.is_current ? '当前设备' : '其他设备'),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showRecoveryCode() async {
    final hint = await ServiceLocator.authService.getRecoveryCodeHint();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('恢复码'),
          content: Text(hint ?? '未设置'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmClearLocalData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('清除本机数据'),
          content: const Text(
            '将清除本机保存的界面状态（展开态、最近使用、继续学习进度、上次停留的 tab），账号数据不受影响。确定清除吗？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('清除'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    final kv = ServiceLocator.kvStore;
    kv.remove(KvStore.keyKbExpandedIds);
    kv.remove(KvStore.keyToolboxRecent);
    kv.remove(KvStore.keyHomeContinue);
    kv.remove(KvStore.keyUiLastTab);
    if (!mounted) return;
    Navigator.of(context).pop();
    showAppSnackBar(context, '已清除本机数据');
  }

  Future<void> _logout() async {
    final navigator = Navigator.of(context);
    await ServiceLocator.authService.logout();
    if (!mounted) return;
    showAppSnackBar(context, '已登出');
    navigator.pop();
    // 登出后清空会话，直接回登录页（不保留已鉴权的壳层）。
    navigator.pushNamedAndRemoveUntil(AppRoutes.login, (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = _user;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: CircleAvatar(
                radius: 20,
                child: Icon(
                  user == null ? Icons.person_outline : Icons.person,
                  size: 22,
                ),
              ),
              title: Text(user?.nickname ?? '未登录'),
              subtitle: Text(user == null ? '登录后同步学习进度' : user.username),
            ),
            const Divider(height: 1),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              )
            else ...[
              if (user == null)
                _item(
                  context,
                  icon: Icons.login_outlined,
                  title: '登录',
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).pushNamed(AppRoutes.login);
                  },
                ),
              _item(
                context,
                icon: Icons.cloud_sync_outlined,
                title: '同步状态',
                subtitle: _syncText(),
                onTap: () => showAppSnackBar(context, '同步状态：${_syncText()}'),
              ),
              _item(
                context,
                icon: Icons.devices_outlined,
                title: '设备列表',
                onTap: _showDevices,
              ),
              _item(
                context,
                icon: Icons.key_outlined,
                title: '恢复码',
                onTap: _showRecoveryCode,
              ),
              _item(
                context,
                icon: Icons.info_outline,
                title: '内容版本',
                subtitle: _contentVersion == null
                    ? null
                    : '题库 ${_contentVersion!.bank_version} · 知识库 ${_contentVersion!.knowledge_version}',
              ),
              if (user != null)
                _item(
                  context,
                  icon: Icons.logout_outlined,
                  title: '登出',
                  onTap: _logout,
                ),
              _item(
                context,
                icon: Icons.delete_outline,
                title: '清除本机数据',
                onTap: _confirmClearLocalData,
              ),
            ],
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                AppConfig.versionLabel,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _item(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? subtitle,
    VoidCallback? onTap,
  }) {
    return SizedBox(
      height: 56,
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle),
        trailing: onTap == null
            ? null
            : const Icon(Icons.chevron_right, size: 20),
        onTap: onTap,
      ),
    );
  }
}
