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

  /// 手动同步（“立即同步”）：两向 MERGE，绝不整表覆盖。
  ///
  /// 安全规则（见 tasks/f19_sync_strip.md）：
  /// 1. 先读服务端记录状态（`GET /sync/baseline` + `GET /sync/pull`）；
  /// 2. 本地 0 条且服务端有数据 → 不上传，只拉取到本地同步镜像
  ///    （`sync.mirror`），并如实回报“已拉取到镜像 X 条”，不谎称应用数据已恢复；
  /// 3. 两边都有数据 → 按记录 id + clientAt 逐条 last-write-wins；
  /// 4. 上传只做逐条 UPSERT，绝不整表覆盖 / 删除服务端独有记录；
  /// 5. 结果回报拉取 / 上传条数。
  Future<ManualSyncResult> syncNow();

  /// 上次读到的同步状态（本地缓存），未读过返回 null。
  /// 页面先展示它，再后台刷新，断网时仍可用。
  SyncStatus? get cachedStatus => null;
}
