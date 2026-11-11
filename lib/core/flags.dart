// 开关名由规格文档 §4.9.3 钦定（MODULE_BANK 等），不受 lowerCamelCase 约束。
// ignore_for_file: constant_identifier_names

/// 编译期功能开关（不是运行时开关）。
///
/// 见规格文档第 4 章 §4.9.3：开关为 `false` 时对应模块的代码被
/// tree-shake，包更小；开关序号见 §4.10.2（步长 10，40 预留，
/// 50、60…留给 V5 及以后新增模块的开关）。开关名本身不变。
class Flags {
  const Flags._();

  /// V2 题库模块。当前未装配，底栏对应目的地显示“暂未开放”占位。
  static const bool MODULE_BANK = false;

  /// V3 知识库模块。当前未装配，底栏对应目的地显示“暂未开放”占位。
  static const bool MODULE_KNOWLEDGE = false;

  /// V4 工具箱模块。当前未装配，底栏对应目的地显示“暂未开放”占位。
  static const bool MODULE_TOOLBOX = false;

  /// MODULE_BANK 开关序号（§4.10.2：功能开关序号）。
  static const int MODULE_BANK_ORDER = 10;

  /// MODULE_KNOWLEDGE 开关序号。
  static const int MODULE_KNOWLEDGE_ORDER = 20;

  /// MODULE_TOOLBOX 开关序号。
  static const int MODULE_TOOLBOX_ORDER = 30;
}
