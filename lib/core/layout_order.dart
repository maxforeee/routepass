/// 布局槽位号 / 顺序号 / 枚举序号常量（规格文档第 4 章 §4.10.2 号段分配表）。
///
/// 设计原则（§4.10）：凡是布局里要编号的东西都用带步长的编号、留出空位，
/// 新东西来了插进空位，不用改已有编号。禁止从 0、1、2、3 重新排。
/// 新增编号只许插预留空位，禁止复用已占用的号、禁止把空位一次占满。
library;

/// 首页 12 个方块的 `layoutOrder` 槽位号（步长 10）。
class HomeBlockOrder {
  const HomeBlockOrder._();

  /// H-B1。预留：130–190 为新增方块（每 10 一个空槽），200–290 为整组扩展。
  static const int b1 = 10;

  /// H-B2。
  static const int b2 = 20;

  /// H-B3。
  static const int b3 = 30;

  /// H-B4。
  static const int b4 = 40;

  /// H-B5。
  static const int b5 = 50;

  /// H-B6。
  static const int b6 = 60;

  /// H-B7。
  static const int b7 = 70;

  /// H-B8。
  static const int b8 = 80;

  /// H-B9。
  static const int b9 = 90;

  /// H-B10。
  static const int b10 = 100;

  /// H-B11。
  static const int b11 = 110;

  /// H-B12。
  static const int b12 = 120;
}

/// 套卷卡槽位号（卡片区卡片排序用；`drawCount` 本身仍是 100/200/50/10）。
class PaperCardOrder {
  const PaperCardOrder._();

  /// 100 题卷卡。预留：50–90 为新档位（如 300 题、自定义卷）。
  static const int paper100 = 10;

  /// 200 题卷卡。
  static const int paper200 = 20;

  /// 50 题卷卡。
  static const int paper50 = 30;

  /// 10 题卷卡。
  static const int paper10 = 40;
}

/// 工具箱工具槽位号（步长 10）。
class ToolboxSlot {
  const ToolboxSlot._();

  /// T-B1。预留：90、100 为 Ping、端口扫描（第 16 章正式工具）；110–190 为新增工具。
  static const int b1 = 10;

  /// T-B2。
  static const int b2 = 20;

  /// T-B3。
  static const int b3 = 30;

  /// T-B4。
  static const int b4 = 40;

  /// T-B5。
  static const int b5 = 50;

  /// T-B6。
  static const int b6 = 60;

  /// T-B7。
  static const int b7 = 70;

  /// T-B8。
  static const int b8 = 80;
}

/// 页面编码 `pageCode` 号段（内部编码，埋点/日志用；路由名仍是字符串路径）。
class PageCodeRange {
  const PageCodeRange._();

  /// V1 页面号段。预留：以后每新增一个版本占一段（每段 100 个号）。
  static const int v1Start = 100;
  static const int v1End = 199;

  /// V2 页面号段。
  static const int v2Start = 200;
  static const int v2End = 299;

  /// V3 页面号段。
  static const int v3Start = 300;
  static const int v3End = 399;

  /// V4 页面号段。
  static const int v4Start = 400;
  static const int v4End = 499;

  /// V5 页面号段（预留）。
  static const int v5Start = 500;
  static const int v5End = 599;

  /// V6 页面号段（预留）。
  static const int v6Start = 600;
  static const int v6End = 699;
}

/// 题目类型枚举序号（§4.10.2：步长 10）。
class QuestionTypeOrder {
  const QuestionTypeOrder._();

  /// `single`。预留：30、40… 以后新增题型（如判断、填空）；未知题型禁止降级为单选。
  static const int single = 10;

  /// `multiple`。
  static const int multiple = 20;
}

/// 模块枚举序号（步长 10；模块代码字符串本身不变）。
class ModuleOrder {
  const ModuleOrder._();

  /// `VLAN`。预留：60、70… 以后新增模块。
  static const int vlan = 10;

  /// `OSPF`。
  static const int ospf = 20;

  /// `ACL`。
  static const int acl = 30;

  /// `NAT`。
  static const int nat = 40;

  /// `SUBNET`。
  static const int subnet = 50;
}

/// 同步操作枚举序号（步长 10；`op_type` 字符串本身不变，见 §4.8.7）。
class SyncOpOrder {
  const SyncOpOrder._();

  /// `practice`。预留：90 起以后新增操作类型。
  static const int practice = 10;

  /// `wrong_add`。
  static const int wrongAdd = 20;

  /// `wrong_master`。
  static const int wrongMaster = 30;

  /// `wrong_update`。
  static const int wrongUpdate = 40;

  /// `wrong_remove`。
  static const int wrongRemove = 50;

  /// `favorite`。
  static const int favorite = 60;

  /// `exam_submit`。
  static const int examSubmit = 70;

  /// `kv_set`。
  static const int kvSet = 80;
}
