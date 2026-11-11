// 字段名必须与规格文档 §4.8 数据契约一字不差（snake_case），故忽略本 lint。
// ignore_for_file: non_constant_identifier_names
/// 同步模型（规格文档第 4 章 §4.8 数据契约；同步协议相关结构）。
///
/// 字段名与数据契约一字不差；服务端返回的数据也必须符合同一契约，
/// 否则校验器（v3.1 附录 B）报错。
library;

/// 单条同步操作（客户端 → 服务端推送队列元素）。
class SyncOp {
  const SyncOp({
    required this.op_id,
    required this.owner_user_id,
    required this.device_id,
    required this.op_type,
    required this.payload,
    required this.created_at,
  });

  /// 操作唯一 id。
  final String op_id;

  /// 归属用户 id。
  final String owner_user_id;

  /// 产生该操作的设备 id。
  final String device_id;

  /// 操作类型：`practice` / `wrong_add` / `wrong_master` / `wrong_update` /
  /// `wrong_remove` / `favorite` / `exam_submit` / `kv_set` 之一。
  final String op_type;

  /// 操作负载（随 op_type 而异）。
  final Map<String, dynamic> payload;

  /// 创建时间戳（毫秒）。
  final int created_at;

  factory SyncOp.fromJson(Map<String, dynamic> json) {
    return SyncOp(
      op_id: json['op_id'] as String,
      owner_user_id: json['owner_user_id'] as String,
      device_id: json['device_id'] as String,
      op_type: json['op_type'] as String,
      payload: (json['payload'] as Map<dynamic, dynamic>).cast<String, dynamic>(),
      created_at: json['created_at'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'op_id': op_id,
      'owner_user_id': owner_user_id,
      'device_id': device_id,
      'op_type': op_type,
      'payload': payload,
      'created_at': created_at,
    };
  }

  @override
  String toString() => 'SyncOp($op_id, $op_type)';
}

/// 同步状态（用于同步页展示）。
class SyncStatus {
  const SyncStatus({
    required this.pendingCount,
    this.lastSyncAt,
    required this.state,
  });

  /// 待同步操作数。
  final int pendingCount;

  /// 上次同步成功时间戳（毫秒），从未同步时为 null。
  final int? lastSyncAt;

  /// 状态：`local_only` / `synced` / `pending` / `offline`。
  final String state;

  factory SyncStatus.fromJson(Map<String, dynamic> json) {
    return SyncStatus(
      pendingCount: json['pendingCount'] as int,
      lastSyncAt: json['lastSyncAt'] as int?,
      state: json['state'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'pendingCount': pendingCount,
      'lastSyncAt': lastSyncAt,
      'state': state,
    };
  }

  @override
  String toString() => 'SyncStatus($state, pending: $pendingCount)';
}

/// 推送结果。
class PushResult {
  const PushResult({required this.pushedCount, required this.failedCount});

  /// 成功推送的操作数。
  final int pushedCount;

  /// 推送失败的操作数。
  final int failedCount;

  factory PushResult.fromJson(Map<String, dynamic> json) {
    return PushResult(
      pushedCount: json['pushedCount'] as int,
      failedCount: json['failedCount'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'pushedCount': pushedCount,
      'failedCount': failedCount,
    };
  }

  @override
  String toString() => 'PushResult(pushed: $pushedCount, failed: $failedCount)';
}

/// 拉取结果。
class PullResult {
  const PullResult({required this.pulledCount, this.newPairSeq});

  /// 拉取到的记录数。
  final int pulledCount;

  /// 拉取后的最新 pair_seq 游标（无新数据时为 null）。
  final int? newPairSeq;

  factory PullResult.fromJson(Map<String, dynamic> json) {
    return PullResult(
      pulledCount: json['pulledCount'] as int,
      newPairSeq: json['newPairSeq'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'pulledCount': pulledCount,
      'newPairSeq': newPairSeq,
    };
  }

  @override
  String toString() => 'PullResult(pulled: $pulledCount, seq: $newPairSeq)';
}
