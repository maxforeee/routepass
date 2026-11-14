/// 考试服务抽象接口（规格文档第 4 章 §4.4.3）。
///
/// 服务的页面：考试页、交卷 dialog、结果页。
/// 现在的实现是 Mock（本地组卷占位，不判真分，score 一律为 null）；以后真实实现走
/// `POST /exam/start`、`/exam/{id}/submit`、`GET /exam/{id}`、`/exam/history`。
library;

import '../../models/exam.dart';

abstract class ExamService {
  /// 开始考试。调用时机：点“套卷 100/200/50”或考试入口时。
  /// Mock：本地用样例题组卷，examId 为本地生成的 "MOCK-EXAM-10" 样式编号；
  /// 返回的题目不含答案（answer 为 []），与以后行为一致。
  /// 以后：POST /exam/start，返回 100 题（不含答案）+ 服务端生成的 examId 与快照。
  Future<ExamSession> startExam({required int drawCount, String? setId});

  /// F19：考试逐题暂存（`PUT /exam/{examId}/answers`，不判分）。
  /// 接口未就绪时静默失败，本地进行态快照保证续考。
  Future<void> saveAnswer({
    required String examId,
    required String questionId,
    required List<String> chosen,
    required String opId,
  }) async {}

  /// 交卷。调用时机：交卷 dialog 点“确认交卷”时。
  /// Mock：本地按空答案计分——score 一律返回 null，页面显示“样例考试，不计分”。
  /// 绝不许用 Mock 的假答案算出一个假分数。
  /// 以后：POST /exam/{id}/submit，服务端按快照判分，返回 {score, passed, detail}。
  Future<ExamResult?> submitExam({
    required String examId,
    required Map<String, List<String>> answers,
    required int durationMs,
  });

  /// 考试详情与历史。Mock：返回空列表。以后：GET /exam/{id}、GET /exam/history。
  Future<ExamSession?> getExam(String examId);
  Future<List<ExamSession>> getHistory();
}
