/// 答题记录卡（F19）：legend 缺口边框卡，前置页完整形态 / 答题页 compact。
///
/// 卡面透明无填充，边框复用 [DailyCardBorderPainter]（与首页每日一练 /
/// 错题本方块同一算法：标题坐在上边框缺口里）。高度 = 72 + 行数×56，
/// 下限 200、上限可视高 × [maxHeightFactor]；超过上限时卡内滚动。
library;

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/answer_record.dart';
import 'daily_card_border_painter.dart';

class AnswerRecordsCard extends StatelessWidget {
  const AnswerRecordsCard({
    super.key,
    required this.records,
    this.currentSummary,
    this.onContinue,
    this.maxHeightFactor = AppSizes.recordsCardMaxHeightFactor,
  });

  final List<AnswerRecord> records;

  /// 答题页「本次」摘要；前置页 null。
  final String? currentSummary;

  /// 前置页断点行「继续」；答题页 null。
  final VoidCallback? onContinue;

  final double maxHeightFactor;

  static const String title = '答题记录';

  static double _titleWidth() {
    final painter = TextPainter(
      text: const TextSpan(
        text: title,
        style: TextStyle(
          fontSize: AppFontSizes.dailyTitle,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return painter.width;
  }

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context).height;
    final configuredMax = viewport * maxHeightFactor;
    final maxH = configuredMax < AppSizes.recordsCardMinHeight
        ? AppSizes.recordsCardMinHeight
        : configuredMax;

    final hasContent = records.isNotEmpty || currentSummary != null;
    final target =
        72.0 +
        (currentSummary == null ? 0 : 36) +
        records.length * AppSizes.recordsRowHeight;
    final height = hasContent
        ? target.clamp(AppSizes.recordsCardMinHeight, maxH).toDouble()
        : AppSizes.recordsCardMinHeight;

    final width = _titleWidth();
    final body = Padding(
      padding: const EdgeInsets.fromLTRB(16, 26, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (currentSummary != null) ...[
            Text(
              currentSummary!,
              style: TextStyle(
                fontSize: AppFontSizes.detailStat,
                color: AppColors.cardCaption(context),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          Expanded(
            child: records.isEmpty
                ? Center(
                    child: Text(
                      '暂无答题记录',
                      style: TextStyle(
                        fontSize: AppFontSizes.detailBody,
                        color: AppColors.cardCaption(context),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: records.length,
                    separatorBuilder: (_, _) => Container(
                      height: AppSizes.divider,
                      color: AppColors.cardBorder(context),
                    ),
                    itemBuilder: (context, index) => _RecordRow(
                      record: records[index],
                      onContinue: onContinue,
                    ),
                  ),
          ),
        ],
      ),
    );

    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: DailyCardBorderPainter(
                color: AppColors.cardBorder(context),
                radius: AppRadii.card,
                gapStart: 20,
                gapEnd: 20 + width + 20,
              ),
            ),
          ),
          Positioned.fill(child: body),
          Positioned(
            top: -11,
            left: 20,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.dailyTitlePadH,
              ),
              child: Text(
                title,
                style: TextStyle(
                  fontSize: AppFontSizes.dailyTitle,
                  fontWeight: FontWeight.w800,
                  color: AppColors.cardTitle(context),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordRow extends StatelessWidget {
  const _RecordRow({required this.record, this.onContinue});

  final AnswerRecord record;
  final VoidCallback? onContinue;

  String get _kindLabel => record.isBreakpoint ? '断点' : '已完成';

  String get _dateText {
    final d = DateTime.fromMillisecondsSinceEpoch(record.updatedAt);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  String get _durationText {
    final total = record.durationMs ~/ 1000;
    final m = (total ~/ 60).toString().padLeft(2, '0');
    final s = (total % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final progress = record.targetCount <= 0
        ? 0.0
        : (record.answeredCount / record.targetCount).clamp(0.0, 1.0);
    final correct = record.correctCount;
    final right = record.isBreakpoint
        ? TextButton(
            onPressed: onContinue,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              '继续',
              style: TextStyle(
                fontSize: AppFontSizes.detailStat,
                color: AppColors.accent(context),
              ),
            ),
          )
        : Text(
            correct == null
                ? '--'
                : '正确率 ${(correct / (record.answeredCount == 0 ? 1 : record.answeredCount) * 100).round()}%',
            style: TextStyle(
              fontSize: AppFontSizes.detailStat,
              color: AppColors.success(context),
            ),
          );

    return SizedBox(
      height: AppSizes.recordsRowHeight,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '$_kindLabel · ${record.answeredCount}/${record.targetCount} 题',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppFontSizes.detailBody,
                    fontWeight: FontWeight.w600,
                    color: AppColors.title(context),
                  ),
                ),
              ),
              right,
            ],
          ),
          Text(
            '${record.mode == 'exam' ? '考试' : '练习'} · ${record.setTitle} · $_dateText · 用时 $_durationText',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: AppFontSizes.detailStat,
              color: AppColors.cardCaption(context),
            ),
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: Container(
              height: 3,
              color: AppColors.cardBorder(context),
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: progress,
                child: Container(color: AppColors.accent(context)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
