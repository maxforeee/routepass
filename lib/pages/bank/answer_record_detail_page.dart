/// 答题记录详情页（F25 Chunk 2a）。
///
/// 前置页点记录行进入：只显示摘要（答题数 / 答对 / 正确率）与薄弱点，
/// 加「查看试卷」入口和删除按钮；不渲染题目列表（试卷页由 Chunk 2b
/// 装配，路由名 [AppRoutes.bankRecordPaper] 已预留）。
///
/// 摘要优先取 `GET /practice/records/{id}` 的真实 attempts 统计；未登录 /
/// 离线 / 本地未同步记录回落本地 kv 摘要（薄弱点显示“待接口”，不虚构）。
/// 删除同时清服务端与本地 kv；断点记录另清进行态，「继续练习」不再续答。
library;

import 'package:flutter/material.dart';

import '../../core/app_animations.dart';
import '../../core/modules.dart';
import '../../core/service_locator.dart';
import '../../core/theme.dart';
import '../../models/answer_record.dart';
import '../../models/practice.dart';
import '../../router/app_router.dart';
import '../../services/bank/answer_record_service.dart';
import '../../services/bank/answer_session_service.dart';
import '../../services/bank/practice_service.dart';
import '../../services/bank/record_paper_preload.dart';
import '../../widgets/loading_skeleton.dart';

class AnswerRecordDetailPage extends StatefulWidget {
  const AnswerRecordDetailPage({
    super.key,
    required this.args,
    this.practiceService,
    this.recordService,
    this.sessionService,
  });

  /// 路由参数：`{'record': AnswerRecord}`。
  final Map<String, Object?> args;

  /// 测试可注入；生产环境不传，走 ServiceLocator 里的实现。
  final PracticeService? practiceService;
  final AnswerRecordService? recordService;
  final AnswerSessionService? sessionService;

  @override
  State<AnswerRecordDetailPage> createState() => _AnswerRecordDetailPageState();
}

class _AnswerRecordDetailPageState extends State<AnswerRecordDetailPage> {
  PracticeRecordDetail? _detail;
  bool _deleting = false;

  /// F27：服务端详情在途时，摘要数值与薄弱点显示同尺寸骨架，到达后淡入；
  /// 无 serverId（纯本地记录）不进入加载态，直接显示本地摘要。
  bool _detailLoading = false;

  late final PracticeService _practiceService;
  late final AnswerRecordService _recordService;
  late final AnswerSessionService _sessionService;

  AnswerRecord? get _record {
    final record = widget.args['record'];
    return record is AnswerRecord ? record : null;
  }

  @override
  void initState() {
    super.initState();
    _practiceService = widget.practiceService ?? ServiceLocator.practiceService;
    _recordService = widget.recordService ?? ServiceLocator.answerRecordService;
    _sessionService =
        widget.sessionService ?? ServiceLocator.answerSessionService;
    _load();
  }

  Future<void> _load() async {
    final serverId = _record?.serverId;
    if (serverId == null || serverId.isEmpty) return;
    // 只在 initState 调用：首帧即加载态，直接赋值，不用 setState。
    _detailLoading = true;
    try {
      final detail = await _practiceService.getRecordDetail(serverId);
      if (!mounted) return;
      // detail 为 null（接口未就绪）时保留本地摘要，骨架照常退场。
      setState(() {
        _detail = detail;
        _detailLoading = false;
      });
    } catch (_) {
      // 离线 / 未登录：保留本地摘要，不抛给 UI。
      if (!mounted) return;
      setState(() => _detailLoading = false);
    }
  }

  int get _answered => _detail?.answered ?? _record?.answeredCount ?? 0;

  int? get _correct => _detail?.correct ?? _record?.correctCount;

  /// 正确率百分数：服务端详情优先，其次本地 correctCount；都没有返回 null。
  int? get _scorePercent {
    final detail = _detail;
    if (detail != null) return detail.answered == 0 ? null : detail.score;
    final record = _record;
    final correct = record?.correctCount;
    if (record == null || correct == null || record.answeredCount == 0) {
      return null;
    }
    return (correct / record.answeredCount * 100).round();
  }

