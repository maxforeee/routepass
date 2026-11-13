/// 题库清单模型（后端 `GET /api/v1/bank/manifest` 的响应）。
///
/// 练习 tab 的每条记录来自 `practiceByModule`（模块 → 题量），考试 tab 的
/// 每条记录来自 `exams[]`（卷 id / 卷名 / 题量）。字段按后端 JSON 命名，
/// 页面只消费解析后的类型。
library;

/// 练习套卷记录：一个模块一条。
class PracticeSetRecord {
  const PracticeSetRecord({required this.module, required this.questionCount});

  /// 模块代码，例如 `H3CNE`。
  final String module;

  /// 模块题目数。
  final int questionCount;
}

/// 考试套卷记录：`exams[]` 的一项。
class ExamSetRecord {
  const ExamSetRecord({
    required this.id,
    required this.title,
    required this.questionCount,
  });

  final String id;
  final String title;
  final int questionCount;
}

/// 题库清单。
class BankManifest {
  const BankManifest({
    required this.bankId,
    required this.version,
    required this.questionCount,
    required this.practiceSets,
    required this.examSets,
  });

  final String bankId;
  final String version;

  /// 题库总题量。
  final int questionCount;

  final List<PracticeSetRecord> practiceSets;
  final List<ExamSetRecord> examSets;

  factory BankManifest.fromJson(Map<String, dynamic> json) {
    final practiceByModule =
        json['practiceByModule'] as Map<String, dynamic>? ??
        const <String, dynamic>{};
    final exams = json['exams'] as List<dynamic>? ?? const <dynamic>[];

    return BankManifest(
      bankId: json['bankId'] as String? ?? '',
      version: json['version'] as String? ?? '',
      questionCount: (json['questionCount'] as num?)?.toInt() ?? 0,
      practiceSets: [
        for (final entry in practiceByModule.entries)
          PracticeSetRecord(
            module: entry.key,
            questionCount: (entry.value as num).toInt(),
          ),
      ],
      examSets: [
        for (final exam in exams)
          if (exam is Map<String, dynamic>)
            ExamSetRecord(
              id: exam['id'] as String? ?? '',
              title: exam['title'] as String? ?? '',
              questionCount: (exam['questionCount'] as num?)?.toInt() ?? 0,
            ),
      ],
    );
  }
}
