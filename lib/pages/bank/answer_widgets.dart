/// 答题页共用组件（规格文档第 3 章 §22.6：A-07、A-10、A-13–A-17）。
library;

import 'package:flutter/material.dart';

import '../../core/app_animations.dart';
import '../../core/theme.dart';
import '../../models/practice.dart';
import '../../models/question.dart';

/// 题型标签（A-07）。
String questionTypeLabel(String type) {
  return switch (type) {
    'single' => '单选',
    'multiple' => '多选',
    'judge' => '判断',
    'fill' => '填空',
    _ => type,
  };
}

/// 选项行状态（F19）：判分后着色；旧调用点不传，默认 idle。
enum OptionTileState { idle, selected, correct, wrong }

/// 选中脉冲的缩放低点（规范 §11：Scale 1.0 → 0.98 → 1.0）。
const double _optionPulseScale = 0.98;

/// 选中抬起高度（规范 §11：Elevation 0dp ↔ 2dp）。
const double _optionSelectElevation = 2;

/// 选项行（A-10）：min 高 56，左字母圆标 28，选中 primaryContainer + primary 描边。
/// 多选显示 checkbox 图标。F19 起支持判分配色：正确项浅绿 / 错误项浅红。
///
/// F20 §11 选中/取消选中：选中 [AppDurations.m] + [AppDurations.enter]，整行
/// Scale 1.0 → 0.98 → 1.0、Elevation 0 → 2dp、勾选标记 Scale 0 → 1 + Alpha 0 → 1；
/// 取消 [AppDurations.s] + [AppDurations.exit]，Elevation 与标记反向（无脉冲）。
/// 按压缩放交给 [Pressable]，背景/描边颜色交给 [AnimatedContainer]，不再瞬间跳色。
class OptionTile extends StatefulWidget {
  const OptionTile({
    super.key,
    required this.option,
    required this.selected,
    required this.multiple,
    required this.onTap,
    this.state = OptionTileState.idle,
  });

  final QuestionOption option;
  final bool selected;
  final bool multiple;
  final VoidCallback onTap;
  final OptionTileState state;

  @override
  State<OptionTile> createState() => _OptionTileState();
}

class _OptionTileState extends State<OptionTile> with TickerProviderStateMixin {
  late final AnimationController _selectController;
  late final AnimationController _pulseController;
  late final CurvedAnimation _select;
  late final CurvedAnimation _pulseCurve;
  late final Animation<double> _pulseScale;

