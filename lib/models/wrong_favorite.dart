// 字段名必须与规格文档 §4.8 数据契约一字不差（snake_case），故忽略本 lint。
// ignore_for_file: non_constant_identifier_names
/// 错题与收藏模型（规格文档第 4 章 §4.8.5；客户端表 `wrong_book` /
/// `favorites`）。
///
/// 字段名与 §4.8.5 数据契约一字不差；Mock 数据必须符合同一契约，
/// 不许编造契约之外的字段（§4.8.9）。
library;

/// 错题条目（§4.8.5）。
///
/// `wrong_add` 必须把 `mastered` 置 `false`、`wrong_count` + 1
/// （v3.1 第 8 章，见 §4.8.7）。
class WrongItem {
  const WrongItem({
    required this.question_id,
    required this.wrong_count,
    required this.last_wrong_at,
    required this.mastered,
    this.removed_at,
  });

  /// 题目 id。
  final String question_id;

  /// 累计做错次数（wrong_add 时 +1）。
  final int wrong_count;

  /// 最近一次做错的毫秒时间戳。
  final int last_wrong_at;

  /// 是否已标记掌握（wrong_add 强制置回 `false`）。
  final bool mastered;

  /// 移除墓碑的毫秒时间戳（null 表示未移除；只允许用户显式移除与
  /// 题库更新失效两种触发，见 §4.4.4 / v3.1 第 8 章）。
  final int? removed_at;

  factory WrongItem.fromJson(Map<String, dynamic> json) {
    return WrongItem(
      question_id: json['question_id'] as String,
      wrong_count: json['wrong_count'] as int,
      last_wrong_at: json['last_wrong_at'] as int,
      mastered: json['mastered'] as bool,
      removed_at: json['removed_at'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'question_id': question_id,
      'wrong_count': wrong_count,
      'last_wrong_at': last_wrong_at,
      'mastered': mastered,
      'removed_at': removed_at,
    };
  }

  @override
  String toString() => 'WrongItem($question_id, x$wrong_count)';
}

/// 收藏条目（§4.8.5）。只有 `question_id` 与 `created_at` 两个字段。
class Favorite {
  const Favorite({required this.question_id, required this.created_at});

  /// 题目 id。
  final String question_id;

  /// 收藏时刻的毫秒时间戳。
  final int created_at;

  factory Favorite.fromJson(Map<String, dynamic> json) {
    return Favorite(
      question_id: json['question_id'] as String,
      created_at: json['created_at'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'question_id': question_id,
      'created_at': created_at,
    };
  }

  @override
  String toString() => 'Favorite($question_id)';
}
