/// 首页 tab 内容（问候区 + 继续学习横幅 + 工具方阵 + 套卷）。
library;

import 'package:flutter/material.dart';

import '../../core/app_snackbar.dart';
import '../../core/modules.dart';
import '../../core/service_locator.dart';
import '../../core/theme.dart';
import '../../models/content.dart';
import '../../models/stats.dart';
import '../../models/sync.dart';
import '../../models/user.dart';
import '../../router/app_router.dart';
import '../../widgets/account_sheet.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_progress_ring.dart';
import '../../widgets/module_tag.dart';
import '../../widgets/user_avatar.dart';
import '../toolbox/toolbox_tools.dart';

class HomeContentPage extends StatefulWidget {
  const HomeContentPage({super.key, required this.onSelectTab});

  final void Function(int index) onSelectTab;

  @override
  State<HomeContentPage> createState() => HomeContentPageState();
}

class HomeContentPageState extends State<HomeContentPage> {
  User? _user;
  int _wrongCount = 0;
  StatsOverview? _overview;
  SyncStatus? _syncStatus;
  ContentVersion? _contentVersion;
  List<ModuleStat> _modules = const <ModuleStat>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// tab 切回时刷新（重拉用户 / 错题 / 知识点 / 统计）。
  Future<void> refresh() => _load();

  Future<void> _load() async {
    User? user;
    try {
      user = await ServiceLocator.authService.getCurrentUser();
    } catch (_) {
      user = null;
    }
    int wrongCount = 0;
    try {
      final wrongItems = await ServiceLocator.wrongService.getWrongBook();
      wrongCount = wrongItems.length;
    } catch (_) {
      wrongCount = 0;
    }
    StatsOverview? overview;
    try {
      overview = await ServiceLocator.statsService.getOverview();
    } catch (_) {
      overview = null;
    }
    SyncStatus? syncStatus;
    try {
      syncStatus = await ServiceLocator.syncService.getSyncStatus();
    } catch (_) {
      syncStatus = null;
    }
    ContentVersion? contentVersion;
    try {
      contentVersion = await ServiceLocator.contentService.getContentVersion();
    } catch (_) {
      contentVersion = null;
    }
    List<ModuleStat> modules = const <ModuleStat>[];
    try {
      modules = await ServiceLocator.questionRepository.getModules();
    } catch (_) {
      modules = const <ModuleStat>[];
    }
    if (!mounted) return;
    setState(() {
      _user = user;
      _wrongCount = wrongCount;
      _overview = overview;
      _syncStatus = syncStatus;
      _contentVersion = contentVersion;
      _modules = modules;
    });
  }

  /// 时段问候：早上好 / 下午好 / 晚上好。
  String get _greetingText {
    final hour = DateTime.now().hour;
    if (hour < 12) return '早上好！';
    if (hour < 18) return '下午好！';
    return '晚上好！';
  }

  String get _todaySummary {
    final overview = _overview;
    if (overview == null || overview.todayAnswered == 0) {
      return '今天还没有完成任务';
    }
    return '今日已完成 ${overview.todayAnswered} 题 · 答对 ${overview.todayCorrect} 题';
  }

  /// 套卷进度：由各模块题量聚合得到（总题量 ≤ 0 时视为 0%）。
  double get _setProgress {
    var total = 0;
    var answered = 0;
    for (final m in _modules) {
      total += m.total;
      answered += m.answered;
    }
    if (total <= 0) return 0.0;
    return (answered / total).clamp(0.0, 1.0);
  }

  /// 本地模式时显示同步提示条（未连接服务器 / 未同步）。
  bool get _showSyncTip {
    final sync = _syncStatus;
    return sync == null || sync.state == 'local_only';
  }

