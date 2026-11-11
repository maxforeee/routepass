// 字段名必须与规格文档 §4.8 数据契约一字不差（snake_case），故忽略本 lint。
// ignore_for_file: non_constant_identifier_names
/// 内容版本与升级模型（规格文档第 4 章 §4.8 数据契约；内容包/升级检查相关结构）。
///
/// 字段名与数据契约一字不差；服务端返回的数据也必须符合同一契约，
/// 否则校验器（v3.1 附录 B）报错。
library;

/// 内容版本信息（题库 + 知识点成对发布）。
class ContentVersion {
  const ContentVersion({
    required this.pair_seq,
    required this.bank_version,
    required this.knowledge_version,
    required this.bank_count,
    required this.knowledge_count,
    required this.status,
  });

  /// 版本对序号（单调递增）。
  final int pair_seq;

  /// 题库版本号。
  final String bank_version;

  /// 知识点版本号。
  final String knowledge_version;

  /// 题目总数。
  final int bank_count;

  /// 知识点总数。
  final int knowledge_count;

  /// 状态：`active` / `staged`。
  final String status;

  factory ContentVersion.fromJson(Map<String, dynamic> json) {
    return ContentVersion(
      pair_seq: json['pair_seq'] as int,
      bank_version: json['bank_version'] as String,
      knowledge_version: json['knowledge_version'] as String,
      bank_count: json['bank_count'] as int,
      knowledge_count: json['knowledge_count'] as int,
      status: json['status'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'pair_seq': pair_seq,
      'bank_version': bank_version,
      'knowledge_version': knowledge_version,
      'bank_count': bank_count,
      'knowledge_count': knowledge_count,
      'status': status,
    };
  }

  @override
  String toString() =>
      'ContentVersion(seq: $pair_seq, bank: $bank_version, knowledge: $knowledge_version)';
}

/// 升级检查结果。
class UpgradeCheck {
  const UpgradeCheck({
    required this.latest,
    required this.min_supported,
    required this.compatibility,
    required this.upgrade_url,
    required this.force,
  });

  /// 最新 App 版本号。
  final String latest;

  /// 最低支持的内容包版本号。
  final String min_supported;

  /// 兼容性：`ok` / `soft` / `hard`。
  final String compatibility;

  /// 升级下载地址。
  final String upgrade_url;

  /// 是否强制升级。
  final bool force;

  factory UpgradeCheck.fromJson(Map<String, dynamic> json) {
    return UpgradeCheck(
      latest: json['latest'] as String,
      min_supported: json['min_supported'] as String,
      compatibility: json['compatibility'] as String,
      upgrade_url: json['upgrade_url'] as String,
      force: json['force'] as bool,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'latest': latest,
      'min_supported': min_supported,
      'compatibility': compatibility,
      'upgrade_url': upgrade_url,
      'force': force,
    };
  }

  @override
  String toString() => 'UpgradeCheck($compatibility, latest: $latest)';
}

/// 能力声明（功能开关与支持的题型）。
class Capabilities {
  const Capabilities({
    required this.features,
    required this.supported_question_types,
  });

  /// 已开放的功能列表。
  final List<String> features;

  /// 支持的题型列表，如 `single` / `multiple`。
  final List<String> supported_question_types;

  factory Capabilities.fromJson(Map<String, dynamic> json) {
    return Capabilities(
      features: (json['features'] as List<dynamic>).cast<String>(),
      supported_question_types:
          (json['supported_question_types'] as List<dynamic>).cast<String>(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'features': features,
      'supported_question_types': supported_question_types,
    };
  }

  @override
  String toString() =>
      'Capabilities(features: $features, types: $supported_question_types)';
}
