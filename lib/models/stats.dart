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

/// 套卷题型分布（F19，`GET /bank/sets/{setId}/overview` 的 `byType`）。
class QuestionTypeStat {
  const QuestionTypeStat({
    required this.setId,
    required this.single,
    required this.multiple,
  });

  final String setId;
  final int single;
  final int multiple;

  int get total => single + multiple;

  factory QuestionTypeStat.fromJson(Map<String, dynamic> json) {
    return QuestionTypeStat(
      setId: json['setId'] as String? ?? '',
      single: (json['single'] as num?)?.toInt() ?? 0,
      multiple: (json['multiple'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'setId': setId,
      'single': single,
      'multiple': multiple,
    };
  }

  @override
  String toString() => 'QuestionTypeStat($setId, $single/$multiple)';
}

/// 套卷概览（F19，`GET /bank/sets/{setId}/overview`）。
///
/// 后端尚未就绪时仓储返回 null，前置页显示“题型待接口 / 完成情况待接口”，
/// 绝不按比例推算或写 0。
class BankSetOverview {
  const BankSetOverview({
    required this.setId,
    required this.total,
    required this.done,
    required this.remaining,
    this.byType,
  });

  final String setId;
  final int total;
  final int done;
  final int remaining;

  /// 题型分布；S11 `GET /practice/progress` 不提供该字段，按 null 处理，
  /// 前置页显示“题型待接口”。绝不按比例推算，也不写 0。
  final QuestionTypeStat? byType;

  factory BankSetOverview.fromJson(Map<String, dynamic> json) {
    final typeJson = json['byType'];
    return BankSetOverview(
      setId: json['setId'] as String? ?? '',
      total: (json['total'] as num?)?.toInt() ?? 0,
      done: (json['done'] as num?)?.toInt() ?? 0,
      remaining: (json['remaining'] as num?)?.toInt() ?? 0,
      byType: typeJson is Map<String, dynamic>
          ? QuestionTypeStat.fromJson(<String, dynamic>{
              'setId': json['setId'],
              ...typeJson,
            })
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'setId': setId,
      'total': total,
      'done': done,
      'remaining': remaining,
      'byType': byType?.toJson(),
    };
  }

  @override
  String toString() => 'BankSetOverview($setId, $done/$total)';
}
