import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_snackbar.dart';
import '../../core/service_locator.dart';
import '../../core/theme.dart';
import '../../models/toolbox.dart';
import 'toolbox_tools.dart';

class CliPage extends StatefulWidget {
  const CliPage({super.key});

  @override
  State<CliPage> createState() => _CliPageState();
}

class _CliPageState extends State<CliPage> {
  final _searchController = TextEditingController();
  List<CliCommand> _allCommands = const [];
  List<CliCommand> _commands = const [];
  String? _category; // null = 全部
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    recordRecentTool('cli');
    _loadAll();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    final commands = await ServiceLocator.cliService.getCommands();
    if (!mounted) return;
    setState(() => _allCommands = commands);
  }

  Future<void> _load() async {
    final keyword = _searchController.text.trim();
    final commands = await ServiceLocator.cliService.getCommands(
      category: _category,
      keyword: keyword.isEmpty ? null : keyword,
    );
    if (!mounted) return;
    setState(() {
      _commands = commands;
      _loading = false;
    });
  }

  List<String> get _categories {
    final seen = <String>[];
    for (final c in _allCommands) {
      if (!seen.contains(c.category)) seen.add(c.category);
    }
    return seen;
  }

  void _copy(CliCommand command) {
    Clipboard.setData(ClipboardData(text: command.command));
    showAppSnackBar(context, '已复制');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('命令速查')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: '搜索命令，如 vlan',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
              ),
              onChanged: (_) => _load(),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('全部'),
                  selected: _category == null,
                  onSelected: (_) {
                    setState(() => _category = null);
                    _load();
                  },
                ),
                const SizedBox(width: 8),
                for (final c in _categories)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(c),
                      selected: _category == c,
                      onSelected: (_) {
                        setState(() => _category = c);
                        _load();
                      },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _commands.isEmpty
                ? const Center(child: Text('没有找到相关命令'))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: _commands.length,
                    itemBuilder: (context, index) {
                      final command = _commands[index];
                      return Card(
                        child: InkWell(
                          onTap: () => _copy(command),
                          borderRadius: BorderRadius.circular(16),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  command.command,
                                  style: monoTextStyle(context, fontSize: 14),
                                ),
                                const SizedBox(height: 4),
                                Text(command.desc_cn),
                                if (command.example != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    '示例：${command.example}',
                                    style: monoTextStyle(context, fontSize: 13),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
