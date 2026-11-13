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
import '../../widgets/module_tag.dart';
import '../../widgets/set_row_card.dart';
import '../../widgets/user_avatar.dart';

class HomeContentPage extends StatefulWidget {
  const HomeContentPage({super.key, required this.onSelectTab});

  final void Function(int index) onSelectTab;

  @override
  State<HomeContentPage> createState() => HomeContentPageState();
}

class HomeContentPageState extends State<HomeContentPage> {
  User? _user;
  int _wrongCount = 0;
  int _favoriteCount = 0;
  StatsOverview? _overview;
  SyncStatus? _syncStatus;
  ContentVersion? _contentVersion;

  /// 题库区懒加载：初始 3 行，滚到底部附近再补 3（最多 5）。
  static const int _bankTotal = 5;
  static const int _bankInitial = 3;
  static const int _bankStep = 3;
  int _visibleBankCount = _bankInitial;

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// 滚到距底部 200px 内时补加载题库行（本地懒渲染，非网络请求）。
  void _onScroll() {
    final controller = _scrollController;
    if (!controller.hasClients) return;
    if (controller.position.maxScrollExtent - controller.position.pixels >
        200) {
      return;
    }
    if (_visibleBankCount >= _bankTotal) return;
    setState(() {
      final next = _visibleBankCount + _bankStep;
      _visibleBankCount = next >= _bankTotal ? _bankTotal : next;
    });
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
    int favoriteCount = 0;
    try {
      final favoriteIds = await ServiceLocator.favoriteService.getFavoriteIds();
      favoriteCount = favoriteIds.length;
    } catch (_) {
      favoriteCount = 0;
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
      _wrongCount = wrongCount;
      _favoriteCount = favoriteCount;
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

  /// 套卷行的 5 个模块小标签（与题库页共用 ModuleTag）。
  Widget _moduleTags() {
    return Wrap(
      spacing: AppSpacing.xxs,
      runSpacing: AppSpacing.xxs,
      children: kModuleOrder
          .map((module) => ModuleTag(label: moduleLabel(module)))
          .toList(),
    );
  }

  /// 首页题库区：100 / 200 / 50 套卷 + 错题本 + 收藏，全部复用 SetRowCard。
  List<Widget> _bankItems(ThemeData theme) {
    return [
      SetRowCard(
        title: '100 题套卷',
        subtitle: '100 题 · 5 个模块 · 含解析',
        trailing: _moduleTags(),
        onTap: () => _openSetDetail(100),
      ),
      SetRowCard(
        title: '200 题套卷',
        subtitle: '200 题 · 5 个模块 · 含解析',
        trailing: _moduleTags(),
        onTap: () => _openSetDetail(200),
      ),
      SetRowCard(
        title: '50 题套卷',
        subtitle: '50 题 · 5 个模块 · 含解析',
        trailing: _moduleTags(),
        onTap: () => _openSetDetail(50),
      ),
      SetRowCard(
        leading: Icon(
          Icons.menu_book_outlined,
          color: theme.colorScheme.error,
          size: AppSizes.icon,
        ),
        title: '错题本',
        subtitle: _wrongCount == 0
            ? '暂无错题 · 做错的题自动收录'
            : '$_wrongCount 道 · 做错的题自动收录',
        trailing: const Icon(
          Icons.chevron_right,
          color: AppColors.brandCaption,
        ),
        onTap: () => Navigator.of(context).pushNamed(AppRoutes.bankWrong),
      ),
      SetRowCard(
        leading: Icon(
          Icons.star,
          color: AppColors.warning(context),
          size: AppSizes.icon,
        ),
        title: '收藏',
        subtitle: '$_favoriteCount 道已收藏',
        trailing: const Icon(
          Icons.chevron_right,
          color: AppColors.brandCaption,
        ),
        onTap: () => Navigator.of(context).pushNamed(AppRoutes.bankFavorites),
      ),
    ];
  }

  /// 题库区懒加载列表（只渲染前 _visibleBankCount 行，不嵌套滚动）。
  Widget _buildBankList(ThemeData theme) {
    final items = _bankItems(theme).take(_visibleBankCount).toList();
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      itemBuilder: (context, index) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: index == items.length - 1 ? 0 : AppSpacing.cardGap,
          ),
          child: items[index],
        );
      },
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
              controller: _scrollController,
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
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.title(context),
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
                  '题库',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                _buildBankList(theme),
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
