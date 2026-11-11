// 字段名必须与规格文档 §4.8 数据契约一字不差（snake_case），故忽略本 lint。
// ignore_for_file: non_constant_identifier_names
/// 题目模型（规格文档第 4 章 §4.8.1，v3.1 第 5 章；客户端表 `questions`）。
///
/// 字段名与 §4.8.1 数据契约一字不差；Mock 数据必须符合同一契约，
/// 不许编造契约之外的字段（§4.8.9）。以后服务端返回的数据也必须
/// 符合同一契约，否则校验器（v3.1 附录 B）报错。
library;

/// 单个选项，契约形状 `{key, text}`（§4.8.1 `options` 元素）。
///
/// `key`：A–F，同题内唯一；`text`：1–200 字。
class QuestionOption {
  const QuestionOption({required this.key, required this.text});

  /// 选项序号字母（A–F，同题内唯一）。
  final String key;

  /// 选项文本（1–200 字）。
  final String text;

  factory QuestionOption.fromJson(Map<String, dynamic> json) {
    return QuestionOption(
      key: json['key'] as String,
      text: json['text'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{'key': key, 'text': text};
  }

  @override
  String toString() => 'QuestionOption($key: $text)';
}

/// 题目（§4.8.1）。
class Question {
  const Question({
    required this.id,
    required this.module,
    required this.type,
    required this.stem,
    required this.options,
    required this.answer,
    required this.explanation,
    required this.knowledge_point_id,
    required this.difficulty,
    required this.set_no,
    required this.row_version,
    this.related_ids,
    this.tags,
    this.status,
  });

  /// 题目 id：`^(VLAN|OSPF|ACL|NAT|SUBNET)-\d{4}$`，全局唯一，永不变，
  /// 如 `"VLAN-0007"`。
  final String id;

  /// 5 个模块代码之一：`VLAN` / `OSPF` / `ACL` / `NAT` / `SUBNET`。
  final String module;

  /// 题型：`"single"` / `"multiple"`；未知题型禁止降级为单选（第 1 章 D15）。
  final String type;

  /// 题干，10–500 字，可含 Markdown。
  final String stem;

  /// 选项列表，4–6 项，每项 `{key, text}`。
  final List<QuestionOption> options;

  /// 正确答案的 key 列表：单选长度 1；多选长度 ≥2；元素必须在
  /// `options` 的 key 里。**Mock 必须为空数组 `[]`**。
  final List<String> answer;

  /// 解析，30–800 字。**Mock 必须为空字符串**。
  final String explanation;

  /// 主关联知识点 id，V2 就写入，V3 用。
  final String knowledge_point_id;

  /// 关联知识点 id 列表（可选）。
  final List<String>? related_ids;

  /// 难度 1–3（易/中/难）。
  final int difficulty;

  /// 检索用标签，0–6 个（可选）。
  final List<String>? tags;

  /// 状态：`active` / `deprecated`，默认 `active`。
  final String? status;

  /// 所属套卷号（客户端表字段）。
  final int set_no;

  /// 行版本（增量同步游标，客户端表字段）。
  final int row_version;

  factory Question.fromJson(Map<String, dynamic> json) {
    return Question(
      id: json['id'] as String,
      module: json['module'] as String,
      type: json['type'] as String,
      stem: json['stem'] as String,
      options: _parseOptions(json['options']),
      answer: (json['answer'] as List<dynamic>).cast<String>(),
      explanation: json['explanation'] as String,
      knowledge_point_id: json['knowledge_point_id'] as String,
      related_ids: (json['related_ids'] as List<dynamic>?)?.cast<String>(),
      difficulty: json['difficulty'] as int,
      tags: (json['tags'] as List<dynamic>?)?.cast<String>(),
      status: json['status'] as String?,
      set_no: json['set_no'] as int,
      row_version: json['row_version'] as int,
    );
  }

  static List<QuestionOption> _parseOptions(dynamic raw) {
    return (raw as List<dynamic>)
        .map((e) => QuestionOption.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'module': module,
      'type': type,
      'stem': stem,
      'options': options.map((e) => e.toJson()).toList(),
      'answer': answer,
      'explanation': explanation,
      'knowledge_point_id': knowledge_point_id,
      if (related_ids != null) 'related_ids': related_ids,
      'difficulty': difficulty,
      if (tags != null) 'tags': tags,
      if (status != null) 'status': status,
      'set_no': set_no,
      'row_version': row_version,
    };
  }

  @override
  String toString() => 'Question($id, $type, module: $module)';
}
