/// 首页 tab 内容（问候区 + 每日一练 + 错题本/收藏方块 + 同步提示条）。
library;

/// F19：画笔已搬到 `widgets/daily_card_border_painter.dart`，这里 re-export
/// 保持旧 import 路径可用（home_test 等直接引用本文件）。
export '../../widgets/daily_card_border_painter.dart'
    show DailyCardBorderPainter;

import 'package:flutter/material.dart';

import '../../core/app_snackbar.dart';
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
import '../../widgets/daily_card_border_painter.dart';
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

  /// 今天加入错题本的题目数，供首页“错题本”方块展示。
  int _todayWrongCount = 0;

  /// 今天收藏的题目数，供首页“收藏”方块展示。
  int _todayFavoriteCount = 0;

  /// 今天的每日一练题目；取题失败时为 null（整张卡隐藏，不影响首页）。
  DailyQuestion? _dailyQuestion;

  /// 今天每日一练已选的选项 key；null = 今天还没答（未锁定）。
  String? _dailySelectedKey;

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
    var todayWrongCount = 0;
    try {
      final wrong = await ServiceLocator.wrongService.getWrongBook();
      todayWrongCount = await _countTodayWrong(wrong);
    } catch (_) {
      todayWrongCount = 0;
    }
    var todayFavoriteCount = 0;
    try {
      final favorites = await ServiceLocator.favoriteService.getFavorites();
      todayFavoriteCount = await _countTodayFavorites(favorites);
    } catch (_) {
      todayFavoriteCount = 0;
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
      _todayWrongCount = todayWrongCount;
      _todayFavoriteCount = todayFavoriteCount;
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

  /// 是否今天（按本地日历日、0 点分界，与方块“今日”口径一致）。
  static bool _isToday(int milliseconds) {
    final time = DateTime.fromMillisecondsSinceEpoch(milliseconds);
    final now = DateTime.now();
    return time.year == now.year &&
        time.month == now.month &&
        time.day == now.day;
  }

  /// 只数今天的错题；题目解析不到（如题库更新失效）的条目跳过，与错题本页一致。
  Future<int> _countTodayWrong(List<WrongItem> wrong) async {
    var count = 0;
    for (final item in wrong) {
      if (!_isToday(item.last_wrong_at)) continue;
      final question = await ServiceLocator.questionRepository.getQuestionById(
        item.question_id,
      );
      if (question == null) continue;
      count++;
    }
    return count;
  }

  /// 只数今天的收藏；题目解析不到的条目跳过，与收藏页一致。
  Future<int> _countTodayFavorites(List<Favorite> favorites) async {
    var count = 0;
    for (final item in favorites) {
      if (!_isToday(item.created_at)) continue;
      final question = await ServiceLocator.questionRepository.getQuestionById(
        item.question_id,
      );
      if (question == null) continue;
      count++;
    }
    return count;
  }

  /// 时段问候：早上好 / 下午好 / 晚上好。
  String get _greetingText {
    final hour = DateTime.now().hour;
    if (hour < 12) return '早上好！';
    if (hour < 18) return '下午好！';
    return '晚上好！';
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

  /// 首页错题本 / 收藏入口：两个并排的正方形方块，只放图标 + 标题 + 今日数量。
  ///
  /// 标题骑在方块上边框上（与每日一练同一套 fieldset legend 语言），向上探出
  /// overhang，所以在方块行内部先补偿这段高度，组件之间的间距仍是统一的 md。
  Widget _buildSquareTiles() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: AppSpacing.dailyTitleOverhang),
        Row(
          children: [
            Expanded(
              child: _SquareTile(
                key: const ValueKey('home-tile-wrong'),
                title: '错题本',
                countLabel: '今日新增 $_todayWrongCount 道',
                icon: Icons.menu_book_outlined,
                iconBackground: AppColors.wrongIconBackground(context),
                iconForeground: AppColors.wrongIconForeground(context),
                onTap: () =>
                    Navigator.of(context).pushNamed(AppRoutes.bankWrong),
              ),
            ),
            const SizedBox(width: AppSpacing.cardGap),
            Expanded(
              child: _SquareTile(
                key: const ValueKey('home-tile-favorites'),
                title: '收藏',
                countLabel: '今日收藏 $_todayFavoriteCount 道',
                icon: Icons.star_border_rounded,
                iconBackground: AppColors.favoriteIconBackground(context),
                iconForeground: AppColors.favoriteIconForeground(context),
                onTap: () =>
                    Navigator.of(context).pushNamed(AppRoutes.bankFavorites),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 问候区显示的名字：优先昵称，其次用户名；未登录时用中性占位，
  /// 不再留空（v0.2.4 真机反馈：昵称为空导致问候语下方一片空白）。
  String _displayName(User? user) {
    final nickname = user?.nickname.trim() ?? '';
    if (nickname.isNotEmpty) return nickname;
    final username = user?.username.trim() ?? '';
    if (username.isNotEmpty) return username;
    return '同学';
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    final nickname = _displayName(user);
    const sectionGap = AppSpacing.md;
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        // 内容顶到屏幕最上沿（外壳 / MaterialApp 都没有 SafeArea），必须让出
        // 系统状态栏高度，否则问候语会被状态栏压住（v0.2.4 真机反馈）。
        // 与题库页一致：SafeArea 让出系统顶部内边距，md 内容内边距叠在它之下。
        child: SafeArea(
          top: true,
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.only(
              top: AppSpacing.md,
              left: AppSpacing.md,
              right: AppSpacing.md,
              bottom: AppSizes.homeBottomPad,
            ),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
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
                  const SizedBox(width: AppSpacing.md),
                  // 头像随页面内容滚动（不再钉在屏幕上）。
                  UserAvatar(
                    username: user?.username ?? '',
                    onTap: () => showAccountSheet(context),
                  ),
                ],
              ),
              const SizedBox(height: sectionGap),
              // 问候区（含头像）保持 md 页边距；下面的内容每侧再内缩
              // contentInset，离屏幕边 md + contentInset。
              if (_dailyQuestion != null) ...[
                // 标题骑在上边框上、向上探出 overhang，补偿后再留统一间距，
                // 让问候区到标题的视觉间距与其他组件一致。
                const SizedBox(height: AppSpacing.dailyTitleOverhang),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.contentInset,
                  ),
                  child: _DailyPracticeCard(
                    question: _dailyQuestion!,
                    selectedKey: _dailySelectedKey,
                    onSelect: _answerDaily,
                  ),
                ),
                const SizedBox(height: sectionGap),
              ],
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.contentInset,
                ),
                child: _buildSquareTiles(),
              ),
              if (_showSyncTip) ...[
                const SizedBox(height: sectionGap),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.contentInset,
                  ),
                  child: _SyncTipStrip(onTap: _openSyncSheet),
                ),
              ],
              const SizedBox(height: sectionGap),
            ],
          ),
        ),
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

