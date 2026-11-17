/// F27 预测性预加载：知识点详情。
///
/// 知识库页展开面板点「查看详情」时先后台发起 getPointDetail，再导航；
/// 详情页 initState 消费同一份 Future。用户首次展开知识点面板时预取该点
/// （最可能的下一步），详情页「下一知识点」切换前预取目标点。
/// 取不到（null / 抛错）静默丢弃、不落槽：详情页消费时回落自身拉取，
/// 不会把预加载的 null 当成「知识点不存在」。
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
    // null = 知识点不存在 / 接口未就绪：槽位不落缓存（也不存失败 Future），
    // 详情页消费时回落重新拉取，失败语义是一个值而不是一次抛错。
    _slot.start(kpId, () => repository.getPointDetail(kpId));
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
