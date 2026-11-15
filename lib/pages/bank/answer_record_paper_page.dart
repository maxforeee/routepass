/// 答题记录试卷页（F25 Chunk 2b）。
///
/// 详情页「查看试卷」进入：只读逐题回顾——题目、选项、用户所选、正确答案、
/// 对错标记与解析，全部来自 `GET /practice/records/{id}/paper` 的真实
/// attempts 数据。不可作答；未登录 / 离线显示重试，空记录显示空态，绝不编题。
library;

import 'package:flutter/material.dart';

import '../../core/service_locator.dart';
import '../../core/theme.dart';
import '../../models/answer_record.dart';
import '../../models/practice.dart';
import '../../services/bank/practice_service.dart';
import 'answer_widgets.dart';

class AnswerRecordPaperPage extends StatefulWidget {
  const AnswerRecordPaperPage({
    super.key,
    required this.args,
    this.practiceService,
  });

  /// 路由参数：`{'record': AnswerRecord?, 'sessionId': String}`（2a 入口约定）。
  final Map<String, Object?> args;

  /// 测试可注入；生产环境不传，走 ServiceLocator 里的实现。
  final PracticeService? practiceService;

  @override
  State<AnswerRecordPaperPage> createState() => _AnswerRecordPaperPageState();
}

class _AnswerRecordPaperPageState extends State<AnswerRecordPaperPage> {
  PracticeRecordPaper? _paper;
  bool _loading = true;
  bool _failed = false;

  late final PracticeService _practiceService;

  AnswerRecord? get _record {
    final record = widget.args['record'];
    return record is AnswerRecord ? record : null;
  }

  String get _sessionId {
    final id = widget.args['sessionId'];
    if (id is String && id.isNotEmpty) return id;
    return _record?.serverId ?? '';
  }

  @override
  void initState() {
    super.initState();
    _practiceService = widget.practiceService ?? ServiceLocator.practiceService;
    _load();
  }

  Future<void> _load() async {
    final sessionId = _sessionId;
    if (sessionId.isEmpty) {
      setState(() {
        _loading = false;
        _failed = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _failed = false;
    });
    PracticeRecordPaper? paper;
    try {
      paper = await _practiceService.getRecordPaper(sessionId);
    } catch (_) {
      // 离线 / 未登录：显示重试态，不抛给 UI。
      paper = null;
    }
    if (!mounted) return;
    setState(() {
      _paper = paper;
      _loading = false;
      _failed = paper == null;
    });
  }

  String get _subtitle {
    final paper = _paper;
    if (paper != null) {
      final correct = paper.items.where((item) => item.correct).length;
      return '共 ${paper.items.length} 题 · 答对 $correct 题';
    }
    final record = _record;
    if (record == null) return '';
    return '${record.mode == 'exam' ? '考试' : '练习'} · ${record.setTitle}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '试卷回顾',
                    style: theme.textTheme.headlineLarge?.copyWith(
                      fontSize: AppFontSizes.detailTitle,
                      fontWeight: FontWeight.w800,
                      color: AppColors.title(context),
                    ),
                  ),
                  if (_subtitle.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      _subtitle,
                      style: TextStyle(
                        fontSize: AppFontSizes.detailStat,
                        color: AppColors.cardCaption(context),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_sessionId.isEmpty) {
      return _emptyState(
        icon: Icons.description_outlined,
        title: '暂无试卷',
        caption: '该记录未同步到服务端，无法查看试卷。',
      );
    }
    if (_failed) {
      return _emptyState(
        icon: Icons.cloud_off,
        title: '试卷加载失败',
        caption: '请检查网络或登录后重试。',
        action: FilledButton(onPressed: _load, child: const Text('重试')),
      );
    }
    final items = _paper?.items ?? const <PracticePaperItem>[];
    if (items.isEmpty) {
      return _emptyState(
        icon: Icons.description_outlined,
        title: '这条记录没有已作答的题目',
        caption: '完成作答后即可查看试卷。',
      );
    }
    // 与答题页回顾同一做法：整卷一次性构建（记录最多 20 题），滚动浏览。
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.md,
      ),
      children: [
        for (var i = 0; i < items.length; i++)
          _PaperQuestionCard(index: i, item: items[i]),
      ],
    );
  }

  Widget _emptyState({
    required IconData icon,
    required String title,
    String? caption,
    Widget? action,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: AppSizes.iconLarge,
              color: AppColors.cardCaption(context),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppFontSizes.detailBody,
                fontWeight: FontWeight.w600,
                color: AppColors.title(context),
              ),
            ),
            if (caption != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                caption,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: AppFontSizes.detailStat,
                  color: AppColors.cardCaption(context),
                ),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: AppSpacing.md),
              action,
            ],
          ],
        ),
      ),
    );
  }
}

/// 单题回顾卡：题号 + 题型 + 对错标记、题干、选项（判分配色）、解析卡。
/// 选项状态与考试回顾同一规则：正确答案标绿，用户错选标红，其余不着色。
class _PaperQuestionCard extends StatelessWidget {
  const _PaperQuestionCard({required this.index, required this.item});

  final int index;
  final PracticePaperItem item;

  OptionTileState _optionState(String key) {
    if (item.question.answer.contains(key)) return OptionTileState.correct;
    if (item.chosen.contains(key)) return OptionTileState.wrong;
    return OptionTileState.idle;
  }

  @override
  Widget build(BuildContext context) {
    final q = item.question;
    final verdictColor = item.correct
        ? AppColors.success(context)
        : AppColors.wrongIconForeground(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.cardSurface(context),
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.cardBorder(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '第 ${index + 1} 题',
                style: TextStyle(
                  fontSize: AppFontSizes.detailBody,
                  fontWeight: FontWeight.w600,
                  color: AppColors.title(context),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                questionTypeLabel(q.type),
                style: TextStyle(
                  fontSize: AppFontSizes.detailStat,
                  color: AppColors.cardCaption(context),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: item.correct
                      ? AppColors.dailyCorrectBackground(context)
                      : AppColors.wrongIconBackground(context),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  item.correct ? '答对' : '答错',
                  style: TextStyle(
                    fontSize: AppFontSizes.detailStat,
                    fontWeight: FontWeight.w600,
                    color: verdictColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SelectableText(
            q.stem,
            style: TextStyle(
              fontSize: AppFontSizes.detailBody + 1,
              height: 1.6,
              color: AppColors.title(context),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          for (final option in q.options)
            OptionTile(
              option: option,
              selected: item.chosen.contains(option.key),
              multiple: q.type == 'multiple',
              state: _optionState(option.key),
              // 只读回顾，不可作答。
              onTap: () {},
            ),
          AnalysisCard(
            question: q,
            result: AnswerResult(
              correct: item.correct,
              explanation: item.explanation.isEmpty
                  ? '解析待接口'
                  : item.explanation,
              correctKeys: q.answer,
            ),
            chosen: item.chosen,
            sampleData: false,
          ),
        ],
      ),
    );
  }
}
