/// F27 预测性预加载：套卷卡被点按时，先在后台发起前置页数据请求，
/// 再导航；前置页 initState 直接消费已就绪（或在途）的结果，打开即有
/// 数据，不再先空屏再弹出内容。
///
/// 只预加载「最可能的下一步」这一个目标：同一 setId 的预加载只发一次，
/// 结果消费后即清除（页面仍会自行同步记录等轻量数据）。预加载失败静默
/// 丢弃，页面回落到自身的加载路径（骨架 + 淡入），绝不阻塞导航。
library;

import 'dart:async';

import '../../models/bank_manifest.dart';
import '../../models/stats.dart';
import '../preload_slot.dart';
import 'bank_manifest_service.dart';
import 'question_repo.dart';

/// 前置页首屏所需的四份数据（与 SetDetailPage._load 的网络部分一一对应）。
/// 单项失败按页面原有语义降级：列表为空 / 概览为 null（UI 显示“待接口”）。
class SetDetailPreloadData {
  const SetDetailPreloadData({
    required this.modules,
    required this.manifest,
    required this.setStats,
    required this.overview,
  });

  final List<ModuleStat> modules;
  final BankManifest? manifest;
  final List<ModuleStat> setStats;
  final BankSetOverview? overview;
}

class SetDetailPreload {
  SetDetailPreload._();

  static final PreloadSlot<SetDetailPreloadData> _slot =
      PreloadSlot<SetDetailPreloadData>();

  /// 后台发起 setId 的前置页数据预加载；已在途 / 已就绪则直接返回。
  /// 不抛错、不阻塞调用方：失败只清除在途标记，由页面自行兜底。
  static void start({
    required String setId,
    required QuestionRepository repository,
    required BankManifestService manifestService,
  }) {
    _slot.start(setId, () => _fetch(setId, repository, manifestService));
  }

  /// 消费已就绪的预加载结果（取走即清除）；未就绪返回 null。
  static SetDetailPreloadData? take(String setId) => _slot.take(setId);

  /// 在途的预加载 Future；页面可 await 它而不是重新发请求。
  static Future<SetDetailPreloadData?>? pending(String setId) =>
      _slot.pending(setId);

  /// 测试辅助：清空全部预加载状态。
  static void debugClear() => _slot.debugClear();

  static Future<SetDetailPreloadData> _fetch(
    String setId,
    QuestionRepository repository,
    BankManifestService manifestService,
  ) async {
    // 四份数据相互独立：并行发起（各自兜底），总时延 ≈ 最慢一项，
    // 而不是四项串行之和——预加载的价值就在导航完成前就绪。
    Future<List<ModuleStat>> modules() async {
      try {
        return await repository.getModules();
      } catch (_) {
        return const <ModuleStat>[];
      }
    }

    Future<BankManifest?> manifest() async {
      try {
        return await manifestService.fetchManifest();
      } catch (_) {
        return null;
      }
    }

    Future<List<ModuleStat>> setStats() async {
      try {
        return await repository.getSetModuleStats(setId: setId);
      } catch (_) {
        return const <ModuleStat>[];
      }
    }

    Future<BankSetOverview?> overview() async {
      try {
        return await repository.getSetOverview(setId: setId);
      } catch (_) {
        return null;
      }
    }

    final (modulesResult, manifestResult, setStatsResult, overviewResult) =
        await (modules(), manifest(), setStats(), overview()).wait;
    return SetDetailPreloadData(
      modules: modulesResult,
      manifest: manifestResult,
      setStats: setStatsResult,
      overview: overviewResult,
    );
  }
}
