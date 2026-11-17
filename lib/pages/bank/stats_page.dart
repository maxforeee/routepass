/// 学习统计页（规格文档第 4 章 StatsService；首页 H-B11 的目标页）。
///
/// F26：登录且在线时显示真实后端数据（GET /stats/overview + /stats/daily）；
/// 未登录 / 离线回落 Mock（全 0 / 空列表），显示 0 与“暂无数据”，不编造数字。
/// 后端 byModule 不提供模块题目总数，模块卡只展示“已答 N 题”与正确率。
/// F27：加载中显示与内容同构的骨架（不再用居中进度圈），数据到达淡入。
/// F29：加载失败显示错误 + 重试（诚实态），不再把失败折叠成 0 / “暂无数据”。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_animations.dart';
import '../../core/service_locator.dart';
import '../../core/theme.dart';
import '../../models/stats.dart';
import '../../services/bank/stats_service.dart';
import '../../widgets/loading_skeleton.dart';

class StatsPage extends StatefulWidget {
  const StatsPage({super.key, this.statsService});

  /// 测试可注入；生产环境不传，走 ServiceLocator 里的实现。
  final StatsService? statsService;

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  bool _loading = true;
  bool _failed = false;
  StatsOverview? _overview;
  List<ModuleStat> _byModule = const <ModuleStat>[];
  List<DailyStats> _daily = const <DailyStats>[];

  late final StatsService _statsService;

  @override
  void initState() {
    super.initState();
    _statsService = widget.statsService ?? ServiceLocator.statsService;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      // getDaily 与 getOverview 并行；getByModule 复用 getOverview  warmed
      // 的派生缓存（后端无独立 by-module 接口），保持在 getOverview 之后，
      // 不额外多发一次 overview 请求。
      final (overview, daily) = await (
        _statsService.getOverview(),
        _statsService.getDaily(),
      ).wait;
      final byModule = await _statsService.getByModule();
      if (!mounted) return;
      setState(() {
        _overview = overview;
        _byModule = byModule;
        _daily = daily;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  String _moduleLabel(String module) => module == 'SUBNET' ? '子网' : module;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('学习统计')),
      body: SkeletonToContent(
        loaded: !_loading,
        skeleton: const _StatsSkeleton(),
        child: _failed ? _buildErrorState(theme) : _buildContent(theme),
      ),
    );
  }

  /// F29：加载失败的诚实态——错误提示 + 重试（同题库页清单失败的做法），
  /// 绝不渲染伪造的 0 / “暂无数据”。
  Widget _buildErrorState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: AppSizes.emptyStateIcon,
            color: AppColors.cardCaption(context),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text('统计加载失败', style: theme.textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton(onPressed: _load, child: const Text('重试')),
        ],
      ),
    );
  }

  Widget _buildContent(ThemeData theme) {
    final ov = _overview;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('总览', style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                _StatRow(
                  label: '累计答题',
                  value: '${ov?.answeredTotal ?? 0} 题',
                ),
                _StatRow(
                  label: '总正确率',
                  value: ov == null || ov.answeredTotal == 0
                      ? '暂无数据'
                      : '${(ov.correctRate * 100).toStringAsFixed(1)}%',
                ),
                _StatRow(
                  label: '连续学习',
                  value: '${ov?.streakDays ?? 0} 天',
                ),
                _StatRow(
                  label: '今日答题',
                  value:
                      '${ov?.todayAnswered ?? 0} 题 · 答对 ${ov?.todayCorrect ?? 0} 题',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('按模块', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (_byModule.isEmpty)
          Text(
            '暂无数据',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          ..._byModule.indexed.map((entry) {
            final (index, m) = entry;
            // 后端不提供模块题目总数（total 恒 0）：进度条展示正确率，
            // 计数只写“已答 N 题”，绝不拿 answered 冒充 answered/total。
            final progress = m.correctRate;
            // F29：骨架 → 内容切换保留文档约定的交错入场（同题库页）。
            return StaggeredListAppear(
              index: index,
              slideOffsetDp: StaggeredListAppear.listSlideOffsetDp,
              child: Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _moduleLabel(m.module),
                              style: theme.textTheme.titleSmall,
                            ),
                          ),
                          Text(
                            '已答 ${m.answered} 题',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(value: progress),
                      const SizedBox(height: 4),
                      Text(
                        m.answered == 0
                            ? '暂无数据'
                            : '正确率 ${(m.correctRate * 100).toStringAsFixed(1)}%',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        const SizedBox(height: 16),
        Text('每日记录', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (_daily.isEmpty)
          Text(
            '暂无数据',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          ..._daily.indexed.map((entry) {
            final (index, d) = entry;
            return StaggeredListAppear(
              index: index,
              slideOffsetDp: StaggeredListAppear.listSlideOffsetDp,
              child: Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(d.stat_date),
                  subtitle: Text(
                    '答题 ${d.answered} · 答对 ${d.correct} · 用时 ${d.duration_sec ~/ 60} 分钟',
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// F27：统计页骨架——与真实内容同一 padding / 卡片结构：
/// 总览卡（标题 + 4 行统计）、按模块（2 张模块卡）、每日记录（2 条）。
/// F29：行高按默认文字缩放下的真实行盒近似占位——标题 titleMedium
/// 18sp × 1.4 ≈ 25px 取 24，统计行 bodyMedium 16sp × 1.5 = 24px（加上下
/// 各 4 padding 与真实 _StatRow 的 32px 一致）；每日卡按 ListTile 最小
/// 高度 72 占位。大字号缩放下真实内容会更高，仍可能有少量位移，
/// 不做逐像素承诺。
class _StatsSkeleton extends StatelessWidget {
  const _StatsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const LoadingSkeleton(height: 24, width: 60),
                const SizedBox(height: 12),
                for (var i = 0; i < 4; i++)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 88,
                          child: LoadingSkeleton(height: 24, width: 64),
                        ),
                        Expanded(child: LoadingSkeleton(height: 24)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const LoadingSkeleton(height: 24, width: 60),
        const SizedBox(height: 8),
        for (var i = 0; i < 2; i++)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Row(
                    children: [
                      Expanded(child: LoadingSkeleton(height: 24, width: 80)),
                      LoadingSkeleton(height: 24, width: 60),
                    ],
                  ),
                  SizedBox(height: 8),
                  LoadingSkeleton(height: 4),
                  SizedBox(height: 4),
                  LoadingSkeleton(height: 18, width: 100),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        const LoadingSkeleton(height: 24, width: 80),
        const SizedBox(height: 8),
        for (var i = 0; i < 2; i++)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: SizedBox(
              height: 72,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    LoadingSkeleton(height: 16, width: 120),
                    SizedBox(height: 4),
                    LoadingSkeleton(height: 12, width: 200),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
