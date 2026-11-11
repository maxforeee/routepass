/// 首页 tab 内容（从 M0 的 HomePage 里抽出的 _HomeContentPage，T3 将按 §22.4 重做为 12 方块瀑布流）。
library;

import 'package:flutter/material.dart';

import '../../core/app_snackbar.dart';
import '../../core/config.dart';
import '../../widgets/account_sheet.dart';

class HomeContentPage extends StatelessWidget {
  const HomeContentPage({super.key, required this.onSelectTab});

  final void Function(int index) onSelectTab;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('RoutePass'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: IconButton(
              onPressed: () => showAccountSheet(context),
              icon: const CircleAvatar(
                radius: 16,
                child: Icon(Icons.person, size: 18),
              ),
              tooltip: '账户',
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '欢迎回来',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'M0 演示外壳：题库、知识库与工具箱将在后续版本上线。',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          _buildSummaryCard(theme),
          const SizedBox(height: 16),
          _buildEntryCard(
            context,
            theme,
            icon: Icons.quiz_outlined,
            title: '题库',
            subtitle: '章节练习、真题与错题，V2 上线',
            onTap: () => onSelectTab(1),
          ),
          _buildEntryCard(
            context,
            theme,
            icon: Icons.menu_book_outlined,
            title: '知识库',
            subtitle: '网络工程知识点速查，V3 上线',
            onTap: () => onSelectTab(2),
          ),
          _buildEntryCard(
            context,
            theme,
            icon: Icons.build_outlined,
            title: '工具箱',
            subtitle: '子网计算等常用小工具，V4 上线',
            onTap: () => onSelectTab(3),
          ),
          _buildEntryCard(
            context,
            theme,
            icon: Icons.timer_outlined,
            title: '模拟考试',
            subtitle: '限时模拟与成绩分析',
            onTap: () => _showComingSoonSnack(context),
          ),
          _buildEntryCard(
            context,
            theme,
            icon: Icons.error_outline,
            title: '错题本',
            subtitle: '自动收集错题并安排复习',
            onTap: () => _showComingSoonSnack(context),
          ),
          _buildEntryCard(
            context,
            theme,
            icon: Icons.star_outline,
            title: '收藏',
            subtitle: '收藏题目与知识点',
            onTap: () => _showComingSoonSnack(context),
          ),
          _buildEntryCard(
            context,
            theme,
            icon: Icons.insights_outlined,
            title: '学习统计',
            subtitle: '练习量与正确率趋势',
            onTap: () => _showComingSoonSnack(context),
          ),
          const SizedBox(height: 24),
          Text(
            '${AppConfig.versionLabel} (demo)',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.today_outlined,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text('今日摘要', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            const _SummaryRow(label: '今日已练', unit: '题', value: 0),
            const SizedBox(height: 8),
            const _SummaryRow(label: '连续打卡', unit: '天', value: 0),
            const SizedBox(height: 8),
            const _SummaryRow(label: '错题待复习', unit: '道', value: 0),
          ],
        ),
      ),
    );
  }

  Widget _buildEntryCard(
    BuildContext context,
    ThemeData theme, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(icon, color: theme.colorScheme.primary),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  void _showComingSoonSnack(BuildContext context) {
    showAppSnackBar(context, '该功能随 V2 题库一起上线');
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.unit,
    required this.value,
  });

  final String label;
  final String unit;
  final int value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const Spacer(),
        Text(
          '$value $unit',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
