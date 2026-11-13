/// 每日一练服务抽象接口（首页 UI 方案 §11.6）。
///
/// 每日一练的题目与答题状态走可替换的数据源：现在由 Mock 顶着，后端接通后
/// 只换实现，首页组件不动。答题状态是设备本地 UI 状态（kv `daily.answer`），
/// 一天一条，不随账号同步。
library;

import '../../models/daily_question.dart';

abstract class DailyPracticeService {
  /// 取某一天的题目。同一日期必须返回同一题（按日期确定性取题）。
  Future<DailyQuestion> questionForDate(DateTime date);

  /// 某一天已选的选项 key；当天未作答返回 null。
  Future<String?> answerForDate(DateTime date);

  /// 保存某一天的作答（一天只能答一次，重复调用覆盖不了的由调用方锁定）。
  Future<void> saveAnswer({
    required DateTime date,
    required String questionId,
    required String selectedKey,
  });
}
