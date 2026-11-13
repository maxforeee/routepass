/// 题库页（规格文档第 3 章 §22.5：Q-01–Q-09；R4 按 04_bank mockup 重绘）。
///
/// 页头（题库 + 副标题）下是搜索/筛选行（mockup 未展示，属保留的既有功能，
/// 见任务报告），默认显示 4 张套卷卡 + 错题本/收藏入口；输入搜索或点筛选
/// chips 后切换为题目结果列表。
library;

import 'package:flutter/material.dart';

import '../../core/service_locator.dart';
import '../../core/modules.dart';
import '../../core/theme.dart';
import '../../models/question.dart';
import '../../models/stats.dart';
import '../../router/app_router.dart';
import '../../widgets/module_tag.dart';
import '../../widgets/page_header.dart';
import '../../widgets/set_row_card.dart';

class BankModuleListPage extends StatefulWidget {
  const BankModuleListPage({super.key});

  @override
  State<BankModuleListPage> createState() => BankModuleListPageState();
}

class BankModuleListPageState extends State<BankModuleListPage> {
  List<ModuleStat> _modules = const <ModuleStat>[];
  List<Question> _samples = const <Question>[];
  List<String> _wrongIds = const <String>[];

  /// 已作答题目 id 集合（当前无作答记录源，恒为空；接后端后按练习记录填充）。
  final Set<String> _answeredIds = <String>{};
  int _wrongCount = 0;
  int _favoriteCount = 0;
  String _query = '';
  String? _moduleFilter;
  String? _typeFilter;
  bool _onlyUnanswered = false;
  bool _onlyWrong = false;

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
        _wrongIds = wrong.map((w) => w.question_id).toList();
        _wrongCount = wrong.length;
        _favoriteCount = favs.length;
      });
    } catch (_) {}
  }

  bool get _filtering =>
      _query.isNotEmpty ||
      _moduleFilter != null ||
      _typeFilter != null ||
      _onlyUnanswered ||
      _onlyWrong;

  List<Question> get _filtered {
    var list = _samples;
    if (_query.isNotEmpty) {
      list = list.where((q) => q.stem.contains(_query)).toList();
    }
    if (_moduleFilter != null) {
      list = list.where((q) => q.module == _moduleFilter).toList();
    }
    if (_typeFilter != null) {
      list = list.where((q) => q.type == _typeFilter).toList();
    }
    if (_onlyWrong) {
      list = list.where((q) => _wrongIds.contains(q.id)).toList();
    }
    if (_onlyUnanswered) {
      list = list.where((q) => !_answeredIds.contains(q.id)).toList();
    }
    return list;
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

  String _typeLabel(String type) {
    return switch (type) {
      'single' => '单选',
      'multiple' => '多选',
      'judge' => '判断',
      'fill' => '填空',
      _ => type,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: AppColors.pageBackground(context),
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.xs,
              ),
              child: PageHeader(title: '题库', subtitle: 'H3CNE 300 道 · 每套含解析'),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.xs,
                AppSpacing.md,
                AppSpacing.xs,
              ),
              child: TextField(
                decoration: InputDecoration(
                  hintText: '搜索题目',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: theme.colorScheme.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadii.card),
                    borderSide: BorderSide(
                      color: theme.colorScheme.outlineVariant,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadii.card),
                    borderSide: BorderSide(
                      color: theme.colorScheme.outlineVariant,
                    ),
                  ),
                ),
                onChanged: (v) => setState(() => _query = v.trim()),
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Row(
                children: [
                  ...kModuleOrder.map(
                    (m) => _chip(
                      label: moduleLabel(m),
                      selected: _moduleFilter == m,
                      onSelected: (v) =>
                          setState(() => _moduleFilter = v ? m : null),
                    ),
                  ),
                  _chip(
                    label: '单选',
                    selected: _typeFilter == 'single',
                    onSelected: (v) =>
                        setState(() => _typeFilter = v ? 'single' : null),
                  ),
                  _chip(
                    label: '多选',
                    selected: _typeFilter == 'multiple',
                    onSelected: (v) =>
                        setState(() => _typeFilter = v ? 'multiple' : null),
                  ),
                  _chip(
                    label: '只看未做',
                    selected: _onlyUnanswered,
                    onSelected: (v) => setState(() => _onlyUnanswered = v),
                  ),
                  _chip(
                    label: '只看错题',
                    selected: _onlyWrong,
                    onSelected: (v) => setState(() => _onlyWrong = v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Expanded(
              child: _filtering ? _buildResults(theme) : _buildSets(theme),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required void Function(bool) onSelected,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.xs),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: onSelected,
        showCheckmark: false,
        backgroundColor: theme.colorScheme.surface,
        selectedColor: theme.colorScheme.primaryContainer,
        side: BorderSide(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant,
        ),
        labelStyle: theme.textTheme.labelMedium?.copyWith(
          color: selected
              ? theme.colorScheme.onPrimaryContainer
              : theme.colorScheme.onSurfaceVariant,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
      ),
    );
  }

  Widget _buildSets(ThemeData theme) {
    final modules = _modules.isEmpty
        ? kModuleOrder
        : _modules.map((m) => m.module).toList();

    Widget moduleTags(List<String> mods) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: mods.map((m) {
          return Flexible(
            child: Padding(
              padding: const EdgeInsets.only(left: AppSpacing.xxs),
              child: ModuleTag(label: moduleLabel(m)),
            ),
          );
        }).toList(),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.md,
      ),
      children: [
        SetRowCard(
          title: '100 题套卷',
          subtitle: '100 题 · 5 个模块 · 含解析',
          trailing: moduleTags(modules),
          onTap: () => _openSetDetail(100),
        ),
        const SizedBox(height: AppSpacing.cardGap),
        SetRowCard(
          title: '200 题套卷',
          subtitle: '200 题 · 5 个模块 · 含解析',
          trailing: moduleTags(modules),
          onTap: () => _openSetDetail(200),
        ),
        const SizedBox(height: AppSpacing.cardGap),
        SetRowCard(
          title: '50 题套卷',
          subtitle: '50 题 · 5 个模块 · 含解析',
          trailing: moduleTags(modules),
          onTap: () => _openSetDetail(50),
        ),
        const SizedBox(height: AppSpacing.cardGap),
        SetRowCard(
          title: '10 题速练',
          subtitle: '10 题 · 5 个模块 · 含解析',
          trailing: moduleTags(modules),
          onTap: () => _openQuiz('quick', 10),
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
            Text(
              _onlyUnanswered || _onlyWrong ? '暂无符合条件的题目' : '没有找到相关题目',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.md,
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
