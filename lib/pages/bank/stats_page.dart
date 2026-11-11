/// 学习统计页（规格文档第 4 章 StatsService；首页 H-B11 的目标页）。
///
/// Mock 下统计全 0、按模块全 0、每日列表为空，显示 0 与“暂无数据”，不编造数字。
library;

import 'package:flutter/material.dart';

import '../../core/service_locator.dart';
import '../../models/stats.dart';

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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
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
                              : '${(ov.correctRate * 100).round()}%',
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
                    final progress =
                        m.total == 0 ? 0.0 : m.answered / m.total;
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
                                  '${m.answered}/${m.total} 题',
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
                                  : '正确率 ${(m.correctRate * 100).round()}%',
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
          Expanded(
            child: Text(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