  @override
  void initState() {
    super.initState();
    _selectController = AnimationController(
      vsync: this,
      duration: AppDurations.m,
      value: widget.selected ? 1.0 : 0.0,
    );
    _select = CurvedAnimation(
      parent: _selectController,
      curve: AppDurations.enter,
      reverseCurve: AppDurations.exit,
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: AppDurations.m,
    );
    _pulseCurve = CurvedAnimation(
      parent: _pulseController,
      curve: AppDurations.enter,
    );
    _pulseScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: _optionPulseScale),
        weight: 1,
      ),
      TweenSequenceItem(
        tween: Tween(begin: _optionPulseScale, end: 1.0),
        weight: 1,
      ),
    ]).animate(_pulseCurve);
  }

  @override
  void didUpdateWidget(OptionTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected == widget.selected) return;
    _selectController.duration = widget.selected
        ? AppDurations.m
        : AppDurations.s;
    if (widget.selected) {
      _selectController.forward();
      _pulseController.forward(from: 0.0);
    } else {
      _selectController.reverse();
    }
  }

  @override
  void dispose() {
    _select.dispose();
    _pulseCurve.dispose();
    _selectController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  bool get _highlighted =>
      widget.state == OptionTileState.selected ||
      widget.state == OptionTileState.correct ||
      widget.state == OptionTileState.wrong ||
      widget.selected;

  Color _background(BuildContext context) {
    final theme = Theme.of(context);
    return switch (widget.state) {
      OptionTileState.correct => AppColors.dailyCorrectBackground(context),
      OptionTileState.wrong => AppColors.wrongIconBackground(context),
      OptionTileState.selected => theme.colorScheme.primaryContainer,
      OptionTileState.idle =>
        widget.selected
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest,
    };
  }

  Color _border(BuildContext context) {
    final theme = Theme.of(context);
    return switch (widget.state) {
      OptionTileState.correct => AppColors.success(context),
      OptionTileState.wrong => AppColors.wrongIconForeground(context),
      OptionTileState.selected => theme.colorScheme.primary,
      OptionTileState.idle =>
        widget.selected
            ? theme.colorScheme.primary
            : theme.colorScheme.outlineVariant,
    };
  }

  Color? _letterBackground(BuildContext context) {
    return switch (widget.state) {
      OptionTileState.correct => AppColors.success(context),
      OptionTileState.wrong => AppColors.wrongIconForeground(context),
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final letterBg = _letterBackground(context);
    final highlighted = _highlighted;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Pressable(
        scale: Pressable.cardScale,
        pressCurve: AppDurations.standard,
        child: ScaleTransition(
          scale: _pulseScale,
          child: AnimatedBuilder(
            animation: _select,
            builder: (context, child) => Material(
              color: Colors.transparent,
              elevation: _optionSelectElevation * _select.value,
              borderRadius: BorderRadius.circular(12),
              child: child,
            ),
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(12),
              child: AnimatedContainer(
                duration: widget.selected ? AppDurations.m : AppDurations.s,
                curve: widget.selected ? AppDurations.enter : AppDurations.exit,
                constraints: const BoxConstraints(minHeight: 56),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: _background(context),
                  border: Border.all(color: _border(context)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color:
                            letterBg ??
                            (highlighted
                                ? theme.colorScheme.primary
                                : theme.colorScheme.surface),
                        border: Border.all(color: theme.colorScheme.outline),
                      ),
                      child: Text(
                        widget.option.key,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: letterBg != null
                              ? theme.colorScheme.onPrimary
                              : (highlighted
                                    ? theme.colorScheme.onPrimary
                                    : theme.colorScheme.onSurface),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.option.text,
                        style: theme.textTheme.bodyLarge,
                      ),
                    ),
                    if (widget.multiple) _buildCheckMark(theme, highlighted),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 勾选标记（规范 §11）：Scale 0 ↔ 1 + Alpha 0 ↔ 1。空框与实框按动画进度
  /// 交接，静止态只留当前那一个图标，选中/未选中的图标构成与改动前一致。
  Widget _buildCheckMark(ThemeData theme, bool highlighted) {
    return AnimatedBuilder(
      animation: _select,
      builder: (context, _) {
        final double t = _select.value;
        return Stack(
          alignment: Alignment.center,
          children: [
            if (t < 1.0)
              Icon(
                Icons.check_box_outline_blank,
                color: highlighted
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            if (t > 0.0)
              FadeTransition(
                opacity: _select,
                // 三轴同比缩放：Transform.scale 的矩阵 Z 轴恒为 1，量不出真实缩放。
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.diagonal3Values(t, t, t),
                  child: Icon(
                    Icons.check_box,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// 答题卡 sheet 内容（A-13）：5 列圆 36，状态色 未答/已答/标记/当前。
class AnswerSheetContent extends StatelessWidget {
  const AnswerSheetContent({
    super.key,
    required this.questions,
    required this.answers,
    required this.marked,
    required this.currentIndex,
    required this.onJump,
  });

  final List<Question> questions;
  final Map<String, List<String>> answers;
  final Set<String> marked;
  final int currentIndex;
  final void Function(int index) onJump;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('答题卡', style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          Flexible(
            child: GridView.builder(
              shrinkWrap: true,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 5,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
              ),
              itemCount: questions.length,
              itemBuilder: (context, index) {
                final q = questions[index];
                final answered = (answers[q.id] ?? const []).isNotEmpty;
                final isCurrent = index == currentIndex;
                final isMarked = marked.contains(q.id);
                return InkWell(
                  onTap: () => onJump(index),
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: answered
                          ? theme.colorScheme.primaryContainer
                          : theme.colorScheme.surfaceContainerHighest,
                      border: Border.all(
                        color: isCurrent
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outlineVariant,
                        width: isCurrent ? 2 : 1,
                      ),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Text('${index + 1}', style: theme.textTheme.bodyMedium),
                        if (isMarked)
                          Positioned(
                            right: 0,
                            top: 0,
                            child: Icon(
                              Icons.flag,
                              size: 12,
                              color: theme.colorScheme.error,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 解析卡（A-14）：提交后显示。Mock 下 correct 恒为 null，不判对错，
/// 只显示占位文案与“样例数据”标注，不编造答案与解析。
class AnalysisCard extends StatefulWidget {
  const AnalysisCard({
    super.key,
    required this.question,
    required this.result,
    required this.chosen,
  });

  final Question question;
  final AnswerResult result;
  final List<String> chosen;

  @override
  State<AnalysisCard> createState() => _AnalysisCardState();
}

class _AnalysisCardState extends State<AnalysisCard> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = widget.question;
    final correctText = q.answer.isEmpty ? '样例数据，无答案' : q.answer.join('、');
    return Card(
      margin: const EdgeInsets.only(top: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('解析', style: theme.textTheme.titleMedium)),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('样例数据', style: theme.textTheme.labelMedium),
                ),
                IconButton(
                  icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                  tooltip: _expanded ? '收起解析' : '展开解析',
                  onPressed: () => setState(() => _expanded = !_expanded),
                ),
              ],
            ),
            if (_expanded) ...[
              const SizedBox(height: 8),
              Text(
                '你的答案：${widget.chosen.isEmpty ? '未作答' : widget.chosen.join('、')}',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 4),
              Text('正确答案：$correctText', style: theme.textTheme.bodyMedium),
              const SizedBox(height: 4),
              Text(
                widget.result.explanation,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 交卷 dialog（A-16）：显示未答数，确认/取消。返回 true 表示确认交卷。
Future<bool> showSubmitDialog(
  BuildContext context, {
  required int unanswered,
}) async {
  final result = await showAppDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('确认交卷'),
        content: Text(
          unanswered > 0 ? '还有 $unanswered 题未答，确认交卷？' : '全部已答，确认交卷？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认交卷'),
          ),
        ],
      );
    },
  );
  return result ?? false;
}

/// 退出保留进度确认（A-01）：返回 true 表示退出并保留进度。
Future<bool> showExitConfirmDialog(BuildContext context) async {
  final result = await showAppDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('退出答题'),
        content: const Text('退出后可在首页“继续学习”恢复作答。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('退出并保留进度'),
          ),
        ],
      );
    },
  );
  return result ?? false;
}

/// 结果 sheet 内容（A-17）：得分 display 28 / 用时 / 正确率 / 逐题回顾 / 错题重练 / 返回。
/// Mock 下 score 恒为 null，显示“样例考试，不计分”，绝不编造分数。
class ResultSheetContent extends StatelessWidget {
  const ResultSheetContent({
    super.key,
    required this.total,
    required this.answered,
    required this.elapsed,
    required this.score,
    required this.detail,
    required this.isExam,
    required this.questions,
    required this.answers,
    required this.onReview,
    required this.onRetryWrong,
    required this.onClose,
  });

  final int total;
  final int answered;
  final Duration elapsed;
  final int? score;
  final String detail;
  final bool isExam;
  final List<Question> questions;
  final Map<String, List<String>> answers;
  final void Function(int index) onReview;
  final VoidCallback onRetryWrong;
  final VoidCallback onClose;

  String get _elapsedText {
    final m = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(isExam ? '考试结果' : '练习完成', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          if (score != null)
            Text(
              '$score 分',
              style: theme.textTheme.displaySmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            )
          else
            Text(
              isExam ? '样例考试，不计分' : '本次练习 $answered/$total 题',
              style: theme.textTheme.titleMedium,
            ),
          const SizedBox(height: 8),
          Text(
            '用时 $_elapsedText · 已答 $answered/$total 题',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (detail.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(detail, style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: 16),
          Text('逐题回顾', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: questions.length,
              itemBuilder: (context, index) {
                final q = questions[index];
                final hasAnswer = (answers[q.id] ?? const []).isNotEmpty;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 16,
                    child: Text('${index + 1}'),
                  ),
                  title: Text(
                    q.stem,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Text(hasAnswer ? '已答' : '未答'),
                  onTap: () => onReview(index),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onRetryWrong,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: const Text('错题重练'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: onClose,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: const Text('返回'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
