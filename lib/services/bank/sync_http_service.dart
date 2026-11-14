/// 真实同步服务（F19：个人中心“同步”区）。
///
/// 契约来源：`/workspace/routepass-server/api/app/api/v1/sync.py`。
/// - `GET  /api/v1/sync/pull?cursor=&limit=`：增量变更 + watermark/serverTime；
/// - `POST /api/v1/sync/push`：逐条 UPSERT（`opId` 幂等）；
/// - `GET  /api/v1/sync/baseline`：账号数据快照（wrongBook / favorites /
///   userKv / dailyStats）。
///
/// 手动同步是两向 MERGE，绝不整表覆盖：先读服务端记录状态，再按记录 id +
/// clientAt 做 last-write-wins；本地 0 条而服务端有数据时只拉不推。
/// 接口未上线（404）/ 未鉴权（401）/ 网络失败时保留本地缓存，不编造状态。
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config.dart';
import '../../core/kv_store.dart';
import '../../core/service_locator.dart';
import '../../models/sync.dart';
import 'bank_sync_service.dart';
import 'local_cache_service.dart';

/// 同步 HTTP 实现。
class HttpSyncService implements SyncService {
  HttpSyncService({
    http.Client? client,
    String? baseUrl,
    this.tokenProvider,
    KvStore? kvStore,
    this.localCache,
  }) : _client = client ?? http.Client(),
       _baseUrl = baseUrl ?? AppConfig.baseUrl,
       _kv = kvStore ?? ServiceLocator.kvStore;

  final http.Client _client;
  final String _baseUrl;

  /// 返回 accessToken 的回调；null / 空串表示未登录。
  final String? Function()? tokenProvider;

  final KvStore _kv;
  final BankLocalCache? localCache;

  static const Duration _timeout = Duration(seconds: 8);
  static const int _pullLimit = 200;
  static const int _maxPullPages = 20;

  @override
  SyncStatus? get cachedStatus => _readCachedStatus();

  @override
  Future<SyncStatus> getSyncStatus() async {
    final pending = (await _pendingOps()).length;
    final cached = _readCachedStatus();
    if (!_loggedIn) {
      final status = SyncStatus(
        pendingCount: pending,
        lastSyncAt: cached?.lastSyncAt,
        state: 'local_only',
        serverTime: cached?.serverTime,
        watermark: cached?.watermark,
      );
      _writeCachedStatus(status);
      return status;
    }

    final response = await _get('/api/v1/sync/pull?cursor=$_cursor&limit=1');
    if (response == null) {
      // 网络不可达：保留上次读到的同步时间与服务器信息，状态标离线。
      return SyncStatus(
        pendingCount: pending,
        lastSyncAt: cached?.lastSyncAt,
        state: 'offline',
        serverTime: cached?.serverTime,
        watermark: cached?.watermark,
      );
    }
    if (response.statusCode != 200) {
      // 401 / 404：接口未就绪或未鉴权，保留缓存，不假装已同步。
      return SyncStatus(
        pendingCount: pending,
        lastSyncAt: cached?.lastSyncAt,
        state: pending > 0 ? 'pending' : (cached?.state ?? 'local_only'),
        serverTime: cached?.serverTime,
        watermark: cached?.watermark,
      );
    }

    final page = SyncPullPage.fromJson(response.body);
    final status = SyncStatus(
      pendingCount: pending,
      lastSyncAt: DateTime.now().millisecondsSinceEpoch,
      state: pending > 0 ? 'pending' : 'synced',
      serverTime: page.serverTime,
      watermark: page.watermark,
      serverReachable: true,
    );
    _writeCachedStatus(status);
    return status;
  }

  @override
  Future<PushResult> pushPendingOps() async {
    if (!_loggedIn) return const PushResult(pushedCount: 0, failedCount: 0);
    final ops = await _pendingOps();
    if (ops.isEmpty) return const PushResult(pushedCount: 0, failedCount: 0);
    final outcome = await _push(ops);
    if (outcome == null) {
      return PushResult(pushedCount: 0, failedCount: ops.length);
    }
    await _markSynced(outcome.handledOpIds);
    return outcome.result;
  }

  @override
  Future<PullResult> pullIncremental({int? since}) async {
    if (!_loggedIn) return const PullResult(pulledCount: 0);
    final cursor = since ?? _cursor;
    final response = await _get(
      '/api/v1/sync/pull?cursor=$cursor&limit=$_pullLimit',
    );
    if (response == null || response.statusCode != 200) {
      return const PullResult(pulledCount: 0);
    }
    final page = SyncPullPage.fromJson(response.body);
    final applied = await _applyServerChanges(page.changes);
    _writeCursor(page.nextCursor);
    _writeCachedStatus(
      SyncStatus(
        pendingCount: (await _pendingOps()).length,
        lastSyncAt: DateTime.now().millisecondsSinceEpoch,
        state: 'synced',
        serverTime: page.serverTime,
        watermark: page.watermark,
        serverReachable: true,
      ),
    );
    return PullResult(
      pulledCount: applied,
      newPairSeq: page.nextCursor == 0 ? null : page.nextCursor,
    );
  }

