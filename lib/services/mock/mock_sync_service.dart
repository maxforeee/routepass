/// SyncService 的 Mock 实现（规格文档第 4 章 §4.7.2）。
///
/// 恒返回“本地模式，未同步”；推送直接返回成功（队列恒为空），拉取返回空增量。
library;

import '../../models/sync.dart';
import '../bank/bank_sync_service.dart';

class MockSyncService implements SyncService {
  @override
  Future<SyncStatus> getSyncStatus() async {
    return SyncStatus(pendingCount: 0, lastSyncAt: null, state: 'local_only');
  }

  @override
  Future<PushResult> pushPendingOps() async {
    return PushResult(pushedCount: 0, failedCount: 0);
  }

  @override
  Future<PullResult> pullIncremental({int? since}) async {
    return PullResult(pulledCount: 0);
  }
}
