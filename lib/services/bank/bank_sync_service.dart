/// 同步服务抽象接口（规格文档第 4 章 §4.7.2）。
///
/// 服务的页面：首页 H-B12、G-02 版本/离线条、同步诊断。
/// 现在的实现是 Mock（返回“本地模式，未同步”）；以后真实实现走
/// `POST /sync/push`、`GET /sync/pull`、`GET /sync/status`。
library;

import '../../models/sync.dart';

abstract class SyncService {
  /// 同步状态。调用时机：进首页时 1 次、回到首页刷新、打开同步诊断时。
  /// Mock：返回 {pendingCount: 0, lastSyncAt: null, state: 'local_only'}。
  /// 以后：GET /sync/status。
  Future<SyncStatus> getSyncStatus();

  /// 推送本地操作队列。调用时机：联网后自动、用户在同步诊断点“立即同步”时。
  /// Mock：直接返回成功（队列恒为空）。以后：POST /sync/push，body 为 pending_ops（见 §4.8.7）。
  Future<PushResult> pushPendingOps();

  /// 拉取增量。调用时机：启动时、每次下拉刷新、每次回到首页时。
  /// Mock：返回空增量。以后：GET /sync/pull（游标拉取）+ GET /content/manifest。
  Future<PullResult> pullIncremental({int? since});
}
