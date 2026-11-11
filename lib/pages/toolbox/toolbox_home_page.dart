import 'package:flutter/material.dart';

import '../../core/kv_store.dart';
import '../../core/service_locator.dart';
import 'toolbox_tools.dart';

class ToolboxHomePage extends StatefulWidget {
  const ToolboxHomePage({super.key});

  @override
  State<ToolboxHomePage> createState() => _ToolboxHomePageState();
}

class _ToolboxHomePageState extends State<ToolboxHomePage> {
  String _query = '';
  ToolCategory? _category; // null = 全部
  final _searchController = TextEditingController();

  List<ToolboxTool> get _filtered {
    return toolboxTools.where((t) {
      if (_category != null && t.category != _category) return false;
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return t.name.toLowerCase().contains(q) ||
          t.desc.toLowerCase().contains(q);
    }).toList();
  }

  List<ToolboxTool> get _recent {
    final ids =
        ServiceLocator.kvStore.getStringList(KvStore.keyToolboxRecent) ??
            const <String>[];
    final byId = <String, ToolboxTool>{
      for (final t in toolboxTools) t.id: t,
    };
    return [for (final id in ids) if (byId.containsKey(id)) byId[id]!];
  }

  void _openTool(ToolboxTool tool) {
    Navigator.of(context).pushNamed(tool.route);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final recent = _recent;
    return Scaffold(
      appBar: AppBar(title: const Text('工具箱')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: '搜索工具',
                prefixIcon: Icon(Icons.search),
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
              ),
              onChanged: (v) => setState(() => _query = v.trim()),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _CategoryChip(
                  label: '全部',
                  selected: _category == null,
                  onSelected: () => setState(() => _category = null),
                ),
                const SizedBox(width: 8),
                for (final c in ToolCategory.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _CategoryChip(
                      label: c.label,
                      selected: _category == c,
                      onSelected: () => setState(() => _category = c),
                    ),
                  ),
              ],
            ),
          ),
          if (recent.isNotEmpty) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  '最近使用',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  for (final t in recent)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        label: Text(t.name),
                        onPressed: () => _openTool(t),
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Expanded(
            child: filtered.isEmpty
                ? const Center(child: Text('没有找到相关工具'))
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      mainAxisExtent: 112,
                    ),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final tool = filtered[index];
                      return _ToolCard(
                        tool: tool,
                        onTap: () => _openTool(tool),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
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
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(tool.icon, size: 32),
              const SizedBox(height: 8),
              Text(
                tool.name,
                style: theme.textTheme.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                tool.desc,
                style: theme.textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
