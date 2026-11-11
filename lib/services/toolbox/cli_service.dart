/// 命令速查服务抽象接口（规格文档第 4 章 §4.6.5）。
///
/// 服务的页面：工具箱 T-B5 命令速查、知识详情页 commands 渲染共用。
/// 现在的实现是 Mock（assets/data/cli_commands.json 样例子集）；以后读本地 cli_commands 表
/// （v3.1 第 12 章），永不走服务器。
library;

import '../../models/toolbox.dart';

abstract class CliService {
  /// 按分类取命令。Mock：读 assets/data/cli_commands.json 的样例子集。
  /// 以后：读本地 cli_commands 表（v3.1 第 12 章），永不走服务器。
  Future<List<CliCommand>> getCommands({String? category, String? keyword});

  /// 取一条命令的详情（含 example）。字段见 §4.8.10。
  Future<CliCommand?> getCommand(String id);
}
