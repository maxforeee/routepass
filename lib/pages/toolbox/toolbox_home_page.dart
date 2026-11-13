import 'package:flutter/material.dart';

import '../../core/kv_store.dart';
import '../../core/service_locator.dart';
import '../../core/theme.dart';
import '../../widgets/app_card.dart';
import '../../widgets/page_header.dart';
import 'toolbox_tools.dart';

class ToolboxHomePage extends StatefulWidget {
  const ToolboxHomePage({super.key});

  @override
  State<ToolboxHomePage> createState() => ToolboxHomePageState();
}

class ToolboxHomePageState extends State<ToolboxHomePage> {
  /// tab 切回时刷新（最近使用行重读 kv）。
  void refresh() {
    setState(() {});
  }

  List<ToolboxTool> get _recent {
    final ids =
        ServiceLocator.kvStore.getStringList(KvStore.keyToolboxRecent) ??
        const <String>[];
    final byId = <String, ToolboxTool>{for (final t in toolboxTools) t.id: t};
    return [
      for (final id in ids)
        if (byId.containsKey(id)) byId[id]!,
    ];
  }

  // 打开工具页；返回后重读 kv 刷新最近使用行（Tab Navigator 保留路由，
  // AppShell 的 setState 不会重建本页，只能在 await 返回后自己刷新）。
  Future<void> _openTool(ToolboxTool tool) async {
    await Navigator.of(context).pushNamed(tool.route);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final recent = _recent;
    return Scaffold(
      backgroundColor: AppColors.pageBackground(context),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSizes.contentMaxWidth,
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSizes.homeBottomPad,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const PageHeader(title: '工具箱', subtitle: '网工常用小工具 · 全部本地运行'),
                  const SizedBox(height: AppSpacing.md),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: AppSpacing.md,
                          crossAxisSpacing: AppSpacing.md,
                          mainAxisExtent: AppSizes.toolboxCardHeight,
                        ),
                    itemCount: toolboxTools.length,
                    itemBuilder: (context, index) {
                      final tool = toolboxTools[index];
                      return _ToolCard(
                        tool: tool,
                        onTap: () => _openTool(tool),
                      );
                    },
                  ),
                  if (recent.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.md),
                    _RecentRow(recent: recent),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({required this.tool, required this.onTap});

  final ToolboxTool tool;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            tool.icon,
            size: AppSizes.toolIconSize,
            color: toolIconColor(tool.iconTone, context),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            tool.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              fontSize: AppFontSizes.toolCardTitle,
              fontWeight: FontWeight.bold,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            tool.desc,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _RecentRow extends StatelessWidget {
  const _RecentRow({required this.recent});

  final List<ToolboxTool> recent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final names = recent.map((t) => t.name).join(' · ');
    return Row(
      children: [
        Text(
          '最近使用',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            names,
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
