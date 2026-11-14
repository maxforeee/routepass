/// 本地答题记录服务（F19）。
///
/// 记录存 kv `answer.records`（JSON 数组，按 updatedAt 倒序）；全局最多
/// 100 条、单 set 最多 20 条，写入时裁剪。断点同 `setId+mode` 只保留
/// 一条（后写覆盖，id 复用）；完成记录同一次会话只更新不新建。
/// 同步字段 `synced=false` 先落盘，`pendingSync()` 供后端
/// `POST /practice/records` 就绪后 flush。
library;

import 'dart:convert';
import 'dart:math';

import '../../core/kv_store.dart';
import '../../core/service_locator.dart';
import '../../models/answer_record.dart';

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
}

class KvAnswerRecordService implements AnswerRecordService {
  KvAnswerRecordService({KvStore? kvStore})
    : _kv = kvStore ?? ServiceLocator.kvStore;

  final KvStore _kv;

  static const int _maxTotal = 100;
  static const int _maxPerSet = 20;
  static const int _maxForDisplay = 10;

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
}
