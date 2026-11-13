/// 首页 tab 内容（问候区 + 继续学习横幅 + 套卷）。
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
import '../../widgets/set_row_card.dart';
import '../../widgets/set_row_tags.dart';
import '../../widgets/user_avatar.dart';

class HomeContentPage extends StatefulWidget {
  const HomeContentPage({super.key, required this.onSelectTab});

  final void Function(int index) onSelectTab;

  @override
  State<HomeContentPage> createState() => HomeContentPageState();
}

class HomeContentPageState extends State<HomeContentPage> {
  User? _user;
  StatsOverview? _overview;
  SyncStatus? _syncStatus;
  ContentVersion? _contentVersion;

  /// 首页精选题库的候选套卷（题库页另有 10 题套卷，不进精选）。
  static const List<int> _setDrawCounts = <int>[100, 200, 50];

  /// 首页最多展示的精选套卷数。
  static const int _featuredLimit = 3;

  /// 每套套卷的做题记录（完成度 / 正确率）。
  ///
  /// 这是接后端推荐的数据入口：现阶段数据源没有按套卷维度的记录（统计只有
  /// 按模块的 ModuleStat），所以留空——全部套卷按“未开始”处理，精选结果
  /// 就是默认顺序 100 / 200 / 50。后端接通后把真实记录填进这里即可，
  /// 排序规则与页面渲染都不用改。
  static const Map<int, _SetRecord> _practiceRecords = <int, _SetRecord>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// tab 切回时刷新（重拉用户 / 统计 / 同步状态）。
  Future<void> refresh() => _load();

  Future<void> _load() async {
    User? user;
    try {
      user = await ServiceLocator.authService.getCurrentUser();
    } catch (_) {
      user = null;
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
    if (!mounted) return;
    setState(() {
      _user = user;
      _overview = overview;
      _syncStatus = syncStatus;
      _contentVersion = contentVersion;
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

  /// 套卷行的 5 个模块小标签（与题库页共用 SetRowTags 3 列网格）。
  Widget _moduleTags() {
    return SetRowTags(labels: kModuleOrder.map(moduleLabel).toList());
  }

  /// 首页精选题库的套卷选取：按做题记录推荐，优先未完成的套卷，其次
  /// 正确率最低的，最多 [_featuredLimit] 套。记录缺失（如 Mock）的套卷
  /// 视为“未开始 + 无正确率”，保持 [_setDrawCounts] 的默认顺序。
  List<int> _featuredSets() {
    final ranked = List<int>.of(_setDrawCounts);
    ranked.sort((a, b) {
      final recordA = _practiceRecords[a];
      final recordB = _practiceRecords[b];
      final finishedA = recordA?.finished ?? false;
      final finishedB = recordB?.finished ?? false;
      // 未完成优先。
      if (finishedA != finishedB) return finishedA ? 1 : -1;
      // 正确率低的优先。
      final rateA = recordA?.correctRate ?? 0.0;
      final rateB = recordB?.correctRate ?? 0.0;
      if (rateA != rateB) return rateA.compareTo(rateB);
      // 都相同时保持默认顺序，避免每次渲染顺序抖动。
      return _setDrawCounts.indexOf(a).compareTo(_setDrawCounts.indexOf(b));
    });
    return ranked.take(_featuredLimit).toList();
  }

  /// 首页精选题库列表：每个精选套卷一行（全部首屏渲染，无懒加载）。
  Widget _buildFeaturedList() {
    final sets = _featuredSets();
    return Column(
      children: [
        for (var i = 0; i < sets.length; i++)
          Padding(
            padding: EdgeInsets.only(
              bottom: i == sets.length - 1 ? 0 : AppSpacing.cardGap,
            ),
            child: SetRowCard(
              title: '${sets[i]} 题套卷',
              subtitle: '${sets[i]} 题 · 5 个模块 · 含解析',
              trailing: _moduleTags(),
              onTap: () => _openSetDetail(sets[i]),
            ),
          ),
      ],
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
                bottom: AppSizes.homeBottomPad,
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _greetingText,
                        style: TextStyle(
                          fontSize: AppFontSizes.homeGreetingHi,
                          fontWeight: FontWeight.w700,
                          color: AppColors.title(context),
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        nickname,
                        style: TextStyle(
                          fontSize: AppFontSizes.homeGreetingName,
                          fontWeight: FontWeight.w800,
                          color: AppColors.title(context),
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
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.title(context),
                              ),
                            ),
                          ],
                        ),
                        style: TextStyle(
                          fontSize: AppFontSizes.pageSubtitle,
                          color: AppColors.label(context),
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
                  '精选题库',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                _buildFeaturedList(),
                if (_showSyncTip) ...[
                  const SizedBox(height: AppSpacing.md),
                  _SyncTipStrip(onTap: _openSyncSheet),
                ],
                const SizedBox(height: AppSpacing.md),
              ],
            ),
          ),
          Positioned(
            top: AppSizes.homeTopPad + AppSpacing.xs,
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

/// 单套套卷的做题记录（精选推荐的排序依据；字段由后端练习记录填充）。
class _SetRecord {
  const _SetRecord({required this.finished, required this.correctRate});

  /// 是否已完成整套。
  final bool finished;

  /// 整套正确率（0–1）。
  final double correctRate;
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