  void _openSyncSheet() {
    final sync = _syncStatus;
    final content = _contentVersion;
    final lastSyncText = sync?.lastSyncAt == null
        ? '从未同步'
        : DateTime.fromMillisecondsSinceEpoch(sync!.lastSyncAt!)
              .toLocal()
              .toString();
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadii.bottomSheet),
        ),
      ),
      builder: (sheetContext) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('同步诊断', style: Theme.of(sheetContext).textTheme.titleLarge),
              const SizedBox(height: AppSpacing.md),
              _SyncRow(label: '状态', value: sync?.state ?? '未知'),
              _SyncRow(label: '待同步', value: '${sync?.pendingCount ?? 0} 条'),
              _SyncRow(label: '上次同步', value: lastSyncText),
              _SyncRow(label: '题库版本', value: content?.bank_version ?? '—'),
              _SyncRow(
                label: '知识库版本',
                value: content?.knowledge_version ?? '—',
              ),
              const SizedBox(height: AppSpacing.md),
              FilledButton(
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  showAppSnackBar(context, '演示环境，同步未接入');
                },
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(
                    AppSizes.sheetButtonHeight,
                  ),
                ),
                child: const Text('同步'),
              ),
            ],
          ),
        );
      },
    );
  }

  void _openQuiz(String mode, int drawCount) {
    Navigator.of(context).pushNamed(
      AppRoutes.bankQuiz,
      arguments: <String, Object?>{'mode': mode, 'drawCount': drawCount},
    );
  }

  void _openSetDetail(int drawCount) {
    Navigator.of(context).pushNamed(
      AppRoutes.bankSetDetail,
      arguments: <String, Object?>{'mode': 'exam', 'drawCount': drawCount},
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = _user;
    final nickname = user?.nickname ?? user?.username ?? '';
    return Scaffold(
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.only(
                top: AppSizes.homeTopPad,
                left: AppSpacing.md,
                right: AppSpacing.md,
                bottom: AppSpacing.md,
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _greetingText,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.brandTitle,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        nickname,
                        style: const TextStyle(
                          fontSize: AppFontSizes.homeGreetingName,
                          fontWeight: FontWeight.w800,
                          color: AppColors.brandTitle,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text.rich(
                        TextSpan(
                          text: '今日已完成题目数 ',
                          children: [
                            TextSpan(
                              text: '${_overview?.todayAnswered ?? 0}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.brandTitle,
                              ),
                            ),
                          ],
                        ),
                        style: const TextStyle(
                          fontSize: AppFontSizes.pageSubtitle,
                          color: AppColors.brandSecondaryText,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                _Banner(
                  summary: _todaySummary,
                  onStart: () => _openQuiz('quick', 10),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  '工具箱',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: AppColors.brandTitle,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: toolboxTools.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 1,
                    crossAxisSpacing: AppSpacing.sm,
                    mainAxisSpacing: AppSpacing.sm,
                  ),
                  itemBuilder: (context, index) =>
                      _ToolGridCard(tool: toolboxTools[index]),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          _IconCard(
                            icon: Icons.bolt,
                            iconColor: theme.colorScheme.primary,
                            title: '快速 10 题',
                            subtitle: '随机 10 题 · 约 5 分钟',
                            onTap: () => _openQuiz('quick', 10),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          _ExamSetCard(
                            count: 200,
                            progress: _setProgress,
                            onTap: () => _openSetDetail(200),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          _IconCard(
                            icon: Icons.menu_book_outlined,
                            iconColor: theme.colorScheme.error,
                            title: '错题本',
                            subtitle: _wrongCount == 0
                                ? '暂无错题'
                                : '$_wrongCount 道',
                            onTap: () =>
                                Navigator.of(context)
                                    .pushNamed(AppRoutes.bankWrong),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        children: [
                          _ExamSetCard(
                            count: 100,
                            progress: _setProgress,
                            onTap: () => _openSetDetail(100),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          _ExamSetCard(
                            count: 50,
                            progress: _setProgress,
                            onTap: () => _openSetDetail(50),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (_showSyncTip) ...[
                  const SizedBox(height: AppSpacing.md),
                  _SyncTipStrip(onTap: _openSyncSheet),
                ],
                const SizedBox(height: AppSpacing.md),
              ],
            ),
          ),
          Positioned(
            top: AppSpacing.sm,
            right: AppSpacing.md,
            child: UserAvatar(
              username: user?.username ?? '',
              onTap: () => showAccountSheet(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// 卡片通用容器：圆角 16、浅灰边框、轻微阴影，点按有涟漪；高度随内容自适应。
/// 浅蓝横幅（#DBEAFE）：左文案 + 右“开始”按钮（快速 10 题）。
class _Banner extends StatelessWidget {
  const _Banner({required this.summary, required this.onStart});

  final String summary;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  summary,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  '从快速 10 题开始，约 5 分钟',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          FilledButton(
            onPressed: onStart,
            style: FilledButton.styleFrom(
              minimumSize: const Size(
                AppSizes.bannerButtonWidth,
                AppSizes.bannerButtonHeight,
              ),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            ),
            child: const Text('开始'),
          ),
        ],
      ),
    );
  }
}

/// 浅蓝同步提示条（#DBEAFE）：云同步图标 + 两行文案，点按打开同步诊断 sheet。
class _SyncTipStrip extends StatelessWidget {
  const _SyncTipStrip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.card),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.cloud_sync,
              size: AppSizes.icon,
              color: theme.colorScheme.onPrimaryContainer,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '本地模式 · 未连接服务器',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    '学习记录保存在本机，点击查看同步诊断',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolGridCard extends StatelessWidget {
  const _ToolGridCard({required this.tool});

  final ToolboxTool tool;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AspectRatio(
      aspectRatio: 1,
      child: AppCard(
        onTap: () => Navigator.of(context).pushNamed(tool.route),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              tool.icon,
              size: AppSizes.toolGridIconSize,
              color: switch (tool.iconTone) {
                ToolIconTone.blue => AppColors.brandPrimary,
                ToolIconTone.green => AppColors.success(context),
                ToolIconTone.orange => AppColors.warning(context),
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              tool.name,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(
                color: AppColors.brandTitle,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 图标 + 标题 + 副标型卡片（快速 10 题 / 错题本）。
class _IconCard extends StatelessWidget {
  const _IconCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: AppSizes.iconXLarge, color: iconColor),
          const SizedBox(height: AppSpacing.xs),
          Text(title, style: _cardTitleStyle(theme)),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 套卷卡片（100/200/50 题）：进度环 + 列表图标 + 标题 + 时长 + 5 个模块小标签。
class _ExamSetCard extends StatelessWidget {
  const _ExamSetCard({
    required this.count,
    required this.progress,
    required this.onTap,
  });

  final int count;
  final double progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppProgressRing(value: progress),
              const Spacer(),
              Icon(
                Icons.list_alt_outlined,
                size: AppSizes.icon,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text('$count 题套卷', style: _cardTitleStyle(theme)),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            '$count 题 · 约 ${(count * 0.6).round()} 分钟',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xxs,
            runSpacing: AppSpacing.xxs,
            children: kModuleOrder
                .map((module) => ModuleTag(label: moduleLabel(module)))
                .toList(),
          ),
        ],
      ),
    );
  }
}

/// 卡片标题样式：约 15px 加粗、深色。
TextStyle _cardTitleStyle(ThemeData theme) {
  return theme.textTheme.titleSmall!.copyWith(fontWeight: FontWeight.bold);
}

/// 同步诊断 sheet 里的一行。
class _SyncRow extends StatelessWidget {
  const _SyncRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
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