  @override
  Future<ManualSyncResult> syncNow() async {
    if (!_loggedIn) {
      return const ManualSyncResult(
        ok: false,
        message: '未登录，无法同步',
        state: 'local_only',
      );
    }

    final cached = _readCachedStatus();
    final baseline = await _fetchBaseline();
    final pulled = await _pullAll();
    if (pulled == null) {
      final status = SyncStatus(
        pendingCount: (await _pendingOps()).length,
        lastSyncAt: cached?.lastSyncAt,
        state: 'offline',
        serverTime: cached?.serverTime,
        watermark: cached?.watermark,
      );
      _writeCachedStatus(status);
      return const ManualSyncResult(
        ok: false,
        message: '无法连接服务器，已保留本地数据',
        state: 'offline',
      );
    }

    final ops = await _pendingOps();
    final localCount = ops.length + _localAnswerRecordCount();
    final serverCount = baseline?.recordCount ?? pulled.changes.length;
    var pulledCount = await _applyServerBaseline(baseline);
    pulledCount += await _applyServerChanges(pulled.changes);

    // 安全闸门：本地没有任何记录而服务端有数据时，只拉取，绝不上传。
    if (localCount == 0 && serverCount > 0) {
      final status = SyncStatus(
        pendingCount: 0,
        lastSyncAt: DateTime.now().millisecondsSinceEpoch,
        state: 'synced',
        serverTime: pulled.serverTime,
        watermark: pulled.watermark,
        serverReachable: true,
      );
      _writeCachedStatus(status);
      return ManualSyncResult(
        ok: true,
        message: '本地无数据，已从服务器拉取 $pulledCount 条',
        pulledCount: pulledCount,
        uploadedCount: 0,
        state: 'synced',
      );
    }

    var uploadedCount = 0;
    if (ops.isNotEmpty) {
      final outcome = await _push(ops);
      if (outcome == null) {
        final status = SyncStatus(
          pendingCount: ops.length,
          lastSyncAt: cached?.lastSyncAt,
          state: 'pending',
          serverTime: pulled.serverTime,
          watermark: pulled.watermark,
          serverReachable: true,
        );
        _writeCachedStatus(status);
        return ManualSyncResult(
          ok: false,
          message: '上传失败，${ops.length} 条保留在本地',
          pulledCount: pulledCount,
          state: 'pending',
        );
      }
      uploadedCount = outcome.result.pushedCount;
      await _markSynced(outcome.handledOpIds);

      // 推完再拉一次，拿回服务端因本次上传产生的新变更。
      final after = await _pullAll();
      if (after != null) {
        pulledCount += await _applyServerChanges(after.changes);
      }
    }

    final remaining = (await _pendingOps()).length;
    final status = SyncStatus(
      pendingCount: remaining,
      lastSyncAt: DateTime.now().millisecondsSinceEpoch,
      state: remaining > 0 ? 'pending' : 'synced',
      serverTime: pulled.serverTime,
      watermark: pulled.watermark,
      serverReachable: true,
    );
    _writeCachedStatus(status);

    final message = uploadedCount > 0
        ? '同步完成：拉取 $pulledCount 条，上传 $uploadedCount 条'
        : pulledCount > 0
        ? '同步完成：拉取 $pulledCount 条'
        : '已是最新';
    return ManualSyncResult(
      ok: true,
      message: message,
      pulledCount: pulledCount,
      uploadedCount: uploadedCount,
      state: status.state,
    );
  }

  bool get _loggedIn {
    final token = tokenProvider?.call();
    return token != null && token.isNotEmpty;
  }

