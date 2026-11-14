/// 题库仓储抽象接口（规格文档第 4 章 §4.4.1）。
///
/// 服务的页面：首页 H-B2–H-B5、题库页 Q-01–Q-09、答题页取题。
/// 现在的实现是 Mock（3–5 道无答案样例）；以后真实实现走
/// `GET /bank/modules`、`/bank/questions`、`/practice/session`。
/// UI 只依赖本抽象接口，不直接碰网络与数据库。
library;

import '../../models/question.dart';
import '../../models/stats.dart';

abstract class QuestionRepository {
  /// 模块列表与题量统计。调用时机：进题库页时 1 次。
  /// Mock：返回 5 个模块，题量全 0。以后：GET /bank/modules。
  Future<List<ModuleStat>> getModules();

  /// 按条件抽题。drawCount 只允许 10 / 50 / 100 / 200（第 1 章 D20）。
  /// Mock：从 3–5 道无答案样例里返回，不足 drawCount 时有多少返多少，
  /// 并在题面注明“样例数据”。
  /// 以后：GET /practice/session（练习）或 POST /exam/start（考试，不含答案）。
  Future<List<Question>> drawQuestions({
    required String mode, // 'quick' | 'practice' | 'exam' | 'daily'
    required int drawCount, // 10 | 50 | 100 | 200
    String? module, // 'VLAN' | 'OSPF' | 'ACL' | 'NAT' | 'SUBNET'，空为全模块
    String? knowledgePointId, // 按知识点抽题
  });

  /// 单题详情。Mock：样例题返回本身；非样例 id 返回 null（页面显示“题目不存在”）。
  /// 以后：GET /bank/questions/{id}（含答案与解析）。
  Future<Question?> getQuestionById(String id);

  /// 套卷级知识点统计（F16 预留接口）：给定套卷（考试卷 id，如
  /// `h3cne-2026-01`；或练习模块代码，如 `VLAN`）返回每模块题量与用户
  /// 作答进度。后端尚未提供，需要新增
  /// `GET /api/v1/bank/sets/{setId}/modules`，响应为
  /// `[{module, total, answered, correctRate}]`（与 ModuleStat 同一契约）。
  /// 真实实现就绪前一律返回空列表，UI 显示“待接口”，不得虚构数字。
  Future<List<ModuleStat>> getSetModuleStats({required String setId});

  /// 套卷概览（F19 预留接口）：`GET /bank/sets/{setId}/overview`
  /// → `{setId, total, done, remaining, byType:{single,multiple}}`。
  /// 后端 done/undone 与 byType 未就绪前返回 null，前置页显示
  /// “题型待接口 / 完成情况待接口”，绝不按比例推算或写 0。
  Future<BankSetOverview?> getSetOverview({required String setId});
}
