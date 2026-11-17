/// F27 预测性预加载：知识点详情。
///
/// 知识库页展开面板点「查看详情」时先后台发起 getPointDetail，再导航；
/// 详情页 initState 消费同一份 Future。知识库页加载完成后也会预取第一个
/// 知识点（最可能的下一步），详情页「下一知识点」切换前预取目标点。
/// 取不到（null / 抛错）静默丢弃，详情页走自身加载路径（骨架 → 不存在态）。
library;

import '../../models/knowledge_point.dart';
import '../preload_slot.dart';
import 'knowledge_repo.dart';

class KnowledgeDetailPreload {
  KnowledgeDetailPreload._();

  static final PreloadSlot<KnowledgePoint> _slot =
      PreloadSlot<KnowledgePoint>();

  static void start({
    required String kpId,
    required KnowledgeRepository repository,
  }) {
    if (kpId.isEmpty) return;
    _slot.start(kpId, () async {
      final point = await repository.getPointDetail(kpId);
      // null = 知识点不存在 / 接口未就绪：不落槽，详情页自行拉取。
      if (point == null) throw Exception('point unavailable');
      return point;
    });
  }

  static Future<KnowledgePoint?> consume({
    required String kpId,
    required KnowledgeRepository repository,
  }) {
    if (kpId.isEmpty) return Future<KnowledgePoint?>.value(null);
    return _slot.consume(kpId, () => repository.getPointDetail(kpId));
  }

  /// 测试辅助：清空全部预加载状态。
  static void debugClear() => _slot.debugClear();
}
