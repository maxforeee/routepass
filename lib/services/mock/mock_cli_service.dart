/// CliService 的 Mock 实现（规格文档第 4 章 §4.6.5）。
///
/// 读 assets/data/cli_commands.json 的样例子集，本地过滤；永不走服务器。
library;

import '../../models/toolbox.dart';
import '../toolbox/cli_service.dart';
import 'sample_data.dart';

class MockCliService implements CliService {
  @override
  Future<List<CliCommand>> getCommands({
    String? category,
    String? keyword,
  }) async {
    var commands = await SampleData.loadCliCommands();
    if (category != null) {
      commands = commands.where((c) => c.category == category).toList();
    }
    if (keyword != null && keyword.trim().isNotEmpty) {
      final key = keyword.trim();
      commands = commands
          .where(
            (c) =>
                c.command.contains(key) ||
                c.desc_cn.contains(key) ||
                c.keywords.contains(key),
          )
          .toList();
    }
    return commands;
  }

  @override
  Future<CliCommand?> getCommand(String id) async {
    final commands = await SampleData.loadCliCommands();
    for (final c in commands) {
      if (c.id == id) return c;
    }
    return null;
  }
}
