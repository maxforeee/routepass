// 字段名必须与规格文档 §4.8 数据契约一字不差（snake_case），故忽略本 lint。
// ignore_for_file: non_constant_identifier_names
/// 工具箱模型（规格文档第 4 章 §4.8 数据契约；子网计算/转换/扫描/CLI 等工具）。
///
/// 字段名与数据契约一字不差；服务端返回的数据也必须符合同一契约，
/// 否则校验器（v3.1 附录 B）报错。
library;

/// 子网计算结果。
class SubnetResult {
  const SubnetResult({
    required this.network,
    required this.broadcast,
    required this.firstHost,
    required this.lastHost,
    required this.hostCount,
    required this.netmask,
    required this.wildcard,
    required this.binaryNetwork,
    required this.binaryNetmask,
  });

  /// 网络地址。
  final String network;

  /// 广播地址。
  final String broadcast;

  /// 第一个可用主机地址。
  final String firstHost;

  /// 最后一个可用主机地址。
  final String lastHost;

  /// 可用主机数。
  final int hostCount;

  /// 子网掩码。
  final String netmask;

  /// 反掩码（wildcard mask）。
  final String wildcard;

  /// 网络地址的二进制表示。
  final String binaryNetwork;

  /// 子网掩码的二进制表示。
  final String binaryNetmask;

  factory SubnetResult.fromJson(Map<String, dynamic> json) {
    return SubnetResult(
      network: json['network'] as String,
      broadcast: json['broadcast'] as String,
      firstHost: json['firstHost'] as String,
      lastHost: json['lastHost'] as String,
      hostCount: json['hostCount'] as int,
      netmask: json['netmask'] as String,
      wildcard: json['wildcard'] as String,
      binaryNetwork: json['binaryNetwork'] as String,
      binaryNetmask: json['binaryNetmask'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'network': network,
      'broadcast': broadcast,
      'firstHost': firstHost,
      'lastHost': lastHost,
      'hostCount': hostCount,
      'netmask': netmask,
      'wildcard': wildcard,
      'binaryNetwork': binaryNetwork,
      'binaryNetmask': binaryNetmask,
    };
  }

  @override
  String toString() => 'SubnetResult($network)';
}

/// VLSM 子网划分计划。
class VlsmPlan {
  const VlsmPlan({required this.network, required this.subnets});

  /// 被划分的母网地址。
  final String network;

  /// 划分出的子网列表（每项为 `{name, network, mask, hosts...}` 形状的结构）。
  final List<Map<String, dynamic>> subnets;

  factory VlsmPlan.fromJson(Map<String, dynamic> json) {
    return VlsmPlan(
      network: json['network'] as String,
      subnets: (json['subnets'] as List<dynamic>)
          .map((e) => (e as Map<dynamic, dynamic>).cast<String, dynamic>())
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{'network': network, 'subnets': subnets};
  }

  @override
  String toString() => 'VlsmPlan($network, ${subnets.length} subnets)';
}

/// IP 进制转换结果。
class IpConvertResult {
  const IpConvertResult({
    required this.input,
    this.decimal,
    this.hex,
    this.binary,
    this.cidr,
    this.netmask,
  });

  /// 原始输入。
  final String input;

  /// 十进制表示（无法转换时为 null）。
  final String? decimal;

  /// 十六进制表示（无法转换时为 null）。
  final String? hex;

  /// 二进制表示（无法转换时为 null）。
  final String? binary;

  /// CIDR 表示（无法转换时为 null）。
  final String? cidr;

  /// 子网掩码表示（无法转换时为 null）。
  final String? netmask;

  factory IpConvertResult.fromJson(Map<String, dynamic> json) {
    return IpConvertResult(
      input: json['input'] as String,
      decimal: json['decimal'] as String?,
      hex: json['hex'] as String?,
      binary: json['binary'] as String?,
      cidr: json['cidr'] as String?,
      netmask: json['netmask'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'input': input,
      'decimal': decimal,
      'hex': hex,
      'binary': binary,
      'cidr': cidr,
      'netmask': netmask,
    };
  }

  @override
  String toString() => 'IpConvertResult($input)';
}

/// Ping 模拟结果。
class PingResult {
  const PingResult({
    required this.state,
    required this.message,
    this.latencyMs,
  });

  /// 结果状态：`ok` / `timeout` / `unreachable` / `error` 等。
  final String state;

  /// 结果说明文案。
  final String message;

  /// 延迟（毫秒），不通时为 null。
  final int? latencyMs;

  factory PingResult.fromJson(Map<String, dynamic> json) {
    return PingResult(
      state: json['state'] as String,
      message: json['message'] as String,
      latencyMs: json['latencyMs'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'state': state,
      'message': message,
      'latencyMs': latencyMs,
    };
  }

  @override
  String toString() => 'PingResult($state, $latencyMs ms)';
}

/// 端口扫描结果。
class PortScanResult {
  const PortScanResult({
    required this.state,
    required this.message,
    required this.openPorts,
  });

  /// 结果状态：`ok` / `error` 等。
  final String state;

  /// 结果说明文案。
  final String message;

  /// 开放端口列表。
  final List<int> openPorts;

  factory PortScanResult.fromJson(Map<String, dynamic> json) {
    return PortScanResult(
      state: json['state'] as String,
      message: json['message'] as String,
      openPorts: (json['openPorts'] as List<dynamic>).cast<int>(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'state': state,
      'message': message,
      'openPorts': openPorts,
    };
  }

  @override
  String toString() => 'PortScanResult($state, ${openPorts.length} open)';
}

/// 工具历史记录（客户端表 `tool_history`）。
class ToolHistory {
  const ToolHistory({
    required this.id,
    required this.tool,
    required this.input,
    this.output,
    required this.created_at,
  });

  /// 记录自增 id。
  final int id;

  /// 工具名：`subnet` / `ping` / `portscan` / `cli` 之一。
  final String tool;

  /// 输入内容。
  final String input;

  /// 输出内容（可为 null）。
  final String? output;

  /// 创建时间戳（毫秒）。
  final int created_at;

  factory ToolHistory.fromJson(Map<String, dynamic> json) {
    return ToolHistory(
      id: json['id'] as int,
      tool: json['tool'] as String,
      input: json['input'] as String,
      output: json['output'] as String?,
      created_at: json['created_at'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'tool': tool,
      'input': input,
      'output': output,
      'created_at': created_at,
    };
  }

  @override
  String toString() => 'ToolHistory($id, $tool)';
}

/// CLI 命令速查条目（客户端表 `cli_commands`）。
class CliCommand {
  const CliCommand({
    required this.id,
    required this.category,
    required this.command,
    required this.desc_cn,
    this.example,
    required this.keywords,
  });

  /// 命令唯一 id。
  final String id;

  /// 所属分类（如 `VLAN` / `OSPF` / `ACL` / `NAT` / `通用`）。
  final String category;

  /// 命令本身。
  final String command;

  /// 中文说明。
  final String desc_cn;

  /// 示例（可为 null）。
  final String? example;

  /// 检索用关键词（空格分隔）。
  final String keywords;

  factory CliCommand.fromJson(Map<String, dynamic> json) {
    return CliCommand(
      id: json['id'] as String,
      category: json['category'] as String,
      command: json['command'] as String,
      desc_cn: json['desc_cn'] as String,
      example: json['example'] as String?,
      keywords: json['keywords'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'category': category,
      'command': command,
      'desc_cn': desc_cn,
      'example': example,
      'keywords': keywords,
    };
  }

  @override
  String toString() => 'CliCommand($id, $command)';
}
