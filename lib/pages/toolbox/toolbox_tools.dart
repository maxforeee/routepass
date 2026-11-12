import 'package:flutter/material.dart';

import '../../core/kv_store.dart';
import '../../core/service_locator.dart';
import '../../core/theme.dart';
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
    required this.iconTone,
    required this.category,
    required this.route,
    required this.slot,
  });

  final String id;
  final String name;
  final String desc;
  final IconData icon;

  /// 图标色调（蓝/绿/橙，见 §4.10 T-B 卡片）。
  final ToolIconTone iconTone;
  final ToolCategory category;
  final String route;
  final int slot;
}

const List<ToolboxTool> toolboxTools = <ToolboxTool>[
  ToolboxTool(
    id: 'subnet',
    name: '子网计算器',
    desc: '网络 / 广播 / 主机数',
    icon: Icons.calculate_outlined,
    iconTone: ToolIconTone.blue,
    category: ToolCategory.calc,
    route: AppRoutes.toolboxSubnet,
    slot: 10,
  ),
  ToolboxTool(
    id: 'ipconvert',
    name: 'IP/进制转换',
    desc: '二/十/十六进制',
    icon: Icons.swap_horiz_outlined,
    iconTone: ToolIconTone.blue,
    category: ToolCategory.calc,
    route: AppRoutes.toolboxIpConvert,
    slot: 20,
  ),
  ToolboxTool(
    id: 'cidr',
    name: 'CIDR ↔ 掩码',
    desc: '前缀 / 掩码互转',
    icon: Icons.compare_arrows_outlined,
    iconTone: ToolIconTone.blue,
    category: ToolCategory.calc,
    route: AppRoutes.toolboxCidr,
    slot: 30,
  ),
  ToolboxTool(
    id: 'vlsm',
    name: 'VLSM 规划',
    desc: '子网划分方案',
    icon: Icons.account_tree_outlined,
    iconTone: ToolIconTone.blue,
    category: ToolCategory.calc,
    route: AppRoutes.toolboxVlsm,
    slot: 40,
  ),
  ToolboxTool(
    id: 'units',
    name: '单位换算',
    desc: 'bps / Bps 换算',
    icon: Icons.straighten_outlined,
    iconTone: ToolIconTone.green,
    category: ToolCategory.calc,
    route: AppRoutes.toolboxUnits,
    slot: 50,
  ),
  ToolboxTool(
    id: 'osi',
    name: 'OSI/TCP-IP 对照',
    desc: '七层 / 四层速查',
    icon: Icons.layers_outlined,
    iconTone: ToolIconTone.blue,
    category: ToolCategory.reference,
    route: AppRoutes.toolboxOsi,
    slot: 60,
  ),
  ToolboxTool(
    id: 'ports',
    name: '端口速查',
    desc: '常用端口表',
    icon: Icons.dns_outlined,
    iconTone: ToolIconTone.blue,
    category: ToolCategory.query,
    route: AppRoutes.toolboxPorts,
    slot: 70,
  ),
  ToolboxTool(
    id: 'cli',
    name: '命令速查',
    desc: 'H3CNE 常用命令',
    icon: Icons.terminal_outlined,
    iconTone: ToolIconTone.blue,
    category: ToolCategory.query,
    route: AppRoutes.toolboxCli,
    slot: 80,
  ),
  ToolboxTool(
    id: 'ping',
    name: 'Ping',
    desc: '本地 TCP 探测',
    icon: Icons.network_ping_outlined,
    iconTone: ToolIconTone.green,
    category: ToolCategory.query,
    route: AppRoutes.toolboxPing,
    slot: 90,
  ),
  ToolboxTool(
    id: 'portscan',
    name: '端口扫描',
    desc: '本地 TCP 扫描',
    icon: Icons.radar_outlined,
    iconTone: ToolIconTone.orange,
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
