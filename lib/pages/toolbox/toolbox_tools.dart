import 'package:flutter/material.dart';

import '../../core/kv_store.dart';
import '../../core/service_locator.dart';
import '../../router/app_router.dart';

/// 工具分类（T-03 chips：计算 / 查询 / 对照）。
enum ToolCategory { calc, query, reference }

extension ToolCategoryLabel on ToolCategory {
  String get label => switch (this) {
    ToolCategory.calc => '计算',
    ToolCategory.query => '查询',
    ToolCategory.reference => '对照',
  };
}

/// 工具箱工具注册表（T-05 grid 的数据源）。
///
/// 槽位号见规格文档 §4.10：T-B1→10 … T-B8→80（步长 10），
/// 90、100 为 Ping、端口扫描（第 16 章正式工具，附录 B 已裁决按 T-B 同构卡片实现）。
class ToolboxTool {
  const ToolboxTool({
    required this.id,
    required this.name,
    required this.desc,
    required this.icon,
    required this.category,
    required this.route,
    required this.slot,
  });

  final String id;
  final String name;
  final String desc;
  final IconData icon;
  final ToolCategory category;
  final String route;
  final int slot;
}

const List<ToolboxTool> toolboxTools = <ToolboxTool>[
  ToolboxTool(
    id: 'subnet',
    name: '子网划分',
    desc: '算网络/广播/可用主机',
    icon: Icons.calculate_outlined,
    category: ToolCategory.calc,
    route: AppRoutes.toolboxSubnet,
    slot: 10,
  ),
  ToolboxTool(
    id: 'ipconvert',
    name: 'IP/进制转换',
    desc: 'IP ↔ 十/十六/二进制',
    icon: Icons.swap_horiz_outlined,
    category: ToolCategory.calc,
    route: AppRoutes.toolboxIpConvert,
    slot: 20,
  ),
  ToolboxTool(
    id: 'cidr',
    name: 'CIDR↔掩码',
    desc: '/24 ↔ 255.255.255.0',
    icon: Icons.compare_arrows_outlined,
    category: ToolCategory.calc,
    route: AppRoutes.toolboxCidr,
    slot: 30,
  ),
  ToolboxTool(
    id: 'vlsm',
    name: 'VLSM 规划',
    desc: '按主机数拆分子网',
    icon: Icons.account_tree_outlined,
    category: ToolCategory.calc,
    route: AppRoutes.toolboxVlsm,
    slot: 40,
  ),
  ToolboxTool(
    id: 'cli',
    name: '命令速查',
    desc: 'H3C 常用命令',
    icon: Icons.terminal_outlined,
    category: ToolCategory.query,
    route: AppRoutes.toolboxCli,
    slot: 50,
  ),
  ToolboxTool(
    id: 'units',
    name: '单位换算',
    desc: '速率/容量单位互转',
    icon: Icons.straighten_outlined,
    category: ToolCategory.calc,
    route: AppRoutes.toolboxUnits,
    slot: 60,
  ),
  ToolboxTool(
    id: 'osi',
    name: 'OSI/TCP-IP 对照',
    desc: '七层模型与协议对照',
    icon: Icons.layers_outlined,
    category: ToolCategory.reference,
    route: AppRoutes.toolboxOsi,
    slot: 70,
  ),
  ToolboxTool(
    id: 'ports',
    name: '端口速查',
    desc: '常用端口与服务',
    icon: Icons.dns_outlined,
    category: ToolCategory.query,
    route: AppRoutes.toolboxPorts,
    slot: 80,
  ),
  ToolboxTool(
    id: 'ping',
    name: 'Ping',
    desc: 'TCP 探测目标端口',
    icon: Icons.network_ping_outlined,
    category: ToolCategory.query,
    route: AppRoutes.toolboxPing,
    slot: 90,
  ),
  ToolboxTool(
    id: 'portscan',
    name: '端口扫描',
    desc: '扫描目标常用端口',
    icon: Icons.radar_outlined,
    category: ToolCategory.query,
    route: AppRoutes.toolboxPortscan,
    slot: 100,
  ),
];

/// 把工具 id 记到 kv `toolbox.recent` 队首（最多 5 个，去重）。
/// 各工具页进页时在 initState 里调用，不论从 grid、首页还是最近使用进入都覆盖。
void recordRecentTool(String toolId) {
  final kv = ServiceLocator.kvStore;
  final recent = <String>[...?kv.getStringList(KvStore.keyToolboxRecent)];
  recent.remove(toolId);
  recent.insert(0, toolId);
  kv.setStringList(KvStore.keyToolboxRecent, recent.take(5).toList());
}
