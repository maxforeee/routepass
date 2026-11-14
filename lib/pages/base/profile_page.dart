import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_snackbar.dart';
import '../../core/config.dart';
import '../../core/service_locator.dart';
import '../../core/theme.dart';
import '../../models/auth.dart';
import '../../models/sync.dart';
import '../../models/user.dart';
import '../../router/app_router.dart';
import '../../services/bank/bank_sync_service.dart';
import '../../services/base/auth_service.dart';
import '../../widgets/animated_app_bar.dart';

/// 个人中心（头像进入）：设备 + 同步两个区块。
///
/// 设备区只展示登录时上送的这一台设备（后端没有设备列表端点）；同步区
/// 展示 [SyncService] 的真实状态，并在“立即同步”里执行两向 MERGE。
/// 两个区块都先读本地缓存，再后台刷新，断网时页面仍可用。
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, this.authService, this.syncService});

  /// 测试注入；生产为 null，走 ServiceLocator。
  final AuthService? authService;
  final SyncService? syncService;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late final AuthService _auth =
      widget.authService ?? ServiceLocator.authService;
  late final SyncService _sync =
      widget.syncService ?? ServiceLocator.syncService;

  User? _user;
  LocalDeviceInfo? _device;
  SyncStatus? _status;
  bool _loading = true;
  bool _syncing = false;
  String? _syncResult;

  @override
  void initState() {
    super.initState();
    _status = _sync.cachedStatus;
    _load();
  }

  Future<void> _load() async {
    final user = await _auth.getCurrentUser();
    final device = await _auth.currentDevice();
    SyncStatus? status;
    try {
      status = await _sync.getSyncStatus();
    } catch (_) {
      status = _sync.cachedStatus;
    }
    if (!mounted) return;
    setState(() {
      _user = user;
      _device = device;
      _status = status ?? _status;
      _loading = false;
    });
  }

  Future<void> _syncNow() async {
    setState(() => _syncing = true);
    ManualSyncResult result;
    try {
      result = await _sync.syncNow();
    } catch (_) {
      result = const ManualSyncResult(
        ok: false,
        message: '同步失败，请稍后重试',
        state: 'offline',
      );
    }
    SyncStatus? status = _sync.cachedStatus;
    if (status == null) {
      try {
        status = await _sync.getSyncStatus();
      } catch (_) {
        status = _status;
      }
    }
    if (!mounted) return;
    setState(() {
      _syncing = false;
      _status = status ?? _status;
      _syncResult = result.message;
    });
    showAppSnackBar(context, result.message);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AnimatedAppBar(
        title: '个人中心',
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading && _status == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSizes.homeBottomPad,
                ),
                children: [
                  _buildDeviceSection(context),
                  const SizedBox(height: AppSpacing.md),
                  _buildSyncSection(context),
                ],
              ),
      ),
    );
  }

  Widget _buildDeviceSection(BuildContext context) {
    final loggedIn = _user != null;
    final deviceId = _device?.deviceId;
    return _SectionCard(
      title: '设备',
      icon: Icons.smartphone_outlined,
      children: [
        _InfoRow(
          label: '设备标识',
          value: deviceId == null || deviceId.isEmpty
              ? '待接口'
              : _truncateId(deviceId),
          monospace: true,
          trailing: deviceId == null || deviceId.isEmpty
              ? null
              : IconButton(
                  tooltip: '复制设备标识',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _copyDeviceId(deviceId),
                  icon: const Icon(Icons.copy, size: AppSizes.iconSmall),
                ),
        ),
        _InfoRow(label: '设备型号', value: _device?.deviceModel ?? '待接口'),
        _InfoRow(
          label: '应用版本',
          value: _device?.appVersion ?? AppConfig.version,
          monospace: true,
        ),
        _InfoRow(label: '绑定账号', value: _user?.username ?? '未登录'),
        _InfoRow(
          label: '绑定状态',
          value: loggedIn ? '已绑定' : '未登录',
          valueColor: loggedIn
              ? AppColors.success(context)
              : AppColors.warning(context),
        ),
        if (!loggedIn) ...[
          const SizedBox(height: AppSpacing.sm),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pushNamed(AppRoutes.login),
            child: const Text('去登录'),
          ),
        ],
        const Divider(height: AppSpacing.lg),
        _InfoRow(label: '其他设备', value: '其他设备列表待接口'),
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xxs),
          child: Text(
            '后端尚未提供设备列表接口（GET /api/v1/auth/devices），暂不展示其他设备。',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: AppColors.cardCaption(context)),
          ),
        ),
      ],
    );
  }

  Widget _buildSyncSection(BuildContext context) {
    final status = _status;
    final loggedIn = _user != null;
    final pending = status?.pendingCount ?? 0;
    final state = status?.state ?? 'local_only';
    return _SectionCard(
      title: '同步',
      icon: Icons.sync,
      children: [
        Row(
          children: [
            _StateChip(state: state),
            const Spacer(),
            Text(
              '待同步 $pending 条',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        _InfoRow(label: '上次同步', value: _formatMillis(status?.lastSyncAt)),
        _InfoRow(
          label: '服务器时间',
          value: _formatServerTime(status?.serverTime),
          monospace: true,
        ),
        _InfoRow(
          label: '服务端水位',
          value: status?.watermark?.toString() ?? '—',
          monospace: true,
        ),
        const SizedBox(height: AppSpacing.sm),
        if (!loggedIn)
          Text(
            '未登录，无法同步账号数据。',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: AppColors.cardCaption(context)),
          ),
        if (_syncResult != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              '上次同步结果：$_syncResult',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        FilledButton.icon(
          onPressed: !loggedIn || _syncing ? null : _syncNow,
          icon: _syncing
              ? const SizedBox(
                  width: AppSizes.iconSmall,
                  height: AppSizes.iconSmall,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.sync, size: AppSizes.icon),
          label: Text(_syncing ? '同步中…' : '立即同步'),
        ),
        if (state == 'offline')
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              '当前网络不可达，展示的是本地缓存的同步状态。',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: AppColors.warning(context)),
            ),
          ),
      ],
    );
  }

  Future<void> _copyDeviceId(String deviceId) async {
    await Clipboard.setData(ClipboardData(text: deviceId));
    if (!mounted) return;
    showAppSnackBar(context, '设备标识已复制');
  }

  /// 只展示首 8 + 末 4，避免把完整 deviceId 铺在界面上。
  static String _truncateId(String id) {
    if (id.length <= 14) return id;
    return '${id.substring(0, 8)}…${id.substring(id.length - 4)}';
  }

  static String _formatMillis(int? ms) {
    if (ms == null) return '从未同步';
    final time = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }

  static String _formatServerTime(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return iso;
    return _formatMillis(parsed.millisecondsSinceEpoch);
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.cardSurface(context),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: AppSizes.icon,
                  color: AppColors.accent(context),
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.monospace = false,
    this.valueColor,
    this.trailing,
  });

  final String label;
  final String value;
  final bool monospace;
  final Color? valueColor;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).textTheme.bodyMedium;
    final valueStyle = (monospace ? monoTextStyle(context, fontSize: 14) : base)
        ?.copyWith(color: valueColor ?? AppColors.cardTitle(context));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        children: [
          SizedBox(
            width: AppSizes.syncLabelWidth,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: AppColors.cardCaption(context)),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: valueStyle,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _StateChip extends StatelessWidget {
  const _StateChip({required this.state});

  final String state;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (state) {
      'synced' => ('已同步', AppColors.success(context)),
      'pending' => ('待同步', AppColors.warning(context)),
      'offline' => ('离线', Theme.of(context).colorScheme.error),
      _ => ('本地模式', AppColors.cardCaption(context)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadii.syncChip),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
