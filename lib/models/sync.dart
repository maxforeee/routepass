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
      payload: (json['payload'] as Map<dynamic, dynamic>)
          .cast<String, dynamic>(),
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
    this.serverTime,
    this.watermark,
    this.serverReachable = false,
  });

  /// 待同步操作数。
  final int pendingCount;

  /// 上次同步成功时间戳（毫秒），从未同步时为 null。
  final int? lastSyncAt;

  /// 状态：`local_only` / `synced` / `pending` / `offline`。
  final String state;

  /// 服务器时间（`GET /sync/pull` 的 `serverTime`，ISO 字符串）。
  final String? serverTime;

  /// 服务端水位（`GET /sync/pull` 的 `watermark`）。
  final int? watermark;

  /// 这次状态查询是否真的拿到了服务端响应（而不是缓存回落）。
  ///
  /// 401 / 404 / 网络失败时为 false；首页同步条只有在它为 true 时才显示
  /// “同步模式”。缓存写回时会一并保存，但读取缓存的一方不能据此声称可达。
  final bool serverReachable;

  factory SyncStatus.fromJson(Map<String, dynamic> json) {
    return SyncStatus(
      pendingCount: (json['pendingCount'] as num?)?.toInt() ?? 0,
      lastSyncAt: (json['lastSyncAt'] as num?)?.toInt(),
      state: json['state'] as String? ?? 'local_only',
      serverTime: json['serverTime'] as String?,
      watermark: (json['watermark'] as num?)?.toInt(),
      serverReachable: json['serverReachable'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'pendingCount': pendingCount,
      'lastSyncAt': lastSyncAt,
      'state': state,
      'serverTime': serverTime,
      'watermark': watermark,
      'serverReachable': serverReachable,
    };
  }

  @override
  String toString() => 'SyncStatus($state, pending: $pendingCount)';
}

/// `GET /sync/pull` 返回的一条变更（契约字段一字不差）。
class SyncChange {
  const SyncChange({
    required this.txid,
    required this.entity,
    required this.entityId,
    required this.op,
    required this.data,
    this.clientAt,
  });

  final int txid;
  final String entity;
  final String entityId;
  final String op;
  final Map<String, dynamic> data;
  final String? clientAt;

  factory SyncChange.fromJson(Map<String, dynamic> json) {
    final rawData = json['data'];
    return SyncChange(
      txid: (json['txid'] as num?)?.toInt() ?? 0,
      entity: json['entity'] as String? ?? '',
      entityId: json['entityId'] as String? ?? '',
      op: json['op'] as String? ?? 'upsert',
      data: rawData is Map
          ? rawData.cast<String, dynamic>()
          : const <String, dynamic>{},
      clientAt: json['clientAt'] as String?,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'txid': txid,
    'entity': entity,
    'entityId': entityId,
    'op': op,
    'data': data,
    'clientAt': clientAt,
  };

  @override
  String toString() => 'SyncChange($entity/$entityId/$op @$txid)';
}

/// `GET /sync/pull` 的一页响应。
class SyncPullPage {
  const SyncPullPage({
    required this.changes,
    required this.nextCursor,
    required this.watermark,
    required this.hasMore,
    this.serverTime,
    required this.baselineRequired,
  });

  final List<SyncChange> changes;
  final int nextCursor;
  final int watermark;
  final bool hasMore;
  final String? serverTime;
  final bool baselineRequired;

  factory SyncPullPage.fromJson(Map<String, dynamic> json) {
    final rawChanges = json['changes'];
    return SyncPullPage(
      changes: rawChanges is List
          ? rawChanges
                .whereType<Map>()
                .map((e) => SyncChange.fromJson(e.cast<String, dynamic>()))
                .toList()
          : const <SyncChange>[],
      nextCursor: (json['nextCursor'] as num?)?.toInt() ?? 0,
      watermark: (json['watermark'] as num?)?.toInt() ?? 0,
      hasMore: json['hasMore'] as bool? ?? false,
      serverTime: json['serverTime'] as String?,
      baselineRequired: json['baselineRequired'] as bool? ?? false,
    );
  }

  @override
  String toString() =>
      'SyncPullPage(${changes.length} changes, cursor: $nextCursor)';
}

/// `GET /sync/baseline` 快照（服务端账号数据）。
class SyncBaseline {
  const SyncBaseline({
    required this.source,
    this.txidWatermark,
    this.generatedAt,
    required this.wrongBook,
    required this.favorites,
    required this.userKv,
    required this.dailyStats,
  });

  final String source;
  final int? txidWatermark;
  final String? generatedAt;
  final List<Map<String, dynamic>> wrongBook;
  final List<Map<String, dynamic>> favorites;
  final List<Map<String, dynamic>> userKv;
  final List<Map<String, dynamic>> dailyStats;

  int get recordCount =>
      wrongBook.length + favorites.length + userKv.length + dailyStats.length;

  factory SyncBaseline.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> listOf(Object? raw) {
      if (raw is! List) return const <Map<String, dynamic>>[];
      return raw
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
    }

    return SyncBaseline(
      source: json['source'] as String? ?? '',
      txidWatermark: (json['txidWatermark'] as num?)?.toInt(),
      generatedAt: json['generatedAt'] as String?,
      wrongBook: listOf(json['wrongBook']),
      favorites: listOf(json['favorites']),
      userKv: listOf(json['userKv']),
      dailyStats: listOf(json['dailyStats']),
    );
  }

  @override
  String toString() => 'SyncBaseline($source, $recordCount records)';
}

/// 手动同步结果（“立即同步”展示用）。
class ManualSyncResult {
  const ManualSyncResult({
    required this.ok,
    required this.message,
    this.pulledCount = 0,
    this.uploadedCount = 0,
    required this.state,
  });

  final bool ok;
  final String message;
  final int pulledCount;
  final int uploadedCount;

  /// 同步后的状态：`synced` / `pending` / `offline` / `local_only`。
  final String state;

  @override
  String toString() =>
      'ManualSyncResult($state, pulled: $pulledCount, uploaded: $uploadedCount)';
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
