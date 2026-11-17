/// F27 预测性预加载：答题页（QuizPage）入口数据。
///
/// 前置页 → 答题页（practice）首次进入的真实网络开销，是 cache-first 层
/// 从公开 `/bank/questions` 分页拉取整套题库并写入本地 SQLite
/// （CachedPracticeService.drawNextQuestion 的冷缓存路径）。这里在前置页
/// 后台预热该缓存：预热完成后首题抽题直接命中本地，点「开始练习」即开。
///
/// 只预热题库（纯读 + 写缓存），不调 startPracticeSession / startExamPaper：
/// 二者会在服务端创建会话 / 考卷，预创建会留下废弃会话。考试入口不预加载，
/// 由答题页自身加载态兜底。预热失败静默，绝不阻塞页面与导航。
library;

import 'cached_practice_service.dart';
import 'practice_service.dart';

class AnswerEntryPreload {
  AnswerEntryPreload._();

  /// 同一 setId 的在途预热标记：预测预热与点按预热不重复拉取。
  static final Set<String> _warming = <String>{};

  /// 后台预热 setId 的本地题库。非 cache-first 实现（Mock / 纯 HTTP）
  /// 没有本地题库可预热，直接 no-op；已有缓存时 warmQuestionBank 自身短路。
  static void start({
    required String setId,
    required PracticeService service,
  }) {
    if (setId.isEmpty || _warming.contains(setId)) return;
    if (service is! CachedPracticeService) return;
    _warming.add(setId);
    service
        .warmQuestionBank(setId: setId)
        .whenComplete(() => _warming.remove(setId));
  }

  /// 测试辅助：清空在途标记。
  static void debugClear() => _warming.clear();
}
