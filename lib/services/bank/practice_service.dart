/// 练习服务抽象接口（规格文档第 4 章 §4.4.2）。
///
/// 服务的页面：答题页 A-01–A-19（练习模式）、首页 H-B1 继续学习。
/// 现在的实现是 Mock（本地建会话、本地记一笔，不判对错）；以后真实实现走
/// `GET /practice/session`、`POST /practice/answer`。
library;

import '../../models/practice.dart';
import '../../models/question.dart';

abstract class PracticeService {
  /// 开始一次练习会话。调用时机：从题库页/首页方块进答题页时。
  /// Mock：用 drawQuestions 的结果在本地建会话。以后：GET /practice/session。
  Future<PracticeSession> startSession({
    required List<Question> questions,
    required String mode,
  });

  /// 提交单题作答。调用时机：用户选完选项点“下一题”或“确认”时（按第 2 章 §14.8 的流程）。
  /// Mock：只在本地记一笔，不判对错，correct 字段返回 null，解析卡显示“样例数据，解析待后端接入”。
  /// 以后：POST /practice/answer，返回 {correct: bool, explanation: String}。
  /// 作答同时写一条 practice 操作进本地队列（见 §4.8.7），联网后由 SyncService 推送。
  Future<AnswerResult> submitAnswer({
    required String sessionId,
    required String questionId,
    required List<String> chosen, // 如 ["A"] 或 ["A", "C"]
    required int durationMs,
  });

  /// 取未完成会话（供 H-B1 继续学习）。Mock：返回 null。
  /// 以后：本地 practice_records 查询。
  /// 注意：返回类型是 ContinueSession?（轻量进度指针，见 §4.3 H-B1 与
  /// §4.9.1 kv 键 home.continue），不是 PracticeSession——文档 §4.4.2
  /// 代码块此处写 PracticeSession? 与 §4.3 出入，以 §4.3 为准。
  Future<ContinueSession?> getContinueSession();
}
