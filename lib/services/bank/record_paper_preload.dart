/// F27 预测性预加载：记录试卷页数据。
///
/// 记录详情页点「查看试卷」时先后台发起 `GET /practice/records/{id}/paper`，
/// 再导航；试卷页 initState 消费同一份 Future，打开即有卷面。
/// 拉取失败（null / 抛错）静默丢弃，试卷页走自身加载路径（骨架 → 重试态）。
library;

import '../../models/practice.dart';
import '../preload_slot.dart';
import 'practice_service.dart';

class RecordPaperPreload {
  RecordPaperPreload._();

  static final PreloadSlot<PracticeRecordPaper> _slot =
      PreloadSlot<PracticeRecordPaper>();

  static void start({
    required String sessionId,
    required PracticeService service,
  }) {
    if (sessionId.isEmpty) return;
    // null = 接口未就绪 / 离线：槽位不落缓存（也不存失败 Future），
    // 试卷页消费时回落自行拉取并显示重试态。
    _slot.start(sessionId, () => service.getRecordPaper(sessionId));
  }

  /// 已就绪结果（取走即清除）；供试卷页 initState 首帧同步应用，
  /// 打开即有卷面、无骨架闪烁。未就绪返回 null。
  static PracticeRecordPaper? take(String sessionId) => _slot.take(sessionId);

  static Future<PracticeRecordPaper?> consume({
    required String sessionId,
    required PracticeService service,
  }) {
    if (sessionId.isEmpty) return Future<PracticeRecordPaper?>.value(null);
    return _slot.consume(sessionId, () => service.getRecordPaper(sessionId));
  }

  /// 测试辅助：清空全部预加载状态。
  static void debugClear() => _slot.debugClear();
}
