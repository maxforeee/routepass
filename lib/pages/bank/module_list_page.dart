/// 题库页（规格文档第 3 章 §22.5：Q-01–Q-09；R4 按 04_bank mockup 重绘）。
///
/// 页头（题库 + 副标题）下是搜索条（保留的既有功能），默认显示 4 张套卷卡 +
/// 错题本/收藏入口；输入搜索后切换为题目结果列表。（G2b：筛选 chips 已按
/// canva 参考移除，文本搜索行为不变。F3：标题 32px 与搜索条左缘对齐，头像
/// 只在首页，模块标签按 canva 参考排成 3 列两行。）
library;

import 'package:flutter/material.dart';

import '../../core/service_locator.dart';
import '../../core/modules.dart';
import '../../core/theme.dart';
import '../../models/question.dart';
import '../../models/stats.dart';
import '../../router/app_router.dart';
import '../../widgets/set_row_card.dart';
import '../../widgets/set_row_tags.dart';

class BankModuleListPage extends StatefulWidget {
  const BankModuleListPage({super.key});

  @override
  State<BankModuleListPage> createState() => BankModuleListPageState();
}

class BankModuleListPageState extends State<BankModuleListPage> {
  List<ModuleStat> _modules = const <ModuleStat>[];
  List<Question> _samples = const <Question>[];
  int _wrongCount = 0;
  int _favoriteCount = 0;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// tab 切回时刷新（重拉模块 / 样题 / 错题 / 收藏）。
  Future<void> refresh() => _load();

  Future<void> _load() async {
    try {
      final modules = await ServiceLocator.questionRepository.getModules();
      final samples = await ServiceLocator.questionRepository.drawQuestions(
        mode: 'practice',
        drawCount: 100,
      );
      final wrong = await ServiceLocator.wrongService.getWrongBook();
      final favs = await ServiceLocator.favoriteService.getFavoriteIds();
      if (!mounted) return;
      setState(() {
        _modules = modules;
        _samples = samples;
        _wrongCount = wrong.length;
        _favoriteCount = favs.length;
      });
    } catch (_) {}
  }

  List<Question> get _filtered => _query.isEmpty
      ? _samples
      : _samples.where((q) => q.stem.contains(_query)).toList();

  void _openSetDetail(int drawCount) {
    Navigator.of(context).pushNamed(
      AppRoutes.bankSetDetail,
      arguments: <String, Object?>{'mode': 'exam', 'drawCount': drawCount},
    );
  }

  String _typeLabel(String type) {
    return switch (type) {
      'single' => '单选',
      'multiple' => '多选',
      'judge' => '判断',
      'fill' => '填空',
      _ => type,
    };
  }

  /// 副标题总数：由模块题量数据求和得出（Mock 下各模块题量为 0）。
  int get _questionTotal => _modules.fold<int>(0, (sum, m) => sum + m.total);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: AppColors.pageBackground(context),
      body: Column(
        // stretch：页头块宽度撑满，标题左缘与搜索条 / 卡片同为 16px。
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSizes.homeTopPad,
              AppSpacing.md,
              AppSpacing.xs,
            ),
            child: _buildHeader(theme),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.xxs,
              AppSpacing.md,
              AppSpacing.cardGap,
            ),
            child: _buildSearchBar(theme),
          ),
          Expanded(
            child: _query.isNotEmpty ? _buildResults(theme) : _buildSets(theme),
          ),
        ],
      ),
    );
  }

  /// 页头（canva 参考：标题 32px 特粗作为页面内容 + 副标题 13px）。
  Widget _buildHeader(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '题库',
          style: TextStyle(
            fontSize: AppFontSizes.homeGreetingName,
            fontWeight: FontWeight.w800,
            color: AppColors.title(context),
            height: 1.2,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          'H3CNE $_questionTotal 道 · 每套含解析',
          style: TextStyle(
            fontSize: AppFontSizes.pageSubtitle,
            color: AppColors.brandSecondaryText,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  /// 搜索条（canva 参考：白色胶囊，高 48，全圆角；右端蓝色圆形搜索按钮）。
  Widget _buildSearchBar(ThemeData theme) {
    return Container(
      height: AppSizes.bankSearchBarHeight,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xxs,
        AppSpacing.xxs,
        AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: AppColors.brandSurface,
        borderRadius: BorderRadius.circular(AppRadii.searchPill),
        border: Border.all(
          color: AppColors.brandBorder,
          width: AppSizes.borderWidth,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              style: theme.textTheme.labelLarge?.copyWith(
                color: AppColors.brandTitle,
              ),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: '搜索题目',
                hintStyle: theme.textTheme.labelLarge?.copyWith(
                  color: AppColors.brandCaption,
                ),
              ),
              onChanged: (v) => setState(() => _query = v.trim()),
            ),
          ),
          Container(
            width: AppSizes.bankSearchButtonSize,
            height: AppSizes.bankSearchButtonSize,
            decoration: const BoxDecoration(
              color: AppColors.brandPrimary,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.search,
              size: AppSizes.icon,
              color: AppColors.brandOnPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSets(ThemeData theme) {
    final modules = _modules.isEmpty
        ? kModuleOrder
        : _modules.map((m) => m.module).toList();
    final tags = SetRowTags(labels: modules.map(moduleLabel).toList());

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSizes.homeBottomPad,
      ),
      children: [
        SetRowCard(
          title: '100 题套卷',
          subtitle: '100 题 · 5 个模块 · 含解析',
          trailing: tags,
          onTap: () => _openSetDetail(100),
        ),
        const SizedBox(height: AppSpacing.cardGap),
        SetRowCard(
          title: '200 题套卷',
          subtitle: '200 题 · 5 个模块 · 含解析',
          trailing: tags,
          onTap: () => _openSetDetail(200),
        ),
        const SizedBox(height: AppSpacing.cardGap),
        SetRowCard(
          title: '50 题套卷',
          subtitle: '50 题 · 5 个模块 · 含解析',
          trailing: tags,
          onTap: () => _openSetDetail(50),
        ),
        const SizedBox(height: AppSpacing.cardGap),
        SetRowCard(
          title: '10 题速练',
          subtitle: '10 题 · 5 个模块 · 含解析',
          trailing: tags,
          onTap: () => _openSetDetail(10),
        ),
        const SizedBox(height: AppSpacing.cardGap),
        SetRowCard(
          leading: Icon(Icons.menu_book, color: theme.colorScheme.error),
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
        const SizedBox(height: AppSpacing.cardGap),
        SetRowCard(
          leading: Icon(Icons.star, color: AppColors.warning(context)),
          title: '收藏',
          subtitle: '$_favoriteCount 道已收藏',
          trailing: const Icon(
            Icons.chevron_right,
            color: AppColors.brandCaption,
          ),
          onTap: () => Navigator.of(context).pushNamed(AppRoutes.bankFavorites),
        ),
      ],
    );
  }

  Widget _buildResults(ThemeData theme) {
    final results = _filtered;
    if (results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_outlined,
              size: AppSizes.emptyStateIcon,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text('没有找到相关题目', style: theme.textTheme.bodyMedium),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSizes.homeBottomPad,
      ),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final q = results[index];
        return Card(
          margin: const EdgeInsets.only(bottom: AppSpacing.xs),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.card),
            side: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
          child: ListTile(
            title: Text(q.stem, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text('${moduleLabel(q.module)} · ${_typeLabel(q.type)}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).pushNamed(
              AppRoutes.bankQuiz,
              arguments: <String, Object?>{
                'mode': 'single',
                'questionId': q.id,
              },
            ),
          ),
        );
      },
    );
  }
}
