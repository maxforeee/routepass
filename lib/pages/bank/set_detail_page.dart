/// 套卷详情页（R5：09_set_detail mockup）。
///
/// 从题库/首页的套卷“开始”进入，展示套卷规模、模块进度与答题说明；
/// “开始答题”再进答题页。四套卷（100/200/50/10）共用本模板，
/// 规模数字全部由路由参数 drawCount 推导。
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

  /// 套卷规模：路由参数 drawCount（100/200/50/10）。
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
        child: Stack(
          children: [
            Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                    ),
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
                      // 底部只为本页钉住按钮留位（导航已按 Q1 隐藏）。
                      AppSizes.buttonHeight + AppSpacing.md * 2,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$_drawCount 题套卷',
                          style: theme.textTheme.headlineLarge?.copyWith(
                            fontSize: AppFontSizes.detailTitle,
                            fontWeight: FontWeight.w800,
                            color: AppColors.title(context),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        // 大标题保持 md 页边距；标题以下内容每侧再内缩
                        // contentInset，离屏幕边 md + contentInset。
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.contentInset,
                          ),
                          child: _MetaRow(
                            single: _singleCount,
                            multiple: _multipleCount,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.contentInset,
                          ),
                          child: Container(
                            height: AppSizes.divider,
                            color: AppColors.brandBorder,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.contentInset,
                          ),
                          child: const ReservedSlot(),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.contentInset,
                          ),
                          child: Text(
                            '知识点考察',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontSize: AppFontSizes.detailSectionTitle,
                              fontWeight: FontWeight.bold,
                              color: AppColors.title(context),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        for (final module in modules) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.contentInset,
                            ),
                            child: _ModuleRow(
                              name: moduleLabel(module),
                              count: _perModuleCount,
                              progress: _moduleProgress(module),
                            ),
                          ),
                          if (module != modules.last)
                            const SizedBox(
                              height: AppSpacing.setDetailModuleGap,
                            ),
                        ],
                        const SizedBox(height: AppSpacing.lg),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.contentInset,
                          ),
                          child: _InstructionsCard(minutes: _minutes),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Positioned(
              left: AppSpacing.md + AppSpacing.contentInset,
              right: AppSpacing.md + AppSpacing.contentInset,
              // 导航已隐藏：按钮贴 SafeArea 底边，只留常规间距。
              bottom: AppSpacing.md,
              child: SizedBox(
                width: double.infinity,
                height: AppSizes.buttonHeight,
                child: FilledButton(
                  onPressed: _start,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brandPrimary,
                    foregroundColor: AppColors.brandSurface,
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

/// 元信息行：左副标题，右“单选 X · 多选 Y”（13px），基线对齐。
class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.single, required this.multiple});

  final int single;
  final int multiple;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(
          child: Text(
            'H3CNE-RS+ 模拟套卷 · 含解析',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: AppFontSizes.detailBody,
              color: AppColors.brandCaption,
            ),
          ),
        ),
        Text(
          '单选 $single · 多选 $multiple',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontSize: AppFontSizes.detailStat,
            color: AppColors.brandCaption,
          ),
        ),
      ],
    );
  }
}

/// 单个模块行：名称（14 粗）+ 右侧“N 题 · x%”（13 灰）+ 下方进度条。
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
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: AppFontSizes.detailBody,
                  fontWeight: FontWeight.bold,
                  color: AppColors.title(context),
                ),
              ),
            ),
            Text(
              '$count 题 · $percent%',
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: AppFontSizes.detailStat,
                color: AppColors.brandCaption,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Container(
          height: AppSizes.setDetailProgressBarHeight,
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: AppColors.brandBorder,
            borderRadius: BorderRadius.circular(AppRadii.setDetailProgressBar),
          ),
          child: FractionallySizedBox(
            widthFactor: progress.clamp(0.0, 1.0),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.brandPrimary,
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

/// 答题说明卡：标题 + 三条说明。
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
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.brandSurface,
        borderRadius: BorderRadius.circular(AppRadii.input),
        border: Border.all(color: AppColors.brandBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '答题说明',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.title(context),
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