/// 首页错题本 / 收藏方块：正方形入口，图标 + 今日数量居中，标题骑在上边框上。
///
/// 与每日一练同一套设计语言：卡面透明，圆角边框由 [DailyCardBorderPainter]
/// 绘制并在标题处留出真实缺口；边框与文字颜色全部跟随当前深浅色模式。
class _SquareTile extends StatelessWidget {
  const _SquareTile({
    super.key,
    required this.title,
    required this.countLabel,
    required this.icon,
    required this.iconBackground,
    required this.iconForeground,
    required this.onTap,
  });

  /// 入口标题（错题本 / 收藏），骑在方块上边框的缺口里。
  final String title;

  /// 今日数量文案（今日新增 N 道 / 今日收藏 N 道）。
  final String countLabel;

  final IconData icon;
  final Color iconBackground;
  final Color iconForeground;

  /// 整块点按：进完整页（方块内不列今日条目）。
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final titleStyle = TextStyle(
      fontSize: AppFontSizes.dailyTitle,
      fontWeight: FontWeight.w800,
      color: AppColors.cardTitle(context),
    );
    // 量出标题宽度，供边框在标题处留缺口（与每日一练同一算法）。
    final painter = TextPainter(
      text: TextSpan(text: title, style: titleStyle),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final gapStart = AppSpacing.dailyTitleLeft;
    final gapEnd = gapStart + painter.width + AppSpacing.dailyTitlePadH * 2;
    return AspectRatio(
      aspectRatio: 1,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: DailyCardBorderPainter(
                color: AppColors.cardBorder(context),
                radius: AppRadii.card,
                gapStart: gapStart,
                gapEnd: gapEnd,
              ),
            ),
          ),
          Positioned.fill(
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(AppRadii.card),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: AppSizes.previewIconSize,
                      height: AppSizes.previewIconSize,
                      decoration: BoxDecoration(
                        color: iconBackground,
                        borderRadius: BorderRadius.circular(
                          AppRadii.previewIcon,
                        ),
                      ),
                      child: Icon(
                        icon,
                        size: AppSizes.iconLarge,
                        color: iconForeground,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      countLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppFontSizes.previewCount,
                        color: AppColors.cardSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: -AppSpacing.dailyTitleOverhang,
            left: gapStart,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.dailyTitlePadH,
              ),
              child: Text(title, style: titleStyle),
            ),
          ),
        ],
      ),
    );
  }
}

