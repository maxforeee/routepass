/// F25 Chunk 4：考试交卷后的全屏评分页。
///
/// 取代旧半屏结果 sheet：得分 / 用时 / 答错数 + 全部错题逐条列出
/// （题干、你的答案 vs 正确答案、解析、「加入错题本」）。退出按钮固定在
/// 页面底部，不随错题列表滚动——错题再多也不用滚到底才能退出。
///
/// 错题判定口径与回顾页一致：服务端判分（grading）优先，correct 非 false
/// 不列；无判分明细时只用题目自带答案键判，答案键为空不猜对错。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_snackbar.dart';
import '../../core/service_locator.dart';
import '../../core/theme.dart';
import '../../models/question.dart';
import '../../services/bank/exam_service.dart';
import '../../services/bank/wrong_service.dart';
import 'answer_widgets.dart';

class ExamScorePage extends StatefulWidget {
  const ExamScorePage({
    super.key,
    required this.total,
    required this.answered,
    required this.elapsed,
    required this.score,
    this.detail = '',
    required this.questions,
    required this.answers,
    this.grading = const <String, ExamQuestionGrade>{},
    this.loadGrading,
    this.wrongService,
    required this.onReview,
  });

  final int total;
  final int answered;
  final Duration elapsed;

  /// 服务端得分；null 显示「样例考试，不计分」，绝不编造分数。
  final int? score;
  final String detail;
  final List<Question> questions;
  final Map<String, List<String>> answers;

  /// 进页时已有的判分明细（通常为空，由 [loadGrading] 后台补齐）。
  final Map<String, ExamQuestionGrade> grading;

  /// 后台拉取判分明细：不阻塞页面渲染，返回后刷新错题列表。
  final Future<Map<String, ExamQuestionGrade>> Function()? loadGrading;

  /// 测试可注入；生产环境不传，走 ServiceLocator。
  final WrongService? wrongService;

  /// 进入逐题回顾：本页先 pop（不带退出结果），再按题目下标回调。
  final void Function(int index) onReview;

  @override
  State<ExamScorePage> createState() => _ExamScorePageState();
}

class _ExamScorePageState extends State<ExamScorePage> {
  late Map<String, ExamQuestionGrade> _grading;
  final Set<String> _addedIds = <String>{};
  final Set<String> _addingIds = <String>{};

  /// 错题本服务延迟到点「加入错题本」时才解析：只搭考试流程、没注册
  /// wrongService 的装配也必须能渲染评分页，不能进页就崩。
  WrongService get _wrong => widget.wrongService ?? ServiceLocator.wrongService;

  @override
  void initState() {
    super.initState();
    _grading = Map<String, ExamQuestionGrade>.of(widget.grading);
    final loader = widget.loadGrading;
    if (loader != null) {
      unawaited(
        loader()
            .then((grading) {
              if (!mounted || grading.isEmpty) return;
              setState(() => _grading = grading);
            })
            .catchError((_) {}),
      );
    }
  }

  /// 是否有任何判分依据（服务端 correct 或题目自带答案键）。没有依据时
  /// 不显示「答错 0 题」——那是编造，只能明说明细未下发。
  bool get _hasBasis =>
      _grading.values.any((g) => g.correct != null) ||
      widget.questions.any((q) => q.answer.isNotEmpty);

  List<_WrongEntry> get _wrongEntries {
    final entries = <_WrongEntry>[];
    for (var i = 0; i < widget.questions.length; i++) {
      final q = widget.questions[i];
      final grade = _grading[q.id];
      final saved = widget.answers[q.id] ?? const <String>[];
      final chosen = grade != null && grade.chosen.isNotEmpty
          ? grade.chosen
          : saved;
      if (grade != null) {
        if (grade.correct != false) continue;
        final keys = grade.answer.isNotEmpty ? grade.answer : q.answer;
        entries.add(
          _WrongEntry(
            index: i,
            question: q,
            chosen: chosen,
            correctKeys: keys,
            explanation: _explanation(grade.explanation, q),
          ),
        );
      } else {
        if (q.answer.isEmpty || _sameKeys(chosen, q.answer)) continue;
        entries.add(
          _WrongEntry(
            index: i,
            question: q,
            chosen: chosen,
            correctKeys: q.answer,
            explanation: _explanation('', q),
          ),
        );
      }
    }
    return entries;
  }

  String _explanation(String remote, Question q) {
    if (remote.isNotEmpty) return remote;
    return q.explanation.isEmpty ? '解析待接口' : q.explanation;
  }

  bool _sameKeys(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    final sortedA = List<String>.of(a)..sort();
    final sortedB = List<String>.of(b)..sort();
    for (var i = 0; i < sortedA.length; i++) {
      if (sortedA[i] != sortedB[i]) return false;
    }
    return true;
  }

  Future<void> _addWrong(_WrongEntry entry) async {
    final id = entry.question.id;
    if (_addedIds.contains(id) || _addingIds.contains(id)) return;
    setState(() => _addingIds.add(id));
    try {
      await _wrong.addWrong(id);
      if (!mounted) return;
      setState(() {
        _addingIds.remove(id);
        _addedIds.add(id);
      });
      showAppSnackBar(context, '已加入错题本');
    } catch (_) {
      if (!mounted) return;
      setState(() => _addingIds.remove(id));
      showAppSnackBar(context, '加入失败，请重试');
    }
  }