  Map<String, String> get _headers {
    final token = tokenProvider?.call();
    return <String, String>{
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  int get _cursor =>
      int.tryParse(_kv.getString(KvStore.keySyncCursor) ?? '') ?? 0;

  void _writeCursor(int cursor) {
    _kv.setString(KvStore.keySyncCursor, '$cursor');
  }

  SyncStatus? _readCachedStatus() {
    final raw = _kv.getString(KvStore.keySyncStatus);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return SyncStatus.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  void _writeCachedStatus(SyncStatus status) {
    _kv.setString(KvStore.keySyncStatus, jsonEncode(status.toJson()));
  }

  Future<List<LocalSyncOp>> _pendingOps() async {
    final cache = localCache;
    if (cache == null) return const <LocalSyncOp>[];
    try {
      return await cache.pendingSync(limit: 200);
    } catch (_) {
      return const <LocalSyncOp>[];
    }
  }

  Future<void> _markSynced(List<String> opIds) async {
    final cache = localCache;
    if (cache == null) return;
    for (final id in opIds) {
      try {
        await cache.markSyncOpSynced(id);
      } catch (_) {
        // 单条标记失败下次会重推，opId 幂等。
      }
    }
  }

  int _localAnswerRecordCount() {
    final raw = _kv.getString(KvStore.keyAnswerRecords);
    if (raw == null || raw.isEmpty) return 0;
    try {
      final decoded = jsonDecode(raw);
      return decoded is List ? decoded.length : 0;
    } catch (_) {
      return 0;
    }
  }

  Future<_HttpResponse?> _get(String path) async {
    try {
      final response = await _client
          .get(Uri.parse('$_baseUrl$path'), headers: _headers)
          .timeout(_timeout);
      return _HttpResponse(response.statusCode, _decodeBody(response));
    } catch (_) {
      return null;
    }
  }

  Future<_HttpResponse?> _post(String path, Map<String, Object?> body) async {
    try {
      final response = await _client
          .post(
            Uri.parse('$_baseUrl$path'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      return _HttpResponse(response.statusCode, _decodeBody(response));
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _decodeBody(http.Response response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // 非 JSON 响应按空体处理。
    }
    return const <String, dynamic>{};
  }

  Future<SyncBaseline?> _fetchBaseline() async {
    final response = await _get('/api/v1/sync/baseline');
    if (response == null || response.statusCode != 200) return null;
    return SyncBaseline.fromJson(response.body);
  }

  /// 游标分页拉完所有变更；任一页失败返回 null（调用方保留本地状态）。
  Future<_Pulled?> _pullAll() async {
    var cursor = _cursor;
    var watermark = 0;
    String? serverTime;
    final changes = <SyncChange>[];
    for (var page = 0; page < _maxPullPages; page++) {
      final response = await _get(
        '/api/v1/sync/pull?cursor=$cursor&limit=$_pullLimit',
      );
      if (response == null || response.statusCode != 200) return null;
      final parsed = SyncPullPage.fromJson(response.body);
      changes.addAll(parsed.changes);
      watermark = parsed.watermark;
      serverTime = parsed.serverTime ?? serverTime;
      cursor = parsed.nextCursor;
      _writeCursor(cursor);
      if (!parsed.hasMore) break;
    }
    return _Pulled(
      changes: changes,
      cursor: cursor,
      watermark: watermark,
      serverTime: serverTime,
    );
  }

  /// 推送本地待同步队列。任何一条不支持的类型跳过并计入失败，不编造载荷。
  Future<_PushOutcome?> _push(List<LocalSyncOp> ops) async {
    final changes = <Map<String, Object?>>[];
    final changeOpIds = <String>[];
    var skipped = 0;
    for (final op in ops) {
      final change = _changeFor(op);
      if (change == null) {
        skipped++;
        continue;
      }
      changes.add(change);
      changeOpIds.add(op.opId);
    }
    if (changes.isEmpty) {
      return _PushOutcome(
        result: PushResult(pushedCount: 0, failedCount: skipped),
        handledOpIds: const <String>[],
      );
    }

    final response = await _post('/api/v1/sync/push', <String, Object?>{
      'changes': changes,
    });
    if (response == null || response.statusCode != 200) return null;

    final results = response.body['results'];
    final accepted = <String>{};
    if (results is List) {
      for (final item in results) {
        if (item is! Map) continue;
        final opId = item['opId'] as String?;
        final status = item['status'] as String?;
        if (opId != null && (status == 'accepted' || status == 'duplicated')) {
          accepted.add(opId);
        }
      }
    }
    final handled = <String>[];
    for (var i = 0; i < changeOpIds.length; i++) {
      final pushedId = changes[i]['opId'] as String;
      if (accepted.contains(pushedId)) handled.add(changeOpIds[i]);
    }
    return _PushOutcome(
      result: PushResult(
        pushedCount: handled.length,
        failedCount: changeOpIds.length - handled.length + skipped,
      ),
      handledOpIds: handled,
    );
  }

  /// 本地队列 → `POST /sync/push` 的一条 change。
  ///
  /// 练习作答按后端 `attempts` 实体上传：questionId + answer 数组 +
  /// durationSec + mode。其余类型（后端没有对应上传契约）不猜，返回 null。
  Map<String, Object?>? _changeFor(LocalSyncOp op) {
    if (op.kind != LocalSyncOp.kindPracticeAnswer) return null;
    final payload = op.payload;
    final questionId = payload['questionId'] as String?;
    final chosen = payload['chosen'];
    if (questionId == null || questionId.isEmpty || chosen is! List) {
      return null;
    }
    final durationMs = (payload['durationMs'] as num?)?.toInt() ?? 0;
    return <String, Object?>{
      'entity': 'attempts',
      'entityId': questionId,
      'op': 'upsert',
      'opId': _pushOpId(op.opId, op.createdAt),
      'clientAt': _iso(op.createdAt),
      'data': <String, Object?>{
        'questionId': questionId,
        'answer': chosen,
        'durationSec': (durationMs / 1000).round(),
        'mode': payload['mode'] as String? ?? 'practice',
      },
    };
  }

  /// 服务端 opId 上限 40 字符；本地幂等键可能更长，用稳定短哈希代替。
  static String _pushOpId(String raw, int createdAt) {
    if (raw.isNotEmpty && raw.length <= 40) return raw;
    var hash = 0x811c9dc5;
    for (final unit in raw.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return 'op-${hash.toRadixString(16).padLeft(8, '0')}-$createdAt';
  }

  static String _iso(int ms) =>
      DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String();

  Future<int> _applyServerBaseline(SyncBaseline? baseline) async {
    if (baseline == null) return 0;
    final mirror = _readMirror();
    var applied = 0;

    bool apply(
      String entity,
      String id,
      Map<String, dynamic> data,
      String? clientAt,
    ) {
      if (entity.isEmpty || id.isEmpty) return false;
      final key = '$entity|$id';
      final existing = mirror[key];
      if (existing != null &&
          !_isNewer(clientAt, existing['clientAt'] as String?)) {
        return false;
      }
      mirror[key] = <String, dynamic>{
        'entity': entity,
        'entityId': id,
        'data': data,
        'clientAt': clientAt,
      };
      return true;
    }

    for (final item in baseline.wrongBook) {
      final id = item['questionId'];
      if (id is! String) continue;
      if (apply('wrong_book', id, item, item['lastWrongAt'] as String?)) {
        applied++;
      }
    }
    for (final item in baseline.favorites) {
      final id = item['questionId'];
      if (id is! String) continue;
      if (apply('favorites', id, item, item['createdAt'] as String?)) {
        applied++;
      }
    }
    for (final item in baseline.userKv) {
      final id = item['key'];
      if (id is! String) continue;
      if (apply('user_kv', id, item, item['clientAt'] as String?)) applied++;
    }
    for (final item in baseline.dailyStats) {
      final id = item['date'];
      if (id is! String) continue;
      if (apply('daily_stats', id, item, null)) applied++;
    }

    if (applied > 0) _writeMirror(mirror);
    return applied;
  }

  Future<int> _applyServerChanges(List<SyncChange> changes) async {
    if (changes.isEmpty) return 0;
    final mirror = _readMirror();
    var applied = 0;
    for (final change in changes) {
      if (change.entity.isEmpty || change.entityId.isEmpty) continue;
      final key = '${change.entity}|${change.entityId}';
      final existing = mirror[key];
      if (change.op == 'delete') {
        // 服务端明确删除才移除本地镜像；本地设备没有的记录本就不会删。
        if (mirror.remove(key) != null) applied++;
        continue;
      }
      if (existing != null &&
          !_isNewer(change.clientAt, existing['clientAt'] as String?)) {
        // 本地镜像更新（last-write-wins），保留本地。
        continue;
      }
      mirror[key] = <String, dynamic>{
        'entity': change.entity,
        'entityId': change.entityId,
        'data': change.data,
        'clientAt': change.clientAt,
      };
      applied++;
    }
    if (applied > 0) _writeMirror(mirror);
    return applied;
  }

  /// incoming 比 existing 新（或 existing 没有时间）才覆盖。
  static bool _isNewer(String? incoming, String? existing) {
    if (incoming == null) return existing == null;
    if (existing == null) return true;
    return incoming.compareTo(existing) >= 0;
  }

  Map<String, dynamic> _readMirror() {
    final raw = _kv.getString(KvStore.keySyncMirror);
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // 损坏镜像丢弃，按空处理（下次拉取重建）。
    }
    return <String, dynamic>{};
  }

  void _writeMirror(Map<String, dynamic> mirror) {
    _kv.setString(KvStore.keySyncMirror, jsonEncode(mirror));
  }
}

class _HttpResponse {
  const _HttpResponse(this.statusCode, this.body);

  final int statusCode;
  final Map<String, dynamic> body;
}

class _Pulled {
  const _Pulled({
    required this.changes,
    required this.cursor,
    required this.watermark,
    required this.serverTime,
  });

  final List<SyncChange> changes;
  final int cursor;
  final int watermark;
  final String? serverTime;
}

class _PushOutcome {
  const _PushOutcome({required this.result, required this.handledOpIds});

  final PushResult result;
  final List<String> handledOpIds;
}
