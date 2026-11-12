/// 首页 tab 内容（R3a：问候区 + #DBEAFE 横幅 + 10 张卡片瀑布流）。
library;

import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/app_snackbar.dart';
import '../../core/modules.dart';
import '../../core/service_locator.dart';
import '../../core/theme.dart';
import '../../models/content.dart';
import '../../models/knowledge_point.dart';
import '../../models/stats.dart';
import '../../models/sync.dart';
import '../../models/user.dart';
import '../../router/app_router.dart';
import '../../widgets/account_sheet.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_progress_ring.dart';
import '../../widgets/module_tag.dart';
import '../../widgets/user_avatar.dart';

class HomeContentPage extends StatefulWidget {
  const HomeContentPage({super.key, required this.onSelectTab});

  final void Function(int index) onSelectTab;

  @override
  State<HomeContentPage> createState() => _HomeContentPageState();
}

class _HomeContentPageState extends State<HomeContentPage> {
  User? _user;
  int _wrongCount = 0;
  KnowledgePoint? _dailyPoint;
  List<Chapter> _chapters = const <Chapter>[];
  StatsOverview? _overview;
  SyncStatus? _syncStatus;
  ContentVersion? _contentVersion;
  List<ModuleStat> _modules = const <ModuleStat>[];
  List<String> _pointIds = const <String>[];
  List<String> _masteredIds = const <String>[];

  /// 掌握态的本地 kv 键（与知识库页共用同一派生键 `kb.masteredIds`）。
  static const String _keyMasteredIds = 'kb.masteredIds';