  void _exit() {
    Navigator.of(context).pop(true);
  }

  void _review(int index) {
    Navigator.of(context).pop();
    widget.onReview(index);
  }

  String get _elapsedText {
    final m = widget.elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = widget.elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final wrong = _wrongEntries;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exit();
      },
      child: Scaffold(
        backgroundColor: AppColors.pageBackground(context),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  children: [
                    _buildHeader(wrong),
                    const SizedBox(height: AppSpacing.md),
                    for (final entry in wrong) _buildWrongCard(entry),
                  ],
                ),
              ),
              // 退出固定底部：在滚动区之外，错题列表多长都始终可见。
              Container(
                height: AppSizes.divider,
                color: AppColors.cardBorder(context),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.md,
                  AppSpacing.md,
                ),
                child: SizedBox(
                  width: double.infinity,
                  height: AppSizes.buttonHeight,
                  child: FilledButton(
                    onPressed: _exit,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent(context),
                      foregroundColor: AppColors.brandSurface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppRadii.setDetailStartButton,
                        ),
                      ),
                    ),
                    child: const Text('退出'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(List<_WrongEntry> wrong) {
    final String wrongLine;
    final Color wrongColor;
    if (!_hasBasis) {
      wrongLine = '判分明细未下发，暂无法列出错题';
      wrongColor = AppColors.cardCaption(context);
    } else if (wrong.isEmpty) {
      wrongLine = '全部答对，没有错题';
      wrongColor = AppColors.success(context);
    } else {
      wrongLine = '答错 ${wrong.length} 题';
      wrongColor = AppColors.wrongIconForeground(context);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '考试结果',
                style: TextStyle(
                  fontSize: AppFontSizes.detailSectionTitle,
                  fontWeight: FontWeight.w700,
                  color: AppColors.title(context),
                ),
              ),
            ),
            TextButton(onPressed: () => _review(0), child: const Text('逐题回顾')),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (widget.score != null)
          Text(
            '${widget.score} 分',
            style: TextStyle(
              fontSize: AppFontSizes.detailTitle,
              fontWeight: FontWeight.w700,
              color: AppColors.accent(context),
            ),
          )
        else
          Text(
            '样例考试，不计分',
            style: TextStyle(
              fontSize: AppFontSizes.detailSectionTitle,
              color: AppColors.title(context),
            ),
          ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '用时 $_elapsedText · 已答 ${widget.answered}/${widget.total} 题',
          style: TextStyle(
            fontSize: AppFontSizes.detailStat,
            color: AppColors.cardCaption(context),
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          wrongLine,
          style: TextStyle(
            fontSize: AppFontSizes.detailBody,
            fontWeight: FontWeight.w600,
            color: wrongColor,
          ),
        ),
        if (widget.detail.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            widget.detail,
            style: TextStyle(
              fontSize: AppFontSizes.detailStat,
              color: AppColors.cardCaption(context),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildWrongCard(_WrongEntry entry) {
    final q = entry.question;
    final added = _addedIds.contains(q.id);
    final adding = _addingIds.contains(q.id);
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
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
              Expanded(
                child: Text(
                  '第 ${entry.index + 1} 题 · ${questionTypeLabel(q.type)}',
                  style: TextStyle(
                    fontSize: AppFontSizes.detailStat,
                    fontWeight: FontWeight.w600,
                    color: AppColors.cardCaption(context),
                  ),
                ),
              ),
              TextButton(
                onPressed: () => _review(entry.index),
                child: const Text('查看'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            q.stem,
            style: TextStyle(
              fontSize: AppFontSizes.detailBody,
              height: 1.5,
              color: AppColors.title(context),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '你的答案：${entry.chosen.isEmpty ? '未作答' : entry.chosen.join('、')}',
            style: TextStyle(
              fontSize: AppFontSizes.detailBody,
              color: AppColors.wrongIconForeground(context),
            ),
          ),
          if (entry.correctKeys.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              '正确答案：${entry.correctKeys.join('、')}',
              style: TextStyle(
                fontSize: AppFontSizes.detailBody,
                fontWeight: FontWeight.w600,
                color: AppColors.success(context),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          Text(
            entry.explanation,
            style: TextStyle(
              fontSize: AppFontSizes.detailStat,
              height: 1.5,
              color: AppColors.cardCaption(context),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: added || adding ? null : () => _addWrong(entry),
              icon: Icon(
                added ? Icons.check : Icons.playlist_add,
                size: AppSizes.icon,
              ),
              label: Text(added ? '已加入错题本' : '加入错题本'),
            ),
          ),
        ],
      ),
    );
  }
}

class _WrongEntry {
  const _WrongEntry({
    required this.index,
    required this.question,
    required this.chosen,
    required this.correctKeys,
    required this.explanation,
  });

  final int index;
  final Question question;
  final List<String> chosen;
  final List<String> correctKeys;
  final String explanation;
}
