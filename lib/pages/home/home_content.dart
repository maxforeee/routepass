/// 首页 tab 内容（问候区 + 继续学习横幅 + 套卷）。
library;

import 'package:flutter/material.dart';

import '../../core/app_snackbar.dart';
import '../../core/modules.dart';
import '../../core/service_locator.dart';
import '../../core/theme.dart';
import '../../models/content.dart';
import '../../models/daily_question.dart';
import '../../models/question.dart';
import '../../models/stats.dart';
import '../../models/sync.dart';
import '../../models/user.dart';
import '../../models/wrong_favorite.dart';
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

  /// 今天加入错题本的题目（条目 + 题目），供首页“错题本”预览卡展示。
  List<(WrongItem, Question)> _todayWrong = const <(WrongItem, Question)>[];

  /// 今天收藏的题目（条目 + 题目），供首页“收藏”预览卡展示。
  List<(Favorite, Question)> _todayFavorites = const <(Favorite, Question)>[];

  /// 今天的每日一练题目；取题失败时为 null（整张卡隐藏，不影响首页）。
  DailyQuestion? _dailyQuestion;

  /// 今天每日一练已选的选项 key；null = 今天还没答（未锁定）。
  String? _dailySelectedKey;

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
    List<(WrongItem, Question)> todayWrong = const <(WrongItem, Question)>[];
    try {
      final wrong = await ServiceLocator.wrongService.getWrongBook();
      todayWrong = await _resolveTodayWrong(wrong);
    } catch (_) {
      todayWrong = const <(WrongItem, Question)>[];
    }
    List<(Favorite, Question)> todayFavorites = const <(Favorite, Question)>[];
    try {
      final favorites = await ServiceLocator.favoriteService.getFavorites();
      todayFavorites = await _resolveTodayFavorites(favorites);
    } catch (_) {
      todayFavorites = const <(Favorite, Question)>[];
    }
    DailyQuestion? dailyQuestion;
    String? dailySelectedKey;
    try {
      final today = DateTime.now();
      dailyQuestion = await ServiceLocator.dailyPracticeService.questionForDate(
        today,
      );
      dailySelectedKey = await ServiceLocator.dailyPracticeService
          .answerForDate(today);
    } catch (_) {
      dailyQuestion = null;
      dailySelectedKey = null;
    }
    if (!mounted) return;
    setState(() {
      _user = user;
      _overview = overview;
      _syncStatus = syncStatus;
      _contentVersion = contentVersion;
      _todayWrong = todayWrong;
      _todayFavorites = todayFavorites;
      _dailyQuestion = dailyQuestion;
      _dailySelectedKey = dailySelectedKey;
    });
  }

  /// 每日一练作答：一天一次，已锁定后忽略点按（锁定态由 [_dailySelectedKey]
  /// 推导，不另存 bool，避免两处状态漂移）。
  Future<void> _answerDaily(String selectedKey) async {
    final question = _dailyQuestion;
    if (question == null || _dailySelectedKey != null) return;
    setState(() => _dailySelectedKey = selectedKey);
    try {
      await ServiceLocator.dailyPracticeService.saveAnswer(
        date: DateTime.now(),
        questionId: question.id,
        selectedKey: selectedKey,
      );
    } catch (_) {
      // 本地存储失败不影响当前页面的锁定展示；下次 _load 会按存储状态重算。
    }
  }

  /// 是否今天（按本地日历日、0 点分界，与预览卡“今日”口径一致）。
  static bool _isToday(int milliseconds) {
    final time = DateTime.fromMillisecondsSinceEpoch(milliseconds);
    final now = DateTime.now();
    return time.year == now.year &&
        time.month == now.month &&
        time.day == now.day;
  }

  /// 只留今天的错题；题目解析不到（如题库更新失效）的条目跳过，与错题本页一致。
  Future<List<(WrongItem, Question)>> _resolveTodayWrong(
    List<WrongItem> wrong,
  ) async {
    final list = <(WrongItem, Question)>[];
    for (final item in wrong) {
      if (!_isToday(item.last_wrong_at)) continue;
      final question = await ServiceLocator.questionRepository.getQuestionById(
        item.question_id,
      );
      if (question == null) continue;
      list.add((item, question));
    }
    return list;
  }

  /// 只留今天的收藏；题目解析不到的条目跳过，与收藏页一致。
  Future<List<(Favorite, Question)>> _resolveTodayFavorites(
    List<Favorite> favorites,
  ) async {
    final list = <(Favorite, Question)>[];
    for (final item in favorites) {
      if (!_isToday(item.created_at)) continue;
      final question = await ServiceLocator.questionRepository.getQuestionById(
        item.question_id,
      );
      if (question == null) continue;
      list.add((item, question));
    }
    return list;
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

  /// 首页底部今日预览：错题本在上、收藏在下，只列今天新增的题。
  Widget _buildPreviewCards() {
    return Column(
      children: [
        _PreviewCard(
          title: '错题本',
          countLabel: '今日新增 ${_todayWrong.length} 道',
          icon: Icons.menu_book_outlined,
          iconBackground: AppColors.wrongIconBackground,
          iconForeground: AppColors.wrongIconForeground,
          stems: [for (final (_, question) in _todayWrong) question.stem],
          onTap: () => Navigator.of(context).pushNamed(AppRoutes.bankWrong),
        ),
        const SizedBox(height: AppSpacing.cardGap),
        _PreviewCard(
          title: '收藏',
          countLabel: '今日收藏 ${_todayFavorites.length} 道',
          icon: Icons.star_border_rounded,
          iconBackground: AppColors.favoriteIconBackground,
          iconForeground: AppColors.favoriteIconForeground,
          stems: [for (final (_, question) in _todayFavorites) question.stem],
          onTap: () => Navigator.of(context).pushNamed(AppRoutes.bankFavorites),
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
                if (_dailyQuestion != null) ...[
                  _DailyPracticeCard(
                    question: _dailyQuestion!,
                    selectedKey: _dailySelectedKey,
                    onSelect: _answerDaily,
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
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
                Text(
                  '错题本 · 收藏',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                _buildPreviewCards(),
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

/// 首页今日预览卡：入口行（图标 + 左对齐标题 + 今日数量 + 箭头）+ 今日条目。
///
/// 卡片沿用 SetRowCard 的固定白底品牌样式（不随深浅色模式变化），所以卡内
/// 文字一律用固定深色 token；若改用 AppColors.title(context) 之类，深色模式
/// 会变成浅字压在纯白卡面上（v0.2.2 报过的白底白字）。
class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.title,
    required this.countLabel,
    required this.icon,
    required this.iconBackground,
    required this.iconForeground,
    required this.stems,
    required this.onTap,
  });

  /// 入口标题（错题本 / 收藏）。
  final String title;

  /// 今日数量文案（今日新增 N 道 / 今日收藏 N 道）。
  final String countLabel;

  final IconData icon;
  final Color iconBackground;
  final Color iconForeground;

  /// 今日条目的题干（一行截断）。
  final List<String> stems;

  /// 整卡点按：进完整页（预览项不单独点按）。
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.brandSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.card),
        side: const BorderSide(
          color: AppColors.brandBorder,
          width: AppSizes.borderWidth,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.previewCardPadV,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: AppSizes.previewIconSize,
                    height: AppSizes.previewIconSize,
                    decoration: BoxDecoration(
                      color: iconBackground,
                      borderRadius: BorderRadius.circular(AppRadii.previewIcon),
                    ),
                    child: Icon(
                      icon,
                      size: AppSizes.iconLarge,
                      color: iconForeground,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: AppFontSizes.entryTitle,
                        fontWeight: FontWeight.bold,
                        color: AppColors.brandTitle,
                      ),
                    ),
                  ),
                  Text(
                    countLabel,
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: AppFontSizes.previewCount,
                      color: AppColors.brandSecondaryText,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  const Icon(
                    Icons.chevron_right,
                    size: AppSizes.iconLarge,
                    color: AppColors.brandCaption,
                  ),
                ],
              ),
              if (stems.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.only(
                    top: AppSpacing.sm,
                    bottom: AppSpacing.xxs,
                  ),
                  child: SizedBox(
                    height: AppSizes.divider,
                    width: double.infinity,
                    child: ColoredBox(color: AppColors.brandBorder),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(
                    left: AppSizes.previewItemIndent,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final stem in stems)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.xxs,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              const Text(
                                '·',
                                style: TextStyle(
                                  fontSize: AppFontSizes.previewItem,
                                  color: AppColors.brandCaption,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.previewItemGap),
                              Expanded(
                                child: Text(
                                  stem,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: AppFontSizes.previewItem,
                                    height: 1.5,
                                    color: AppColors.previewItemText,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 每日一练选项条的视觉状态：未作答（白底）/ 正确（浅绿）/ 错误（浅红）。
enum _DailyOptionState { idle, correct, wrong }

/// 首页每日一练卡：标题“每日一练”骑在卡片上边框上，一道题 + 四条整条可点
/// 的选项；答完即锁定，显示“已锁定，明天刷新”。
///
/// 卡片固定白底品牌样式（与 _PreviewCard 一致），卡内文字与选项颜色一律用
/// 固定深色 token，不用 AppColors.title(context) 之类——深色模式下白卡配
/// 固定深字才可读。
class _DailyPracticeCard extends StatelessWidget {
  const _DailyPracticeCard({
    required this.question,
    required this.selectedKey,
    required this.onSelect,
  });

  final DailyQuestion question;

  /// 今天已选的选项 key；null = 未作答（未锁定）。
  final String? selectedKey;

  final ValueChanged<String> onSelect;

  bool get _locked => selectedKey != null;

  _DailyOptionState _stateFor(QuestionOption option) {
    if (!_locked) return _DailyOptionState.idle;
    if (option.key == question.correctKey) return _DailyOptionState.correct;
    if (option.key == selectedKey) return _DailyOptionState.wrong;
    return _DailyOptionState.idle;
  }

  @override
  Widget build(BuildContext context) {
    final options = question.options;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          key: const ValueKey('daily-practice-card'),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.dailyOptionPadH,
            AppSpacing.dailyCardPadTop,
            AppSpacing.dailyOptionPadH,
            AppSpacing.dailyOptionPadH,
          ),
          decoration: BoxDecoration(
            color: AppColors.brandSurface,
            borderRadius: BorderRadius.circular(AppRadii.card),
            border: Border.all(
              color: AppColors.brandBorder,
              width: AppSizes.borderWidth,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                question.stem,
                style: const TextStyle(
                  fontSize: AppFontSizes.dailyQuestion,
                  fontWeight: FontWeight.bold,
                  height: 1.6,
                  color: AppColors.brandTitle,
                ),
              ),
              const SizedBox(height: AppSpacing.dailyQuestionGap),
              for (var i = 0; i < options.length; i++)
                Padding(
                  padding: EdgeInsets.only(
                    bottom: i == options.length - 1
                        ? 0
                        : AppSpacing.dailyOptionGap,
                  ),
                  child: _DailyOptionStrip(
                    option: options[i],
                    state: _stateFor(options[i]),
                    onTap: _locked ? null : () => onSelect(options[i].key),
                  ),
                ),
              if (_locked) ...[
                const SizedBox(height: AppSpacing.sm),
                const Text(
                  '已锁定，明天刷新',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: AppFontSizes.dailyLockHint,
                    color: AppColors.brandSecondaryText,
                  ),
                ),
              ],
            ],
          ),
        ),
        Positioned(
          top: -AppSpacing.dailyTitleOverhang,
          left: AppSpacing.dailyTitleLeft,
          child: const ColoredBox(
            color: AppColors.brandSurface,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: AppSpacing.dailyTitlePadH,
              ),
              child: Text(
                '每日一练',
                style: TextStyle(
                  fontSize: AppFontSizes.dailyTitle,
                  fontWeight: FontWeight.w800,
                  color: AppColors.brandTitle,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 每日一练单条选项：整条长条可点按（字母圈 + 选项文字），颜色随状态整体变化。
class _DailyOptionStrip extends StatelessWidget {
  const _DailyOptionStrip({
    required this.option,
    required this.state,
    this.onTap,
  });

  final QuestionOption option;
  final _DailyOptionState state;

  /// 锁定时为 null（点按无效）。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (
      background,
      border,
      textColor,
      letterBackground,
      letterForeground,
    ) = switch (state) {
      _DailyOptionState.correct => (
        AppColors.dailyCorrectBackground,
        AppColors.successLight,
        AppColors.dailyCorrectText,
        AppColors.successLight,
        AppColors.brandOnPrimary,
      ),
      _DailyOptionState.wrong => (
        AppColors.wrongIconBackground,
        AppColors.wrongIconForeground,
        AppColors.dailyWrongText,
        AppColors.wrongIconForeground,
        AppColors.brandOnPrimary,
      ),
      _DailyOptionState.idle => (
        AppColors.brandSurface,
        AppColors.brandBorder,
        AppColors.brandTitle,
        AppColors.dailyLetterBackground,
        AppColors.dailyLetterText,
      ),
    };
    return Material(
      key: ValueKey('daily-option-${option.key}'),
      color: background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.dailyOption),
        side: BorderSide(color: border, width: AppSizes.borderWidth),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.dailyOptionPadH,
            vertical: AppSpacing.dailyOptionPadV,
          ),
          child: Row(
            children: [
              Container(
                width: AppSizes.dailyLetterSize,
                height: AppSizes.dailyLetterSize,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: letterBackground,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  option.key,
                  style: TextStyle(
                    fontSize: AppFontSizes.dailyLetter,
                    fontWeight: FontWeight.bold,
                    height: 1.2,
                    color: letterForeground,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  option.text,
                  style: TextStyle(
                    fontSize: AppFontSizes.dailyOption,
                    height: 1.5,
                    color: textColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