  String get _dateText {
    final record = _record;
    if (record == null) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(record.updatedAt);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Text('删除记录'),
          content: const Text('删除后不可恢复，确定删除这条答题记录吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    await _delete();
  }

  Future<void> _delete() async {
    final record = _record;
    if (record == null) return;
    setState(() => _deleting = true);

    // 服务端删除失败（离线 / 未登录）不阻塞本地删除。
    final serverId = record.serverId;
    if (serverId != null && serverId.isNotEmpty) {
      try {
        await _practiceService.deleteRecord(serverId);
      } catch (_) {}
    }
    try {
      _recordService.remove(record.id);
    } catch (_) {}
    // 断点记录：进行态一并清掉，前置页「继续练习」不再续答。
    if (record.isBreakpoint) {
      try {
        _sessionService.clear(setId: record.setId, mode: record.mode);
      } catch (_) {}
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  void _openPaper() {
    final record = _record;
    if (record == null) return;
    // F27：导航前先后台预取试卷数据（不等待、不阻塞导航）；失败由试卷页
    // 自身的骨架 → 重试态兜底。F29：start 契约不抛错（空 sessionId 自行
    // no-op，同步抛错已在 PreloadSlot 内兜底），_practiceService 已在
    // initState 解析，无需再包 try/catch。
    RecordPaperPreload.start(
      sessionId: record.serverId ?? '',
      service: _practiceService,
    );
    Navigator.of(context).pushNamed(
      AppRoutes.bankRecordPaper,
      arguments: <String, Object?>{
        'record': record,
        'sessionId': record.serverId ?? '',
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final record = _record;
    return Scaffold(
      backgroundColor: AppColors.pageBackground(context),
      body: SafeArea(
        bottom: true,
        child: record == null
            ? Center(
                child: Text(
                  '记录不存在',
                  style: TextStyle(
                    fontSize: AppFontSizes.detailBody,
                    color: AppColors.cardCaption(context),
                  ),
                ),
              )
            : Stack(
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
                            // 底部为钉住的删除按钮留位。
                            AppSizes.buttonHeight + AppSpacing.md * 2,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '答题记录详情',
                                style: theme.textTheme.headlineLarge?.copyWith(
                                  fontSize: AppFontSizes.detailTitle,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.title(context),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                '${record.mode == 'exam' ? '考试' : '练习'} · '
                                '${record.setTitle} · '
                                '${record.isBreakpoint ? '断点' : '已完成'} · '
                                '$_dateText',
                                style: TextStyle(
                                  fontSize: AppFontSizes.detailStat,
                                  color: AppColors.cardCaption(context),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              _SummaryCard(
                                answered: _answered,
                                targetCount: record.isBreakpoint
                                    ? record.targetCount
                                    : null,
                                correct: _correct,
                                scorePercent: _scorePercent,
                                examScore: record.mode == 'exam'
                                    ? record.score
                                    : null,
                                loading: _detailLoading,
                              ),
                              const SizedBox(height: AppSpacing.lg),
                              Text(
                                '薄弱点',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontSize: AppFontSizes.detailSectionTitle,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.title(context),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              _WeakPoints(
                                detail: _detail,
                                loading: _detailLoading,
                              ),
                              const SizedBox(height: AppSpacing.lg),
                              _PaperEntry(onTap: _openPaper),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  Positioned(
                    left: AppSpacing.md,
                    right: AppSpacing.md,
                    bottom: AppSpacing.md,
                    child: SizedBox(
                      width: double.infinity,
                      height: AppSizes.buttonHeight,
                      child: OutlinedButton(
                        onPressed: _deleting ? null : _confirmDelete,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: theme.colorScheme.error,
                          side: BorderSide(color: theme.colorScheme.error),
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
                        child: Text(_deleting ? '删除中…' : '删除记录'),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// 摘要卡：与前置页记录卡同风格（卡面填充 + 边框圆角）。
/// F27：服务端详情在途时数值列显示同高骨架，到达后淡入（标签列是静态
/// 文案，照常显示）；行高不变，无布局位移。
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.answered,
    required this.targetCount,
    required this.correct,
    required this.scorePercent,
    required this.examScore,
    this.loading = false,
  });

  final int answered;

  /// 断点记录显示 已答/目标；完成记录 null。
  final int? targetCount;
  final int? correct;
  final int? scorePercent;
  final int? examScore;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final answeredText = targetCount == null
        ? '$answered 题'
        : '$answered/$targetCount 题';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.cardSurface(context),
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.cardBorder(context)),
      ),
      child: Column(
        children: [
          _SummaryRow(label: '答题数', value: answeredText, loading: loading),
          const SizedBox(height: AppSpacing.xs),
          _SummaryRow(
            label: '答对',
            value: correct == null ? '--' : '$correct 题',
            loading: loading,
          ),
          const SizedBox(height: AppSpacing.xs),
          _SummaryRow(
            label: '正确率',
            value: scorePercent == null ? '--' : '$scorePercent%',
            valueColor: AppColors.success(context),
            loading: loading,
          ),
          if (examScore != null) ...[
            const SizedBox(height: AppSpacing.xs),
            _SummaryRow(label: '得分', value: '$examScore 分'),
          ],
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.loading = false,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: AppFontSizes.detailBody,
              color: AppColors.cardCaption(context),
            ),
          ),
        ),
        SkeletonToContent(
          loaded: !loading,
          skeleton: const LoadingSkeleton(
            height: AppFontSizes.detailBody,
            width: 56,
          ),
          child: Text(
            value,
            style: TextStyle(
              fontSize: AppFontSizes.detailBody,
              fontWeight: FontWeight.w600,
              color: valueColor ?? AppColors.title(context),
            ),
          ),
        ),
      ],
    );
  }
}

/// 薄弱点：服务端详情里答错最多的模块。没有详情显示“待接口”，
/// 全对显示明确的“没有薄弱点”，绝不虚构。
/// F27：详情在途时显示两行同字号骨架，到达后淡入（含“待接口”诚实态）。
class _WeakPoints extends StatelessWidget {
  const _WeakPoints({required this.detail, this.loading = false});

  final PracticeRecordDetail? detail;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final captionStyle = TextStyle(
      fontSize: AppFontSizes.detailStat,
      color: AppColors.cardCaption(context),
    );
    final detail = this.detail;
    final Widget content;
    if (detail == null) {
      content = Text('薄弱点待接口', style: captionStyle);
    } else if (detail.weakPoints.isEmpty) {
      content = Text('本次练习没有薄弱点', style: captionStyle);
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final point in detail.weakPoints) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    point.module.isEmpty
                        ? '全部模块'
                        : moduleLabel(point.module),
                    style: TextStyle(
                      fontSize: AppFontSizes.detailBody,
                      fontWeight: FontWeight.w600,
                      color: AppColors.title(context),
                    ),
                  ),
                ),
                Text(
                  '错 ${point.wrong}/${point.total} 题',
                  style: TextStyle(
                    fontSize: AppFontSizes.detailStat,
                    color: AppColors.warning(context),
                  ),
                ),
              ],
            ),
            if (point != detail.weakPoints.last)
              const SizedBox(height: AppSpacing.xs),
          ],
        ],
      );
    }
    return SkeletonToContent(
      loaded: !loading,
      skeleton: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LoadingSkeleton(height: AppFontSizes.detailBody, width: 180),
          SizedBox(height: AppSpacing.xs),
          LoadingSkeleton(height: AppFontSizes.detailStat, width: 120),
        ],
      ),
      child: content,
    );
  }
}

/// 查看试卷入口（Chunk 2b 装配试卷页，这里只接线路由）。
class _PaperEntry extends StatelessWidget {
  const _PaperEntry({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.card),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.cardSurface(context),
          borderRadius: BorderRadius.circular(AppRadii.card),
          border: Border.all(color: AppColors.cardBorder(context)),
        ),
        child: Row(
          children: [
            Icon(
              Icons.description_outlined,
              size: AppSizes.icon,
              color: AppColors.accent(context),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                '查看试卷',
                style: TextStyle(
                  fontSize: AppFontSizes.detailBody,
                  fontWeight: FontWeight.w600,
                  color: AppColors.title(context),
                ),
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: AppSizes.icon,
              color: AppColors.cardCaption(context),
            ),
          ],
        ),
      ),
    );
  }
}
