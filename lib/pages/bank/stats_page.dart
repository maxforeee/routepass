/// 学习统计页（规格文档第 4 章 StatsService；首页 H-B11 的目标页）。
///
/// F26：登录且在线时显示真实后端数据（GET /stats/overview + /stats/daily）；
/// 未登录 / 离线回落 Mock（全 0 / 空列表），显示 0 与“暂无数据”，不编造数字。
/// 后端 byModule 不提供模块题目总数，模块卡只展示“已答 N 题”与正确率。
/// F27：加载中显示与内容同构的骨架（不再用居中进度圈），数据到达淡入；
/// 失败保留原有 0 / “暂无数据”兜底（诚实态）。
library;

import 'package:flutter/material.dart';

import '../../core/service_locator.dart';
import '../../models/stats.dart';
import '../../widgets/loading_skeleton.dart';

class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  bool _loading = true;
  StatsOverview? _overview;
  List<ModuleStat> _byModule = const <ModuleStat>[];
  List<DailyStats> _daily = const <DailyStats>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final overview = await ServiceLocator.statsService.getOverview();
      final byModule = await ServiceLocator.statsService.getByModule();
      final daily = await ServiceLocator.statsService.getDaily();
      if (!mounted) return;
      setState(() {
        _overview = overview;
        _byModule = byModule;
        _daily = daily;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  String _moduleLabel(String module) => module == 'SUBNET' ? '子网' : module;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ov = _overview;
    return Scaffold(
      appBar: AppBar(title: const Text('学习统计')),
      body: SkeletonToContent(
        loaded: !_loading,
        skeleton: const _StatsSkeleton(),
        child: ListView(
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
              ..._byModule.map((m) {
                // 后端不提供模块题目总数（total 恒 0）：进度条展示正确率，
                // 计数只写“已答 N 题”，绝不拿 answered 冒充 answered/total。
                final progress = m.correctRate;
                return Card(
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
              ..._daily.map((d) {
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(d.stat_date),
                    subtitle: Text(
                      '答题 ${d.answered} · 答对 ${d.correct} · 用时 ${d.duration_sec ~/ 60} 分钟',
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
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

/// F27：统计页骨架——与真实内容同一 padding / 卡片结构 / 行高：
/// 总览卡（标题 + 4 行统计）、按模块（2 张模块卡）、每日记录（2 条）。
/// 行高按对应文字样式的字号占位，内容到达时不产生纵向位移。
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
                const LoadingSkeleton(height: 16, width: 60),
                const SizedBox(height: 12),
                for (var i = 0; i < 4; i++)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 88,
                          child: LoadingSkeleton(height: 14, width: 64),
                        ),
                        Expanded(child: LoadingSkeleton(height: 14)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const LoadingSkeleton(height: 16, width: 60),
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
                      Expanded(child: LoadingSkeleton(height: 14, width: 80)),
                      LoadingSkeleton(height: 14, width: 60),
                    ],
                  ),
                  SizedBox(height: 8),
                  LoadingSkeleton(height: 4),
                  SizedBox(height: 4),
                  LoadingSkeleton(height: 12, width: 100),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        const LoadingSkeleton(height: 16, width: 80),
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
