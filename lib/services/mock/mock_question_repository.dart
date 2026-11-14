/// QuestionRepository 的 Mock 实现（规格文档第 4 章 §4.4.1）。
///
/// 只读 assets 里的 3 道样例题，不含答案；以后换真实实现时 UI 文件不动。
library;

import '../../models/question.dart';
import '../../models/stats.dart';
import '../bank/question_repo.dart';
import 'sample_data.dart';

class MockQuestionRepository implements QuestionRepository {
  static const List<String> _modules = <String>[
    'VLAN',
    'OSPF',
    'ACL',
    'NAT',
    'SUBNET',
  ];

  @override
  Future<List<ModuleStat>> getModules() async {
    return _modules
        .map(
          (m) => ModuleStat(module: m, total: 0, answered: 0, correctRate: 0.0),
        )
        .toList();
  }

  @override
  Future<List<Question>> drawQuestions({
    required String mode,
    required int drawCount,
    String? module,
    String? knowledgePointId,
  }) async {
    var questions = await SampleData.loadSampleQuestions();
    if (module != null) {
      questions = questions.where((q) => q.module == module).toList();
    }
    if (knowledgePointId != null) {
      questions = questions
          .where((q) => q.knowledge_point_id == knowledgePointId)
          .toList();
    }
    // Mock 只有 3 道样例题，不足 drawCount 时有多少返多少。
    if (questions.length > drawCount) {
      return questions.sublist(0, drawCount);
    }
    return questions;
  }

  @override
  Future<Question?> getQuestionById(String id) async {
    final questions = await SampleData.loadSampleQuestions();
    for (final q in questions) {
      if (q.id == id) return q;
    }
    return null;
  }

  /// F16 预留接口：后端套卷级统计未就绪，返回空（UI 显示“待接口”）。
  @override
  Future<List<ModuleStat>> getSetModuleStats({required String setId}) async {
    return const <ModuleStat>[];
  }

  /// F19 预留接口：套卷概览未就绪，返回 null（UI 显示“待接口”）。
  @override
  Future<BankSetOverview?> getSetOverview({required String setId}) async {
    return null;
  }
}