/// 每日一练选项条的视觉状态：未作答（白底）/ 正确（浅绿）/ 错误（浅红）。
enum _DailyOptionState { idle, correct, wrong }

/// 首页每日一练卡：标题“每日一练”骑在卡片上边框上，一道题 + 四条整条可点
/// 的选项；答完即锁定，显示“已锁定，明天刷新”。
///
/// 卡片本身透明（无填充），上边框在标题处留出真实缺口；卡内文字与选项
/// 颜色全部跟随当前深浅色模式。
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

  /// 量出标题文字宽度，供边框在标题处留缺口（含左右内边距）。
  double _measureTitle(BuildContext context, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: '每日一练', style: style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    return painter.width;
  }

  @override
  Widget build(BuildContext context) {
    final options = question.options;
    final titleStyle = TextStyle(
      fontSize: AppFontSizes.dailyTitle,
      fontWeight: FontWeight.w800,
      color: AppColors.cardTitle(context),
    );
    final gapStart = AppSpacing.dailyTitleLeft;
    final gapEnd =
        gapStart +
        _measureTitle(context, titleStyle) +
        AppSpacing.dailyTitlePadH * 2;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: CustomPaint(
            key: const ValueKey('daily-card-border'),
            painter: DailyCardBorderPainter(
              color: AppColors.cardBorder(context),
              radius: AppRadii.card,
              gapStart: gapStart,
              gapEnd: gapEnd,
            ),
          ),
        ),
        Container(
          key: const ValueKey('daily-practice-card'),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.dailyOptionPadH,
            AppSpacing.dailyCardPadTop,
            AppSpacing.dailyOptionPadH,
            AppSpacing.dailyOptionPadH,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                question.stem,
                style: TextStyle(
                  fontSize: AppFontSizes.dailyQuestion,
                  fontWeight: FontWeight.bold,
                  height: 1.6,
                  color: AppColors.cardTitle(context),
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
                Text(
                  '已锁定，明天刷新',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: AppFontSizes.dailyLockHint,
                    color: AppColors.cardSecondary(context),
                  ),
                ),
              ],
            ],
          ),
        ),
        Positioned(
          top: -AppSpacing.dailyTitleOverhang,
          left: gapStart,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.dailyTitlePadH,
            ),
            child: Text('每日一练', style: titleStyle),
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
    final scheme = Theme.of(context).colorScheme;
    final (
      background,
      border,
      textColor,
      letterBackground,
      letterForeground,
    ) = switch (state) {
      _DailyOptionState.correct => (
        AppColors.dailyCorrectBackground(context),
        AppColors.success(context),
        AppColors.dailyCorrectText(context),
        AppColors.success(context),
        scheme.onPrimary,
      ),
      _DailyOptionState.wrong => (
        AppColors.wrongIconBackground(context),
        AppColors.wrongIconForeground(context),
        AppColors.dailyWrongText(context),
        AppColors.wrongIconForeground(context),
        scheme.onError,
      ),
      _DailyOptionState.idle => (
        AppColors.dailyOptionIdleBackground(context),
        AppColors.cardBorder(context),
        AppColors.cardTitle(context),
        AppColors.dailyLetterBackground(context),
        AppColors.dailyLetterText(context),
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
