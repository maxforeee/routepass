/// 题库页（规格文档第 3 章 §22.5：Q-01–Q-09）。
///
/// 默认显示套卷卡 + 错题本/收藏入口；输入搜索或点筛选 chips 后切换为题目结果列表。
library;

import 'package:flutter/material.dart';

import '../../core/service_locator.dart';
import '../../models/question.dart';
import '../../models/stats.dart';
import '../../router/app_router.dart';
import '../../widgets/account_sheet.dart';

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

  String _moduleLabel(String module) => module == 'SUBNET' ? '子网' : module;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('题库'),
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
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              decoration: InputDecoration(
                hintText: '搜索题目',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (v) => setState(() => _query = v.trim()),
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                ..._moduleNames.map(
                  (m) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(_moduleLabel(m)),
                      selected: _moduleFilter == m,
                      onSelected: (v) => setState(
                        () => _moduleFilter = v ? m : null,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: const Text('单选'),
                    selected: _typeFilter == 'single',
                    onSelected: (v) => setState(
                      () => _typeFilter = v ? 'single' : null,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: const Text('多选'),
                    selected: _typeFilter == 'multiple',
                    onSelected: (v) => setState(
                      () => _typeFilter = v ? 'multiple' : null,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: const Text('只看未做'),
                    selected: _onlyUnanswered,
                    onSelected: (v) => setState(() => _onlyUnanswered = v),
                  ),
                ),
                FilterChip(
                  label: const Text('只看错题'),
                  selected: _onlyWrong,
                  onSelected: (v) => setState(() => _onlyWrong = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _filtering ? _buildResults(theme) : _buildSets(theme),
          ),
        ],
      ),
    );
  }

  Widget _buildSets(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        Text(
          '套卷',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        _SetCard(
          count: 100,
          minutes: '约 50 分钟',
          height: 112,
          modules: _modules.isEmpty ? _moduleNames : _modules.map((m) => m.module).toList(),
          onTap: () => _openQuiz('exam', 100),
        ),
        const SizedBox(height: 12),
        _SetCard(
          count: 200,
          minutes: '约 100 分钟',
          height: 112,
          modules: _modules.isEmpty ? _moduleNames : _modules.map((m) => m.module).toList(),
          onTap: () => _openQuiz('exam', 200),
        ),
        const SizedBox(height: 12),
        _SetCard(
          count: 50,
          minutes: '约 25 分钟',
          height: 104,
          modules: _modules.isEmpty ? _moduleNames : _modules.map((m) => m.module).toList(),
          onTap: () => _openQuiz('exam', 50),
        ),
        const SizedBox(height: 12),
        _SetCard(
          count: 10,
          minutes: '约 5 分钟',
          height: 96,
          showProgress: false,
          modules: _modules.isEmpty ? _moduleNames : _modules.map((m) => m.module).toList(),
          onTap: () => _openQuiz('quick', 10),
        ),
        const SizedBox(height: 12),
        _EntryRow(
          icon: Icons.error_outline,
          title: '错题本',
          badge: _wrongCount > 0 ? '$_wrongCount 道' : null,
          onTap: () =>
              Navigator.of(context).pushNamed(AppRoutes.bankWrong),
        ),
        const SizedBox(height: 12),
        _EntryRow(
          icon: Icons.bookmark_border,
          title: '收藏',
          badge: _favoriteCount > 0 ? '$_favoriteCount 道' : null,
          onTap: () =>
              Navigator.of(context).pushNamed(AppRoutes.bankFavorites),
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
            const Icon(Icons.search_off_outlined, size: 48),
            const SizedBox(height: 12),
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
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final q = results[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            title: Text(
              q.stem,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
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

  String _typeLabel(String type) {
    return switch (type) {
      'single' => '单选',
      'multiple' => '多选',
      'judge' => '判断',
      'fill' => '填空',
      _ => type,
    };
  }
}

/// 套卷卡：左题量 display 28，右覆盖模块 + 预计时长 + 进度条，开始按钮高 40。
class _SetCard extends StatelessWidget {
  const _SetCard({
    required this.count,
    required this.minutes,
    required this.height,
    required this.modules,
    required this.onTap,
    this.showProgress = true,
  });

  final int count;
  final String minutes;
  final double height;
  final List<String> modules;
  final VoidCallback onTap;
  final bool showProgress;

  String _moduleLabel(String module) => module == 'SUBNET' ? '子网' : module;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '$count',
                      style: theme.textTheme.displaySmall,
                    ),
                    const SizedBox(width: 4),
                    Text('题套卷', style: theme.textTheme.titleMedium),
                    const Spacer(),
                    FilledButton(
                      onPressed: onTap,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(72, 40),
                      ),
                      child: const Text('开始'),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 4,
                  children: modules.map((m) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _moduleLabel(m),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    );
                  }).toList(),
                ),
                if (showProgress) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        minutes,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: LinearProgressIndicator(value: 0),
                      ),
                    ],
                  ),
                ] else ...[
                  const SizedBox(height: 4),
                  Text(
                    minutes,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 错题本/收藏入口行（高 56，数量徽标）。
class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 56,
      child: Card(
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Text(title, style: theme.textTheme.titleMedium),
                const Spacer(),
                if (badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      badge!,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
