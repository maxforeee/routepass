/// 本地答题记录服务（F19）。
///
/// 记录存 kv `answer.records`（JSON 数组，按 updatedAt 倒序）；全局最多
/// 100 条、单 set 最多 20 条，写入时裁剪。断点同 `setId+mode` 只保留
/// 一条（后写覆盖，id 复用）；完成记录同一次会话只更新不新建。
///
/// 离线缓存与 S11 `GET /practice/records` 的调和：
/// - 服务端记录是权威（完成会话 + 进行中的断点会话）；
/// - [AnswerRecordService.syncFromServer] 把已完成的会话并入本地列表
///   （`targetCount = answeredCount`，即服务端的最终题数），并把匹配的
///   本地断点标记为已同步；
/// - 服务端没有批量上传接口，本地未确认记录继续保留在 [pendingSync]；
/// - 进行中的服务端会话不凭空造展示记录（本地卡片需要目标题数，服务端
///   记录不提供，编一个就是假进度）。
library;

import 'dart:convert';
import 'dart:math';

import '../../core/kv_store.dart';
import '../../core/service_locator.dart';
import '../../models/answer_record.dart';
import '../../models/practice.dart';

abstract class AnswerRecordService {
  /// 指定套卷 / 模式的记录，按 `updatedAt` 倒序，最多 10 条。
  List<AnswerRecord> recordsFor({required String setId, required String mode});

  /// 指定套卷 / 模式的断点记录（没有返回 null）。
  AnswerRecord? breakpointOf({required String setId, required String mode});

  /// 写入或更新：完成记录按 id 更新；断点按 `setId+mode` 去重。
  void upsert(AnswerRecord record);

  void remove(String id);

  /// 尚未同步的记录。
  List<AnswerRecord> pendingSync();

  /// 标记已同步并回填服务端 id。
  void markSynced(String id, String serverId);

  /// 与服务端记录调和（S11 `GET /practice/records`）。接口未就绪或无数据源
  /// 时为 no-op；失败静默，本地记录照常展示。
  Future<void> syncFromServer() async {}
}

class KvAnswerRecordService implements AnswerRecordService {
  KvAnswerRecordService({KvStore? kvStore, this.serverRecords})
    : _kv = kvStore ?? ServiceLocator.kvStore;

  final KvStore _kv;

  /// 服务端记录来源（生产为 `HttpPracticeService.fetchPracticeRecords`）。
  final Future<List<PracticeRecordSummary>> Function()? serverRecords;

  static const int _maxTotal = 100;
  static const int _maxPerSet = 20;
  static const int _maxForDisplay = 10;
  static const String _serverPrefix = 'srv-';

  @override
  List<AnswerRecord> recordsFor({required String setId, required String mode}) {
    return _read()
        .where((r) => r.setId == setId && r.mode == mode)
        .take(_maxForDisplay)
        .toList();
  }

  @override
  AnswerRecord? breakpointOf({required String setId, required String mode}) {
    for (final r in _read()) {
      if (r.setId == setId && r.mode == mode && r.isBreakpoint) return r;
    }
    return null;
  }

  @override
  void upsert(AnswerRecord record) {
    final records = _read();
    var incoming = record;

    // 断点：同一 setId+mode 只保留一条，复用已有 id / createdAt。
    if (record.isBreakpoint) {
      for (final existing in records) {
        if (existing.isBreakpoint &&
            existing.setId == record.setId &&
            existing.mode == record.mode &&
            existing.id != record.id) {
          incoming = incoming.copyWith(
            id: existing.id,
            createdAt: existing.createdAt,
          );
          break;
        }
      }
      records.removeWhere(
        (r) =>
            r.isBreakpoint &&
            r.setId == incoming.setId &&
            r.mode == incoming.mode &&
            r.id != incoming.id,
      );
    }

    final index = records.indexWhere((r) => r.id == incoming.id);
    if (index >= 0) {
      records[index] = incoming;
    } else {
      records.add(incoming);
    }

    records.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    _write(_trim(records));
  }

