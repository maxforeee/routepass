/// 模块代码与展示顺序（M7 收敛：三处本地列表的唯一来源）。
library;

/// 模块代码 -> 中文展示名（SUBNET 显示“子网划分”）。
String moduleLabel(String module) => module == 'SUBNET' ? '子网划分' : module;

/// 五个模块的展示顺序（与 Mock 题库一致）。
const List<String> kModuleOrder = <String>[
  'VLAN',
  'OSPF',
  'ACL',
  'NAT',
  'SUBNET',
];
