/// 题库页（规格文档第 3 章 §22.5：Q-01–Q-09；R4 按 04_bank mockup 重绘）。
///
/// 页头（题库 + 副标题）下是搜索/筛选行（mockup 未展示，属保留的既有功能，
/// 见任务报告），默认显示 4 张套卷卡 + 错题本/收藏入口；输入搜索或点筛选
/// chips 后切换为题目结果列表。
library;

import 'package:flutter/material.dart';

import '../../core/service_locator.dart';
import '../../core/theme.dart';
import '../../models/question.dart';
import '../../models/stats.dart';
import '../../router/app_router.dart';
import '../../widgets/account_sheet.dart';

/// Mock 暂无套卷作答进度，进度环恒为 0（接后端后按练习记录计算）。
const double _mockSetProgress = 0;

/// 模块代码 -> 中文展示名（套卷卡标签用完整名“子网划分”）。
String _moduleLabel(String module) => module == 'SUBNET' ? '子网划分' : module;

class BankModuleListPage extends StatefulWidget {
  const BankModuleListPage({super.key});

  @override
  State<BankModuleListPage> createState() => _BankModuleListPageState();
}

class _BankModuleListPageState extends State<BankModuleListPage> {
  List<ModuleStat> _modules = const <ModuleStat>[];
  List<Question> _samples = const <Question>[];
  int _wrongCount = 0;
  int _favoriteCount = 0;
  String _query = '';
  String? _moduleFilter;
  String? _typeFilter;
  bool _onlyUnanswered = false;
  bool _onlyWrong = false;

  static const List<String> _moduleNames = <String>[
    'VLAN',
    'OSPF',
    'ACL',
    'NAT',
    'SUBNET',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

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
    if (_onlyUnanswered || _onlyWrong) {
      // Mock 无作答记录与错题记录，筛选项恒为空（接后端后按 practice_records / wrong_items 过滤）。
      return const <Question>[];
    }
    return list;
  }

  void _openQuiz(String mode, int drawCount) {
    Navigator.of(context).pushNamed(
      AppRoutes.bankQuiz,
      arguments: <String, Object?>{'mode': mode, 'drawCount': drawCount},
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
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '题库',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'H3CNE 300 道 · 每套含解析',
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: AppFontSizes.pageSubtitle,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync_outlined),
            tooltip: '同步诊断',
            onPressed: () => showAccountSheet(context),
          ),
        ],
      ),
      body: Column(
        children: [
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
                ..._moduleNames.map(
                  (m) => _chip(
                    label: _moduleLabel(m),
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
        ? _moduleNames
        : _modules.map((m) => m.module).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.md,
      ),
      children: [
        _SetCard(
          title: '100 题套卷',
          subtitle: '100 题 · 5 个模块 · 含解析',
          modules: modules,
          onTap: () => _openQuiz('exam', 100),
        ),
        const SizedBox(height: AppSpacing.cardGap),
        _SetCard(
          title: '200 题套卷',
          subtitle: '200 题 · 5 个模块 · 含解析',
          modules: modules,
          onTap: () => _openQuiz('exam', 200),
        ),
        const SizedBox(height: AppSpacing.cardGap),
        _SetCard(
          title: '50 题套卷',
          subtitle: '50 题 · 5 个模块 · 含解析',
          modules: modules,
          onTap: () => _openQuiz('exam', 50),
        ),
        const SizedBox(height: AppSpacing.cardGap),
        _SetCard(
          title: '10 题速练',
          subtitle: '10 题 · 5 个模块 · 含解析',
          modules: modules,
          onTap: () => _openQuiz('quick', 10),
        ),
        const SizedBox(height: AppSpacing.cardGap),
        _EntryRow(
          icon: Icons.menu_book,
          iconColor: theme.colorScheme.error,
          title: '错题本',
          subtitle: _wrongCount == 0
              ? '暂无错题 · 做错的题自动收录'
              : '$_wrongCount 道 · 做错的题自动收录',
          onTap: () => Navigator.of(context).pushNamed(AppRoutes.bankWrong),
        ),
        const SizedBox(height: AppSpacing.cardGap),
        _EntryRow(
          icon: Icons.star,
          iconColor: AppColors.warning(context),
          title: '收藏',
          subtitle: '$_favoriteCount 道已收藏',
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
              size: AppSizes.progressRing + AppSpacing.xs,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              _onlyUnanswered || _onlyWrong
                  ? '暂无符合条件的题目（Mock 无作答/错题记录）'
                  : '没有找到相关题目',
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
            subtitle: Text('${_moduleLabel(q.module)} · ${_typeLabel(q.type)}'),
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

/// 套卷卡：左灰色进度环（上方百分比），中标题/副标题/5 个模块标签，
/// 右蓝色“开始”按钮（76x36、圆角 18）。
class _SetCard extends StatelessWidget {
  const _SetCard({
    required this.title,
    required this.subtitle,
    required this.modules,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final List<String> modules;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: AppSizes.setCardHeight,
      child: Material(
        color: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Row(
              children: [
                const _SetProgressRing(value: _mockSetProgress),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Wrap(
                        spacing: AppSpacing.xxs,
                        runSpacing: AppSpacing.xxs,
                        children: modules.map((m) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.xs,
                              vertical: AppSpacing.xxs,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(
                                AppSpacing.xs,
                              ),
                            ),
                            child: Text(
                              _moduleLabel(m),
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontSize: AppFontSizes.setCardTag,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                FilledButton(
                  onPressed: onTap,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(
                      AppSizes.setStartButtonWidth,
                      AppSizes.setStartButtonHeight,
                    ),
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        AppRadii.setStartButton,
                      ),
                    ),
                    textStyle: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  child: const Text('开始'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 套卷卡小进度环：灰色圆环 + 上方百分比标签（Mock 进度 0%）。
class _SetProgressRing extends StatelessWidget {
  const _SetProgressRing({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percent = (value * 100).round();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$percent%',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        SizedBox(
          width: AppSizes.setProgressRing,
          height: AppSizes.setProgressRing,
          child: CircularProgressIndicator(
            value: value,
            strokeWidth: 3,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// 错题本/收藏入口行（高 64）：彩色图标 + 标题/副标题 + 右侧灰色 chevron。
class _EntryRow extends StatelessWidget {
  const _EntryRow({
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
    return SizedBox(
      height: AppSizes.entryRowHeight,
      child: Material(
        color: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Row(
              children: [
                Icon(icon, color: iconColor, size: AppSizes.icon),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontSize: AppFontSizes.entryTitle,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
