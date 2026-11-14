/// QuestionRepository 的 cache-first 装饰器（F19）。
///
/// 只改「前置页计数」的读路径：
/// 1. 先读本地 SQLite `set_overview`，命中立即返回（离线可用）；
/// 2. 命中后若 [backgroundRefresh] 为 true，后台静默拉一次服务端并更新缓存；
/// 3. 未命中才拉服务端（HTTP 概览接口或注入的仓储），成功即写缓存；
/// 4. 服务端失败 / 接口未就绪返回 null，UI 继续显示原有“待接口”文案。
///
/// 其余方法原样委托给 [delegate]，不改变现存行为。
library;

import 'dart:async';

import '../../models/question.dart';
import '../../models/stats.dart';
import 'local_cache_service.dart';
import 'question_bank_source.dart';
import 'question_repo.dart';

class CachedQuestionRepository implements QuestionRepository {
  CachedQuestionRepository({
    required this.delegate,
    required this.cache,
    this.overviewSource,
    this.backgroundRefresh = true,
  });

  final QuestionRepository delegate;
  final BankLocalCache cache;
  final BankSetOverviewSource? overviewSource;

  /// 缓存命中后是否后台刷新（生产 true，单元测试可关）。
  final bool backgroundRefresh;

  @override
  Future<BankSetOverview?> getSetOverview({required String setId}) async {
    final cached = await cache.readOverview(setId);
    if (cached != null) {
      if (backgroundRefresh) {
        unawaited(_refresh(setId));
      }
      return cached;
    }
    return _refresh(setId);
  }

  Future<BankSetOverview?> _refresh(String setId) async {
    try {
      final source = overviewSource;
      final overview = source != null
          ? await source.fetchOverview(setId)
          : await delegate.getSetOverview(setId: setId);
      if (overview == null) return null;
      await cache.writeOverview(overview);
      return overview;
    } catch (_) {
      // 离线 / 接口未就绪：静默失败，保留缓存值（没有缓存则返回 null）。
      return null;
    }
  }

  @override
  Future<List<ModuleStat>> getModules() => delegate.getModules();

  @override
  Future<List<Question>> drawQuestions({
    required String mode,
    required int drawCount,
    String? module,
    String? knowledgePointId,
  }) => delegate.drawQuestions(
    mode: mode,
    drawCount: drawCount,
    module: module,
    knowledgePointId: knowledgePointId,
  );

  @override
  Future<Question?> getQuestionById(String id) => delegate.getQuestionById(id);

  @override
  Future<List<ModuleStat>> getSetModuleStats({required String setId}) =>
      delegate.getSetModuleStats(setId: setId);
}