  @override
  void remove(String id) {
    final records = _read()..removeWhere((r) => r.id == id);
    _write(records);
  }

  @override
  List<AnswerRecord> pendingSync() {
    return _read().where((r) => !r.synced).toList();
  }

  @override
  void markSynced(String id, String serverId) {
    final records = _read();
    final index = records.indexWhere((r) => r.id == id);
    if (index < 0) return;
    records[index] = records[index].copyWith(synced: true, serverId: serverId);
    _write(records);
  }

  /// 全局 100 条 + 单 set 20 条，超出丢最旧。
  List<AnswerRecord> _trim(List<AnswerRecord> sortedDesc) {
    final kept = <AnswerRecord>[];
    final perSet = <String, int>{};
    for (final record in sortedDesc) {
      final count = perSet[record.setId] ?? 0;
      if (count >= _maxPerSet) continue;
      kept.add(record);
      perSet[record.setId] = count + 1;
      if (kept.length >= _maxTotal) break;
    }
    return kept;
  }

  List<AnswerRecord> _read() {
    final raw = _kv.getString(KvStore.keyAnswerRecords);
    if (raw == null || raw.isEmpty) return <AnswerRecord>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <AnswerRecord>[];
      final records = <AnswerRecord>[];
      for (final item in decoded) {
        if (item is! Map<String, dynamic>) continue;
        try {
          records.add(AnswerRecord.fromJson(item));
        } catch (_) {
          // 损坏记录丢弃，不抛错。
        }
      }
      records.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return records;
    } catch (_) {
      return <AnswerRecord>[];
    }
  }

  void _write(List<AnswerRecord> records) {
    _kv.setString(
      KvStore.keyAnswerRecords,
      jsonEncode(records.map((r) => r.toJson()).toList()),
    );
  }

  /// 生成记录 id：`rec-<createdAt>-<4 位随机>`。
  static String newRecordId(int createdAt) {
    final suffix = (Random().nextInt(9000) + 1000).toString();
    return 'rec-$createdAt-$suffix';
  }

  @override
  Future<void> syncFromServer() async {
    final fetch = serverRecords;
    if (fetch == null) return;
    final List<PracticeRecordSummary> items;
    try {
      items = await fetch();
    } catch (_) {
      return;
    }
    if (items.isEmpty) return;

    final records = _read();
    var changed = false;
    for (final item in items) {
      if (item.id.isEmpty) continue;
      final serverId = '$_serverPrefix${item.id}';
      final existingIndex = records.indexWhere(
        (r) => r.serverId == item.id || r.id == serverId,
      );

      if (!item.isCompleted) {
        // 进行中的服务端会话：只把同模块的本地断点标记已同步，不造展示记录。
        final localIndex = records.indexWhere(
          (r) => r.isBreakpoint && r.setId == item.module && r.serverId == null,
        );
        if (localIndex >= 0) {
          records[localIndex] = records[localIndex].copyWith(
            synced: true,
            serverId: item.id,
          );
          changed = true;
        }
        continue;
      }

      final updatedAt = item.completedAt ?? item.startedAt;
      final mapped = AnswerRecord(
        id: serverId,
        setId: item.module,
        setTitle: item.module.isEmpty ? '全部' : item.module,
        mode: 'practice',
        kind: 'completion',
        // 服务端完成记录只给最终题数（>= 20），它就是这次会话的目标。
        targetCount: item.answeredCount,
        answeredCount: item.answeredCount,
        totalCount: item.answeredCount,
        correctCount: item.correctCount,
        // 服务端记录不带用时：有 completedAt 时用会话时长，否则 0（未知）。
        durationMs: item.completedAt == null
            ? 0
            : item.completedAt! - item.startedAt,
        createdAt: item.startedAt,
        updatedAt: updatedAt,
        synced: true,
        serverId: item.id,
      );
      if (existingIndex >= 0) {
        records[existingIndex] = mapped;
      } else {
        records.add(mapped);
      }
      changed = true;
    }
    if (!changed) return;
    records.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    _write(_trim(records));
  }
}
