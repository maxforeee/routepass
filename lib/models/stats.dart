// 字段名必须与规格文档 §4.8 数据契约一字不差（snake_case），故忽略本 lint。
// ignore_for_file: non_constant_identifier_names
/// 统计模型（规格文档第 4 章 §4.8 数据契约；统计页相关结构）。
///
/// 字段名与数据契约一字不差；服务端返回的数据也必须符合同一契约，
/// 否则校验器（v3.1 附录 B）报错。
library;

/// 单日统计。
class DailyStats {
  const DailyStats({
    required this.stat_date,
    required this.answered,
    required this.correct,
    required this.duration_sec,
  });

  /// 统计日期，格式 `YYYY-MM-DD`。
  final String stat_date;

  /// 当日答题数。
  final int answered;

  /// 当日答对数。
  final int correct;

  /// 当日累计答题时长（秒）。
  final int duration_sec;

  factory DailyStats.fromJson(Map<String, dynamic> json) {
    return DailyStats(
      stat_date: json['stat_date'] as String,
      answered: json['answered'] as int,
      correct: json['correct'] as int,
      duration_sec: json['duration_sec'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'stat_date': stat_date,
      'answered': answered,
      'correct': correct,
      'duration_sec': duration_sec,
    };
  }

  @override
  String toString() => 'DailyStats($stat_date, $answered/$correct)';
}

/// 模块统计。
class ModuleStat {
  const ModuleStat({
    required this.module,
    required this.total,
    required this.answered,
    required this.correctRate,
  });

  /// 模块代码：`VLAN` / `OSPF` / `ACL` / `NAT` / `SUBNET`。
  final String module;

  /// 模块题目总数。
  final int total;

  /// 已答题数。
  final int answered;

  /// 正确率（0–1 的小数）。
  final double correctRate;

  factory ModuleStat.fromJson(Map<String, dynamic> json) {
    return ModuleStat(
      module: json['module'] as String,
      total: json['total'] as int,
      answered: json['answered'] as int,
      correctRate: (json['correctRate'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'module': module,
      'total': total,
      'answered': answered,
      'correctRate': correctRate,
    };
  }

  @override
  String toString() => 'ModuleStat($module, $answered/$total)';
}

/// 统计总览。
class StatsOverview {
  const StatsOverview({
    required this.answeredTotal,
    required this.correctRate,
    required this.streakDays,
    required this.todayAnswered,
    required this.todayCorrect,
  });

  /// 累计答题数。
  final int answeredTotal;

  /// 总正确率（0–1 的小数）。
  final double correctRate;

  /// 连续学习天数。
  final int streakDays;

  /// 今日答题数。
  final int todayAnswered;

  /// 今日答对数。
  final int todayCorrect;

  factory StatsOverview.fromJson(Map<String, dynamic> json) {
    return StatsOverview(
      answeredTotal: json['answeredTotal'] as int,
      correctRate: (json['correctRate'] as num).toDouble(),
      streakDays: json['streakDays'] as int,
      todayAnswered: json['todayAnswered'] as int,
      todayCorrect: json['todayCorrect'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'answeredTotal': answeredTotal,
      'correctRate': correctRate,
      'streakDays': streakDays,
      'todayAnswered': todayAnswered,
      'todayCorrect': todayCorrect,
    };
  }

  @override
  String toString() => 'StatsOverview($answeredTotal, $correctRate)';
}
