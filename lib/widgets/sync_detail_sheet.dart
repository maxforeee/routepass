/// 同步诊断 sheet（F19：点首页底部同步条打开）。
///
/// 每次打开都重新读取真实状态（网络 + 登录态 + `/api/v1/sync/pull`），
/// 不会展示应用启动时的旧快照；打开期间监听网络变化，并提供刷新与手动同步。
/// 手动同步走 [SyncService.syncNow]（两向 MERGE，本地为空时只拉不推），
/// 这里只负责触发与展示结果，不自己拼请求。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_animations.dart';
import '../core/service_locator.dart';
import '../core/theme.dart';
import '../models/sync.dart';
import '../services/bank/bank_sync_service.dart';
import '../services/sync_mode_service.dart';

/// 打开同步诊断。
Future<void> showSyncDetailSheet(
  BuildContext context, {
  SyncService? syncService,
  SyncModeService? modeService,
}) {
  return showAppSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.of(context).size.height * 0.85,
    ),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppRadii.bottomSheet),
      ),
    ),
    builder: (_) =>
        SyncDetailSheet(syncService: syncService, modeService: modeService),
  );
}

class SyncDetailSheet extends StatefulWidget {
  const SyncDetailSheet({super.key, this.syncService, this.modeService});

  /// 测试可注入；生产从 [ServiceLocator] 取。
  final SyncService? syncService;
  final SyncModeService? modeService;

  @override
  State<SyncDetailSheet> createState() => _SyncDetailSheetState();
}

class _SyncDetailSheetState extends State<SyncDetailSheet> {
  SyncModeSnapshot? _snapshot;
  bool _loading = true;
  bool _syncing = false;
  String? _message;
  StreamSubscription<bool>? _connectivitySubscription;

  late final SyncModeService _modeService =
      widget.modeService ?? ServiceLocator.syncModeService;
  late final SyncService _syncService =
      widget.syncService ?? ServiceLocator.syncService;

  @override
  void initState() {
    super.initState();
    _load();
    _connectivitySubscription = _modeService.onChanged.listen((_) => _load());
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final snapshot = await _modeService.load();
    if (!mounted) return;
    setState(() {
      _snapshot = snapshot;
      _loading = false;
    });
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    await _load();
  }

  Future<void> _syncNow() async {
    setState(() {
      _syncing = true;
      _message = null;
    });
    ManualSyncResult result;
    try {
      result = await _syncService.syncNow();
    } catch (_) {
      result = const ManualSyncResult(
        ok: false,
        message: '同步失败，已保留本地数据',
        state: 'offline',
      );
    }
    if (!mounted) return;
    setState(() {
      _syncing = false;
      _message = result.message;
    });
    await _load();
  }

  String get _syncStateText {
    return switch (_snapshot?.status?.state) {
      'synced' => '已同步',
      'pending' => '有待同步操作',
      'offline' => '离线',
      'local_only' => '本地模式',
      null => '未知',
      _ => _snapshot!.status!.state,
    };
  }

  String get _serverText {
    final snapshot = _snapshot;
    if (snapshot == null) return '检测中';
    if (!snapshot.networkOnline) return '不可达（本机离线）';
    if (!snapshot.loggedIn) return '未登录';
    if (snapshot.serverReachable) return '可达';
    return snapshot.status?.state == 'offline' ? '不可达' : '同步接口不可用';
  }

  static String _formatMillis(int milliseconds) {
    final time = DateTime.fromMillisecondsSinceEpoch(milliseconds).toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }

  static String _formatIso(String? iso) {
    if (iso == null || iso.isEmpty) return '不可用';
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return '不可用';
    return _formatMillis(parsed.millisecondsSinceEpoch);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final snapshot = _snapshot;
    final lastSyncAt = snapshot?.status?.lastSyncAt;
    final canSync =
        snapshot != null &&
        snapshot.networkOnline &&
        snapshot.loggedIn &&
        !_syncing;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.xs,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('同步诊断', style: theme.textTheme.titleLarge),
                ),
                IconButton(
                  tooltip: '刷新',
                  onPressed: _loading ? null : _refresh,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            if (_loading) const LinearProgressIndicator(),
            const SizedBox(height: AppSpacing.sm),
            Text(
              snapshot?.modeLabel ?? '本地模式',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              snapshot == null
                  ? '正在读取同步状态…'
                  : snapshot.networkOnline
                  ? (snapshot.serverReachable
                        ? '已连接服务器，学习记录自动同步'
                        : '网络已连接，但同步接口尚不可用')
                  : '当前离线，显示最近一次同步状态',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _InfoRow(label: '当前模式', value: snapshot?.modeLabel ?? '本地模式'),
            _InfoRow(label: '同步状态', value: _syncStateText),
            _InfoRow(
              label: '待同步',
              value: '${snapshot?.status?.pendingCount ?? 0} 条',
            ),
            _InfoRow(
              label: '上次同步',
              value: lastSyncAt == null ? '从未同步' : _formatMillis(lastSyncAt),
            ),
            _InfoRow(
              label: '本机网络',
              value: snapshot == null
                  ? '检测中'
                  : (snapshot.networkOnline ? '已连接' : '未连接'),
            ),
            _InfoRow(label: '服务器', value: _serverText),
            _InfoRow(label: '服务器时间', value: _formatIso(snapshot?.serverTime)),
            if (_message != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _message!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            if (snapshot != null && !snapshot.loggedIn)
              Text(
                '未登录：本地模式，登录后才能同步学习记录。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else ...[
              FilledButton(
                onPressed: canSync ? _syncNow : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(
                    AppSizes.sheetButtonHeight,
                  ),
                ),
                child: _syncing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('立即同步'),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '同步为两向合并：本机没有记录时只从服务器拉取，不会用空数据覆盖服务器。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: AppSizes.syncLabelWidth,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