  @override
  void initState() {
    super.initState();
    _load();
  }

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
    final pointIds = <String>[];
    for (final chapter in chapters) {
      var sections = const <Section>[];
      try {
        sections = await ServiceLocator.knowledgeRepository.getSections(
          chapter.id,
        );
      } catch (_) {
        sections = const <Section>[];
      }
      for (final section in sections) {
        try {
          final points = await ServiceLocator.knowledgeRepository
              .getPointsBySection(section.id);
          pointIds.addAll(points.map((p) => p.id));
        } catch (_) {}
      }
    }
    final masteredIds = _readIdList(_keyMasteredIds);
    if (!mounted) return;
    setState(() {
      _user = user;
      _wrongCount = wrongCount;
      _dailyPoint = dailyPoint;
      _chapters = chapters;
      _overview = overview;
      _syncStatus = syncStatus;
      _contentVersion = contentVersion;
      _modules = modules;
      _pointIds = pointIds;
      _masteredIds = masteredIds;
    });
  }

  List<String> _readIdList(String key) {
    final raw = ServiceLocator.kvStore.getString(key);
    if (raw == null || raw.isEmpty) return <String>[];
    try {
      return (jsonDecode(raw) as List<dynamic>).cast<String>();
    } catch (_) {
      return <String>[];
    }
  }

  /// 时段问候：早上好 / 下午好 / 晚上好 + 当前登录用户昵称。
  String get _greetingText {
    final hour = DateTime.now().hour;
    final String prefix;
    if (hour < 12) {
      prefix = '早上好';
    } else if (hour < 18) {
      prefix = '下午好';
    } else {
      prefix = '晚上好';
    }
    final name = _user?.nickname ?? _user?.username ?? '';
    return name.isEmpty ? prefix : '$prefix，$name';
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
    return '${now.month}月${now.day}日星期${weekdays[now.weekday - 1]}';
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

  /// 章节卡标题：无章节回退“暂无章节”，有章节时去掉展示用的“样例章节：”前缀。
  String get _chapterCardTitle {
    if (_chapters.isEmpty) return '暂无章节';
    const prefix = '样例章节：';
    final title = _chapters.first.title;
    return title.startsWith(prefix) ? title.substring(prefix.length) : title;
  }

  /// 已掌握知识点数 = 掌握 id 与全部知识点 id 的交集。
  int get _masteredCount => _masteredIds.where(_pointIds.contains).length;

  /// 知识点总数。
  int get _totalPoints => _pointIds.length;

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
    final syncState = _syncStatus?.state ?? 'local_only';
    final dailyPoint = _dailyPoint;
    final user = _user;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _greetingText,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
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
          const SizedBox(width: AppSpacing.xs),
          UserAvatar(
            username: user?.username ?? '',
            onTap: () => showAccountSheet(context),
          ),
          const SizedBox(width: AppSpacing.md),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            _Banner(
              summary: _todaySummary,
              onStart: () => _openQuiz('quick', 10),
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
                        subtitle: _wrongCount == 0 ? '暂无错题' : '$_wrongCount 道',
                        onTap: () =>
                            Navigator.of(context)
                                .pushNamed(AppRoutes.bankWrong),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _ChapterCard(
                        title: _chapterCardTitle,
                        masteredCount: _masteredCount,
                        totalPoints: _totalPoints,
                        hasChapter: _chapters.isNotEmpty,
                        onTap: () => widget.onSelectTab(2),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _IconCard(
                        icon: Icons.swap_horiz,
                        iconColor: theme.colorScheme.primary,
                        title: 'IP/进制转换',
                        subtitle: '二/十/十六进制',
                        onTap: () =>
                            Navigator.of(context)
                                .pushNamed(AppRoutes.toolboxIpConvert),
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
                      const SizedBox(height: AppSpacing.md),
                      _DailyPointCard(
                        point: dailyPoint,
                        onTap: dailyPoint == null
                            ? null
                            : () => Navigator.of(context).pushNamed(
                                AppRoutes.knowledgePoint,
                                arguments: <String, Object?>{
                                  'kpId': dailyPoint.id,
                                  'returnTo': 'home',
                                },
                              ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _IconCard(
                        icon: Icons.calculate_outlined,
                        iconColor: theme.colorScheme.primary,
                        title: '子网计算器',
                        subtitle: '网络 / 广播 / 主机数',
                        onTap: () =>
                            Navigator.of(context)
                                .pushNamed(AppRoutes.toolboxSubnet),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _StatsCard(
                        overview: _overview,
                        onTap: () =>
                            Navigator.of(context)
                                .pushNamed(AppRoutes.bankStats),
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

/// 图标 + 标题 + 副标型卡片（快速 10 题 / 错题本 / 子网计算器 / IP 转换）。
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

/// 章节速览卡片：图标 + 小标题 + 章节名（粗）+ 掌握进度。
class _ChapterCard extends StatelessWidget {
  const _ChapterCard({
    required this.title,
    required this.masteredCount,
    required this.totalPoints,
    required this.hasChapter,
    required this.onTap,
  });

  final String title;
  final int masteredCount;
  final int totalPoints;
  final bool hasChapter;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = hasChapter ? '已掌握 $masteredCount/$totalPoints' : null;
    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SmallHeading(
            icon: Icons.layers_outlined,
            iconColor: theme.colorScheme.primary,
            text: '章节速览',
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(title, style: _cardTitleStyle(theme)),
          if (subtitle != null) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 今日知识点卡片：橙色星标 + 小标题 + 完整正文（不截断）。
class _DailyPointCard extends StatelessWidget {
  const _DailyPointCard({required this.point, this.onTap});

  final KnowledgePoint? point;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = point;
    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SmallHeading(
            icon: Icons.star,
            iconColor: AppColors.warning(context),
            text: '今日知识点',
          ),
          const SizedBox(height: AppSpacing.xs),
          if (p == null)
            Text(
              '暂无知识点',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else ...[
            Text(
              '${p.code} · ${p.topic}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              p.title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              p.summary,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 学习统计卡片：小标题 + 三个数字并排（空值如实展示）。
class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.overview, required this.onTap});

  final StatsOverview? overview;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ov = overview;
    final correctRate = ov == null || ov.answeredTotal == 0
        ? '–'
        : '${(ov.correctRate * 100).round()}%';
    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SmallHeading(
            icon: Icons.insert_chart_outlined,
            iconColor: theme.colorScheme.primary,
            text: '学习统计',
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Expanded(
                child: _StatValue(
                  value: '${ov?.streakDays ?? 0}',
                  label: '连续天数',
                ),
              ),
              Expanded(
                child: _StatValue(value: correctRate, label: '正确率'),
              ),
              Expanded(
                child: _StatValue(
                  value: '${ov?.answeredTotal ?? 0}',
                  label: '累计答题',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 小标题（章节速览 / 今日知识点 / 学习统计 上方的小字标题）。
class _SmallHeading extends StatelessWidget {
  const _SmallHeading({
    required this.icon,
    required this.iconColor,
    required this.text,
  });

  final IconData icon;
  final Color iconColor;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: AppSizes.icon, color: iconColor),
        const SizedBox(width: AppSpacing.xxs),
        Text(
          text,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// 统计卡里的单个数值 + 标签。
class _StatValue extends StatelessWidget {
  const _StatValue({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
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
      borderRadius: BorderRadius.circular(AppRadii.syncChip),
      child: Container(
        height: AppSizes.syncChipHeight,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(AppRadii.syncChip),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: AppSpacing.xxs),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}
