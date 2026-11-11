/// 首页 tab 内容（T3 按 §22.4 重做为 12 方块瀑布流）。
library;

import 'package:flutter/material.dart';

import '../../core/app_snackbar.dart';
import '../../core/service_locator.dart';
import '../../core/theme.dart';
import '../../models/content.dart';
import '../../models/knowledge_point.dart';
import '../../models/practice.dart';
import '../../models/stats.dart';
import '../../models/sync.dart';
import '../../router/app_router.dart';
import '../../widgets/account_sheet.dart';

class HomeContentPage extends StatefulWidget {
  const HomeContentPage({super.key, required this.onSelectTab});

  final void Function(int index) onSelectTab;

  @override
  State<HomeContentPage> createState() => _HomeContentPageState();
}

class _HomeContentPageState extends State<HomeContentPage> {
  ContinueSession? _continueSession;
  int _wrongCount = 0;
  KnowledgePoint? _dailyPoint;
  List<Chapter> _chapters = const <Chapter>[];
  StatsOverview? _overview;
  SyncStatus? _syncStatus;
  ContentVersion? _contentVersion;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    ContinueSession? continueSession;
    try {
      continueSession =
          await ServiceLocator.practiceService.getContinueSession();
    } catch (_) {
      continueSession = null;
    }
    int wrongCount = 0;
    try {
      final wrongItems = await ServiceLocator.wrongService.getWrongBook();
      wrongCount = wrongItems.length;
    } catch (_) {
      wrongCount = 0;
    }
    KnowledgePoint? dailyPoint;
    try {
      dailyPoint = await ServiceLocator.knowledgeRepository.getDailyPoint();
    } catch (_) {
      dailyPoint = null;
    }
    List<Chapter> chapters = const <Chapter>[];
    try {
      chapters = await ServiceLocator.knowledgeRepository.getChapters();
    } catch (_) {
      chapters = const <Chapter>[];
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
      contentVersion =
          await ServiceLocator.contentService.getContentVersion();
    } catch (_) {
      contentVersion = null;
    }
    if (!mounted) return;
    setState(() {
      _continueSession = continueSession;
      _wrongCount = wrongCount;
      _dailyPoint = dailyPoint;
      _chapters = chapters;
      _overview = overview;
      _syncStatus = syncStatus;
      _contentVersion = contentVersion;
    });
  }

  bool get _showSyncCard {
    final sync = _syncStatus;
    if (sync == null) return false;
    return sync.pendingCount > 0 || sync.state == 'offline';
  }

  String get _todaySummary {
    final overview = _overview;
    if (overview == null || overview.todayAnswered == 0) {
      return '今天还没有完成任务';
    }
    return '今日已完成 ${overview.todayAnswered} 题 · 答对 ${overview.todayCorrect} 题';
  }

  String get _dateLabel {
    final now = DateTime.now();
    const weekdays = <String>['一', '二', '三', '四', '五', '六', '日'];
    return '${now.month}月${now.day}日 星期${weekdays[now.weekday - 1]}';
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '同步诊断',
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              _SyncRow(label: '状态', value: sync?.state ?? '未知'),
              _SyncRow(label: '待同步', value: '${sync?.pendingCount ?? 0} 条'),
              _SyncRow(label: '上次同步', value: lastSyncText),
              _SyncRow(label: '题库版本', value: content?.bank_version ?? '—'),
              _SyncRow(
                label: '知识库版本',
                value: content?.knowledge_version ?? '—',
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  showAppSnackBar(context, '演示环境，同步未接入');
                },
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final syncState = _syncStatus?.state ?? 'local_only';
    final continueSession = _continueSession;
    final dailyPoint = _dailyPoint;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '欢迎回来，Max',
              style: theme.textTheme.titleLarge?.copyWith(fontSize: 20),
            ),
            Text(
              _dateLabel,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          _SyncChip(state: syncState, onTap: _openSyncSheet),
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: '账户与同步',
            onPressed: () => showAccountSheet(context),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              _todaySummary,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            if (continueSession != null) ...[
              _ContinueHero(
                session: continueSession,
                onTap: () => Navigator.of(context).pushNamed(
                  AppRoutes.bankQuiz,
                  arguments: <String, Object?>{
                    'mode': continueSession.mode,
                    'questionId': continueSession.questionId,
                  },
                ),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    children: [
                      _HomeBlock(
                        height: 150,
                        onTap: () => _openQuiz('quick', 10),
                        child: const _BlockIconText(
                          icon: Icons.quiz_outlined,
                          title: '快速 10 题',
                          subtitle: '随机 10 题·约 5 分钟',
                        ),
                      ),
                      const SizedBox(height: 12),
                      _ExamBlock(
                        title: '200 题套卷',
                        onTap: () => _openQuiz('exam', 200),
                      ),
                      const SizedBox(height: 12),
                      _HomeBlock(
                        height: 140,
                        onTap: () => Navigator.of(context)
                            .pushNamed(AppRoutes.bankWrong),
                        child: _BlockTitleBadge(
                          title: '错题本',
                          badge: '$_wrongCount 道',
                        ),
                      ),
                      const SizedBox(height: 12),
                      _HomeBlock(
                        height: 140,
                        onTap: () => widget.onSelectTab(2),
                        child: _ChapterBlockContent(chapters: _chapters),
                      ),
                      const SizedBox(height: 12),
                      _HomeBlock(
                        height: 130,
                        onTap: () => widget.onSelectTab(3),
                        child: const _BlockIconText(
                          icon: Icons.swap_horiz,
                          title: 'IP/进制转换',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    children: [
                      _ExamBlock(
                        title: '100 题套卷',
                        onTap: () => _openQuiz('exam', 100),
                      ),
                      const SizedBox(height: 12),
                      _ExamBlock(
                        title: '50 题套卷',
                        height: 150,
                        onTap: () => _openQuiz('exam', 50),
                      ),
                      const SizedBox(height: 12),
                      _HomeBlock(
                        height: 160,
                        onTap: dailyPoint == null
                            ? null
                            : () => Navigator.of(context).pushNamed(
                                  AppRoutes.knowledgePoint,
                                  arguments: <String, Object?>{
                                    'kpId': dailyPoint.id,
                                    'returnTo': 'home',
                                  },
                                ),
                        child: _DailyPointContent(point: dailyPoint),
                      ),
                      const SizedBox(height: 12),
                      _HomeBlock(
                        height: 130,
                        onTap: () => Navigator.of(context)
                            .pushNamed(AppRoutes.toolboxSubnet),
                        child: const _BlockIconText(
                          icon: Icons.calculate_outlined,
                          title: '子网计算器',
                        ),
                      ),
                      const SizedBox(height: 12),
                      _HomeBlock(
                        height: 120,
                        onTap: () => Navigator.of(context)
                            .pushNamed(AppRoutes.bankStats),
                        child: _StatsContent(overview: _overview),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_showSyncCard) ...[
              const SizedBox(height: 12),
              _HomeBlock(
                height: 96,
                onTap: _openSyncSheet,
                child: _SyncCardContent(sync: _syncStatus!),
              ),
            ],
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

/// 方块通用容器：固定高、圆角 16、内边距 16，点按有涟漪。
class _HomeBlock extends StatelessWidget {
  const _HomeBlock({
    required this.height,
    required this.child,
    this.onTap,
  });

  final double height;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Card(
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// 图标 + 标题（+副标）型方块内容。
class _BlockIconText extends StatelessWidget {
  const _BlockIconText({required this.icon, required this.title, this.subtitle});

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 32, color: theme.colorScheme.primary),
        const SizedBox(height: 8),
        Text(title, style: theme.textTheme.titleMedium),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// 标题 + 数量徽标型方块内容（错题本）。
class _BlockTitleBadge extends StatelessWidget {
  const _BlockTitleBadge({required this.title, required this.badge});

  final String title;
  final String badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: theme.colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            badge,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onErrorContainer,
            ),
          ),
        ),
      ],
    );
  }
}

/// 套卷方块：标题 + 进度环（右）+ 覆盖模块小 chips。
class _ExamBlock extends StatelessWidget {
  const _ExamBlock({required this.title, required this.onTap, this.height = 170});

  final String title;
  final VoidCallback onTap;
  final double height;

  static const List<String> _modules = <String>[
    'VLAN',
    'OSPF',
    'ACL',
    'NAT',
    '子网',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _HomeBlock(
      height: height,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title, style: theme.textTheme.titleMedium),
              ),
              const SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(value: 0),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: _modules.map((m) {
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  m,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

/// 继续学习 hero：左文案 + 进度条，右“继续”按钮。
class _ContinueHero extends StatelessWidget {
  const _ContinueHero({required this.session, required this.onTap});

  final ContinueSession session;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = session.totalCount == 0
        ? 0.0
        : session.answeredCount / session.totalCount;
    return SizedBox(
      height: 120,
      child: Card(
        margin: EdgeInsets.zero,
        color: theme.colorScheme.primaryContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '继续学习',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '已完成 ${session.answeredCount}/${session.totalCount} 题',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(value: progress),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: onTap,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(72, 40),
                  ),
                  child: const Text('继续'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 章节速览方块内容。
class _ChapterBlockContent extends StatelessWidget {
  const _ChapterBlockContent({required this.chapters});

  final List<Chapter> chapters;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('章节速览', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (chapters.isEmpty)
          Text(
            '暂无章节',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else ...[
          Text(
            chapters.first.title,
            style: theme.textTheme.bodyMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            '共 ${chapters.length} 章',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// 今日知识点方块内容。
class _DailyPointContent extends StatelessWidget {
  const _DailyPointContent({required this.point});

  final KnowledgePoint? point;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = point;
    if (p == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('今日知识点', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            '暂无知识点',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          p.code,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          p.title,
          style: theme.textTheme.titleMedium,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),
        Text(
          p.summary,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

/// 学习统计方块内容。
class _StatsContent extends StatelessWidget {
  const _StatsContent({required this.overview});

  final StatsOverview? overview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ov = overview;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('学习统计', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          '连续 ${ov?.streakDays ?? 0} 天',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 4),
        Text(
          ov == null || ov.answeredTotal == 0
              ? '暂无数据'
              : '正确率 ${(ov.correctRate * 100).round()}%',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// 同步/版本卡内容（条件出现）。
class _SyncCardContent extends StatelessWidget {
  const _SyncCardContent({required this.sync});

  final SyncStatus sync;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('同步/版本', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          sync.pendingCount > 0
              ? '待同步 ${sync.pendingCount} 条'
              : '离线，未同步',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
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
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

/// H-03 同步 chip（高 28，圆角 14，icon 14 + label 12）。
class _SyncChip extends StatelessWidget {
  const _SyncChip({required this.state, required this.onTap});

  final String state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    late final IconData icon;
    late final String label;
    late final Color color;
    switch (state) {
      case 'synced':
        icon = Icons.check_circle_outline;
        label = '已同步';
        color = AppColors.success(context);
      case 'pending':
        icon = Icons.sync;
        label = '同步中';
        color = theme.colorScheme.primary;
      case 'offline':
        icon = Icons.cloud_off_outlined;
        label = '离线';
        color = theme.colorScheme.error;
      case 'local_only':
      default:
        icon = Icons.cloud_off_outlined;
        label = '本地模式';
        color = theme.colorScheme.onSurfaceVariant;
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(label, style: theme.textTheme.labelMedium?.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}
