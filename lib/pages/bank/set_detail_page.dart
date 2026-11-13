/// 套卷详情页（R5：09_set_detail mockup）。
///
/// 从题库/首页的套卷“开始”进入，展示套卷规模、模块进度与答题说明；
/// “开始答题”再进答题页。套卷规模由路由参数 drawCount（100/200/50）推导。
library;

import 'package:flutter/material.dart';

import '../../core/service_locator.dart';
import '../../core/modules.dart';
import '../../core/theme.dart';
import '../../models/stats.dart';
import '../../router/app_router.dart';
import '../../widgets/reserved_slot.dart';

class SetDetailPage extends StatefulWidget {
  const SetDetailPage({super.key, required this.args});

  final Map<String, Object?> args;

  @override
  State<SetDetailPage> createState() => _SetDetailPageState();
}

class _SetDetailPageState extends State<SetDetailPage> {
  List<ModuleStat> _modules = const <ModuleStat>[];

  /// 套卷规模：路由参数 drawCount（100/200/50）。
  int get _drawCount =>
      widget.args['drawCount'] is int ? widget.args['drawCount'] as int : 100;

  /// 单选/多选：按 3:1 拆分（与题库套卷同一 Mock 题量比例）。
  int get _singleCount => _drawCount * 3 ~/ 4;
  int get _multipleCount => _drawCount - _singleCount;

  /// 每模块题量（5 个模块均分）。
  int get _perModuleCount => _drawCount ~/ 5;

  /// 时长估算：每题 0.6 分钟，四舍五入。
  int get _minutes => (_drawCount * 0.6).round();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final modules = await ServiceLocator.questionRepository.getModules();
      if (!mounted) return;
      setState(() => _modules = modules);
    } catch (_) {}
  }

  /// 展示模块顺序（优先题库模块接口，Mock 返回 5 个同序模块）。
  List<String> get _displayModules {
    if (_modules.isNotEmpty) {
      return _modules.map((m) => m.module).toList();
    }
    return kModuleOrder;
  }

  ModuleStat? _moduleStat(String module) {
    for (final m in _modules) {
      if (m.module == module) return m;
    }
    return null;
  }

  /// 模块进度（0–1）：Mock 无作答记录（answered/total 均为 0），故 0%。
  double _moduleProgress(String module) {
    final stat = _moduleStat(module);
    if (stat == null || stat.total <= 0) return 0;
    return (stat.answered / stat.total).clamp(0.0, 1.0);
  }

  void _start() {
    Navigator.of(context).pushNamed(
      AppRoutes.bankQuiz,
      arguments: <String, Object?>{'mode': 'exam', 'drawCount': _drawCount},
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final modules = _displayModules;
    return Scaffold(
      backgroundColor: AppColors.pageBackground(context),
      body: SafeArea(
        bottom: true,
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                child: IconButton(
                  icon: const Icon(
                    Icons.chevron_left,
                    size: AppSizes.iconLarge,
                  ),
                  tooltip: '返回',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.xs,
                  AppSpacing.md,
                  AppSpacing.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$_drawCount 题套卷',
                      style: theme.textTheme.headlineLarge?.copyWith(
                        fontSize: AppFontSizes.detailTitle,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'H3CNE 模拟套卷 · 每题含解析',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: AppFontSizes.detailBody,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _StatsRow(
                      drawCount: _drawCount,
                      single: _singleCount,
                      multiple: _multipleCount,
                      minutes: _minutes,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Container(
                      height: AppSizes.divider,
                      color: theme.colorScheme.outlineVariant,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    const ReservedSlot(),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      '知识点考察',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontSize: AppFontSizes.detailSectionTitle,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    for (final module in modules) ...[
                      _ModuleRow(
                        name: moduleLabel(module),
                        count: _perModuleCount,
                        progress: _moduleProgress(module),
                      ),
                      if (module != modules.last)
                        const SizedBox(height: AppSpacing.setDetailModuleGap),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    _InstructionsCard(minutes: _minutes),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xs,
                AppSpacing.lg,
                AppSizes.homeBottomPad,
              ),
              child: SizedBox(
                width: double.infinity,
                height: AppSizes.buttonHeight,
                child: FilledButton(
                  onPressed: _start,
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: theme.colorScheme.onPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        AppRadii.setDetailStartButton,
                      ),
                    ),
                    textStyle: theme.textTheme.bodyLarge?.copyWith(
                      fontSize: AppFontSizes.detailButton,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  child: const Text('开始答题'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 统计行：三列等宽，13px #334155。
class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.drawCount,
    required this.single,
    required this.multiple,
    required this.minutes,
  });

  final int drawCount;
  final int single;
  final int multiple;
  final int minutes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(child: _stat(context, theme, '$drawCount 题')),
        Expanded(child: _stat(context, theme, '单选 $single · 多选 $multiple')),
        Expanded(child: _stat(context, theme, '约 $minutes 分钟')),
      ],
    );
  }

  Widget _stat(BuildContext context, ThemeData theme, String text) {
    return Text(
      text,
      style: theme.textTheme.bodyMedium?.copyWith(
        fontSize: AppFontSizes.detailStat,
        color: AppColors.label(context),
      ),
    );
  }
}

/// 单个模块行：名称（14 粗）+ 右侧“N 题 · x%”（12 灰）+ 下方进度条。
class _ModuleRow extends StatelessWidget {
  const _ModuleRow({
    required this.name,
    required this.count,
    required this.progress,
  });

  final String name;
  final int count;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percent = (progress * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                name,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Text(
              '$count 题 · $percent%',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Container(
          height: AppSizes.setDetailProgressBarHeight,
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: theme.colorScheme.outlineVariant,
            borderRadius: BorderRadius.circular(AppRadii.setDetailProgressBar),
          ),
          child: FractionallySizedBox(
            widthFactor: progress.clamp(0.0, 1.0),
            child: Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(
                  AppRadii.setDetailProgressBar,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 答题说明卡：标题 + 三条绿色对勾说明。
class _InstructionsCard extends StatelessWidget {
  const _InstructionsCard({required this.minutes});

  final int minutes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines = <String>[
      '限时 $minutes 分钟，超时自动交卷',
      '交卷后可查看解析与得分',
      '做错的题自动收入错题本',
    ];
    return Container(
      height: AppSizes.setDetailInstructionsHeight,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.input),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '答题说明',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final line in lines) ...[
            Row(
              children: [
                Icon(
                  Icons.check_circle,
                  size: AppSizes.iconSmall,
                  color: AppColors.success(context),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    line,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: AppFontSizes.detailStat,
                      color: AppColors.label(context),
                    ),
                  ),
                ),
              ],
            ),
            if (line != lines.last) const SizedBox(height: AppSpacing.xs),
          ],
        ],
      ),
    );
  }
}
