import 'package:flutter/material.dart';

import '../../core/config.dart';
import '../../router/app_router.dart';
import '../bank/module_list_page.dart';
import '../knowledge/knowledge_home_page.dart';
import '../toolbox/toolbox_home_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;

  static const List<Widget> _tabs = <Widget>[
    _HomeContentPage(),
    BankModuleListPage(),
    KnowledgeHomePage(),
    ToolboxHomePage(),
  ];

  void _selectTab(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  void _openAccountSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: const Text('设置'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  Navigator.of(context).pushNamed(AppRoutes.settings);
                },
              ),
              ListTile(
                leading: const Icon(Icons.cloud_sync_outlined),
                title: const Text('账户与同步'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  Navigator.of(context).pushNamed(AppRoutes.profile);
                },
              ),
              ListTile(
                enabled: false,
                leading: const Icon(Icons.info_outline),
                title: Text(AppConfig.versionLabel),
                subtitle: const Text('演示版本'),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _selectTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '首页',
          ),
          NavigationDestination(
            icon: Icon(Icons.quiz_outlined),
            selectedIcon: Icon(Icons.quiz),
            label: '题库',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book),
            label: '知识库',
          ),
          NavigationDestination(
            icon: Icon(Icons.build_outlined),
            selectedIcon: Icon(Icons.build),
            label: '工具箱',
          ),
        ],
      ),
    );
  }
}

class _HomeContentPage extends StatelessWidget {
  const _HomeContentPage();

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
              onPressed: () => _HomeContentPage.openAccountSheet(context),
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
            onTap: () => _switchTab(context, 1),
          ),
          _buildEntryCard(
            context,
            theme,
            icon: Icons.menu_book_outlined,
            title: '知识库',
            subtitle: '网络工程知识点速查，V3 上线',
            onTap: () => _switchTab(context, 2),
          ),
          _buildEntryCard(
            context,
            theme,
            icon: Icons.build_outlined,
            title: '工具箱',
            subtitle: '子网计算等常用小工具，V4 上线',
            onTap: () => _switchTab(context, 3),
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

  void _switchTab(BuildContext context, int index) {
    final state = context.findAncestorStateOfType<_HomePageState>();
    state?._selectTab(index);
  }

  void _showComingSoonSnack(BuildContext context) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('该功能随 V2 题库一起上线')));
  }

  static void openAccountSheet(BuildContext context) {
    final state = context.findAncestorStateOfType<_HomePageState>();
    state?._openAccountSheet();
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
