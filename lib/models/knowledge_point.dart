// 字段名必须与规格文档 §4.8 数据契约一字不差（snake_case），故忽略本 lint。
// ignore_for_file: non_constant_identifier_names
/// 知识点模型（规格文档第 4 章 §4.8.2，v3.1 第 6 章 §6.4；客户端表
/// `knowledge_points`）与章节分组（§4.8.3，v3.1 第 6 章 §6.1 三层结构）。
///
/// 字段名与 §4.8.2 / §4.8.3 数据契约一字不差；Mock 数据必须符合同一
/// 契约，不许编造契约之外的字段（§4.8.9）。
library;

/// 单条命令，契约形状 `{cmd, desc}`（§4.8.2 `commands` 元素）。
class KnowledgeCommand {
  const KnowledgeCommand({required this.cmd, required this.desc});

  /// 命令本身，如 `display vlan`。
  final String cmd;

  /// 命令说明。
  final String desc;

  factory KnowledgeCommand.fromJson(Map<String, dynamic> json) {
    return KnowledgeCommand(
      cmd: json['cmd'] as String,
      desc: json['desc'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{'cmd': cmd, 'desc': desc};
  }

  @override
  String toString() => 'KnowledgeCommand($cmd)';
}

/// 知识点（§4.8.2）。
class KnowledgePoint {
  const KnowledgePoint({
    required this.id,
    required this.module,
    required this.topic,
    required this.code,
    required this.title,
    required this.summary,
    required this.content_md,
    required this.row_version,
    this.key_points,
    this.commands,
    this.pitfalls,
    this.tags,
    this.status,
  });

  /// 知识点 id：`KP-{模块}-{2位}-{2位}`，全局唯一，永不变。
  final String id;

  /// 5 个模块代码之一：`VLAN` / `OSPF` / `ACL` / `NAT` / `SUBNET`。
  final String module;

  /// 所属专题名，用于分组展示。
  final String topic;

  /// 展示用章节号，如 `1.3`（“章.节”）。
  final String code;

  /// 标题，≤ 20 字，列表页标题。
  final String title;

  /// 副标题，≤ 100 字，列表副标题 + 搜索摘要。
  final String summary;

  /// 详情页正文（Markdown），V3 补全。
  final String content_md;

  /// 要点列表（可选）。
  final List<String>? key_points;

  /// 命令列表 `{cmd, desc}`，仅 VLAN/OSPF/ACL/NAT 有（可选）。
  final List<KnowledgeCommand>? commands;

  /// 易错点 1–3 条，与错题强相关（可选）。
  final List<String>? pitfalls;

  /// 检索用标签（可选）。
  final List<String>? tags;

  /// 状态：`active` / `deprecated`。
  final String? status;

  /// 行版本（增量同步游标）。
  final int row_version;

  factory KnowledgePoint.fromJson(Map<String, dynamic> json) {
    return KnowledgePoint(
      id: json['id'] as String,
      module: json['module'] as String,
      topic: json['topic'] as String,
      code: json['code'] as String,
      title: json['title'] as String,
      summary: json['summary'] as String,
      content_md: json['content_md'] as String,
      key_points: (json['key_points'] as List<dynamic>?)?.cast<String>(),
      commands: _parseCommands(json['commands']),
      pitfalls: (json['pitfalls'] as List<dynamic>?)?.cast<String>(),
      tags: (json['tags'] as List<dynamic>?)?.cast<String>(),
      status: json['status'] as String?,
      row_version: json['row_version'] as int,
    );
  }

  static List<KnowledgeCommand> _parseCommands(dynamic raw) {
    return (raw as List<dynamic>)
        .map((e) => KnowledgeCommand.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'module': module,
      'topic': topic,
      'code': code,
      'title': title,
      'summary': summary,
      'content_md': content_md,
      if (key_points != null) 'key_points': key_points,
      if (commands != null)
        'commands': commands!.map((e) => e.toJson()).toList(),
      if (pitfalls != null) 'pitfalls': pitfalls,
      if (tags != null) 'tags': tags,
      if (status != null) 'status': status,
      'row_version': row_version,
    };
  }

  @override
  String toString() => 'KnowledgePoint($id, $code: $title)';
}

/// 章（§4.8.3）。章 → 节 → 知识点三层，章/节是展示分组，由
/// `KnowledgePoint.code` 的“章.节”前缀聚合得到，不单独建表。
class Chapter {
  const Chapter({
    required this.id,
    required this.module,
    required this.title,
    required this.order,
  });

  /// 章 id，如 `"VLAN-01"`。
  final String id;

  /// 所属模块代码。
  final String module;

  /// 章标题。
  final String title;

  /// 布局序号，步长见规格文档 §4.10。
  final int order;

  factory Chapter.fromJson(Map<String, dynamic> json) {
    return Chapter(
      id: json['id'] as String,
      module: json['module'] as String,
      title: json['title'] as String,
      order: json['order'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'module': module,
      'title': title,
      'order': order,
    };
  }

  @override
  String toString() => 'Chapter($id: $title)';
}

/// 节（§4.8.3）。由 `KnowledgePoint.code` 的“章.节”前缀聚合得到。
class Section {
  const Section({
    required this.id,
    required this.chapterId,
    required this.title,
    required this.order,
  });

  /// 节 id，如 `"VLAN-01-03"`。
  final String id;

  /// 所属章 id，如 `"VLAN-01"`。
  final String chapterId;

  /// 节标题。
  final String title;

  /// 布局序号，步长见规格文档 §4.10。
  final int order;

  factory Section.fromJson(Map<String, dynamic> json) {
    return Section(
      id: json['id'] as String,
      chapterId: json['chapterId'] as String,
      title: json['title'] as String,
      order: json['order'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'chapterId': chapterId,
      'title': title,
      'order': order,
    };
  }

  @override
  String toString() => 'Section($id: $title)';
}
