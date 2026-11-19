/// WrongService / FavoriteService 的 SQLite 持久实现（F36，规格文档
/// 第 4 章 §4.4.4 / §4.8.5，客户端表 `wrong_book` / `favorites`）。
///
/// 与 Mock 的区别：数据落本地 SQLite（与题库缓存共用同一个
/// `LocalDatabase` / `routepass.db`），重启不丢；不预置演示数据，
/// 空库读回空（诚实空态）。合并语义与 Mock 一字不差：
/// last-write-wins（服务端更旧保留本地），错题墓碑（removed_at）
/// 不被更旧的服务端数据复活。读路径按需查 SQLite，不做启动阻塞加载。
library;

import '../../core/local_db.dart';
import '../../models/wrong_favorite.dart';
import 'favorite_service.dart';
import 'wrong_service.dart';

/// 错题本持久实现：`wrong_book` 表，一行一题。
class SqliteWrongService implements WrongService {
  SqliteWrongService(this._db);

  final LocalDatabase _db;

  static const String _columns =
      'question_id, wrong_count, last_wrong_at, mastered, removed_at';

  @override
  Future<List<WrongItem>> getWrongBook({
    String? module,
    bool? masteredOnly,
  }) async {
    // 与 Mock 一致：本地表没有模块列，module 过滤由 HTTP 层负责。
    final rows = await _db.rawQuery(
      'SELECT $_columns FROM wrong_book WHERE removed_at IS NULL'
      '${masteredOnly == null ? '' : ' AND mastered = ?'}'
      ' ORDER BY last_wrong_at DESC',
      masteredOnly == null ? null : <Object?>[masteredOnly ? 1 : 0],
    );
    return rows.map(_fromRow).toList();
  }

  @override
  Future<void> addWrong(String questionId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    // wrong_add：次数 +1、mastered 置回 false（§4.8.7）；再做错即复活，
    // 清掉墓碑（与 Mock 重建条目时 removed_at 归 null 的行为一致）。
    await _db.rawExecute(
      'INSERT INTO wrong_book ($_columns) VALUES (?, 1, ?, 0, NULL) '
      'ON CONFLICT(question_id) DO UPDATE SET '
      'wrong_count = wrong_count + 1, '
      'last_wrong_at = excluded.last_wrong_at, '
      'mastered = 0, removed_at = NULL',
      <Object?>[questionId, now],
    );
  }

  @override
  Future<void> markMastered(String questionId) async {
    // 不存在则 no-op（与 Mock 一致）；保留 removed_at 不动。
    await _db.rawExecute(
      'UPDATE wrong_book SET mastered = 1 WHERE question_id = ?',
      <Object?>[questionId],
    );
  }

  @override
  Future<void> removeWrong(
    String questionId, {
    String reason = 'user_removed',
  }) async {
    // F36：写墓碑而不是删行——getWrongBook 过滤 removed_at，
    // mergeFromServer 不让更旧的服务端数据复活已移除条目。
    await _db.rawExecute(
      'UPDATE wrong_book SET removed_at = ? WHERE question_id = ?',
      <Object?>[DateTime.now().millisecondsSinceEpoch, questionId],
    );
  }

  @override
  Future<int> mergeFromServer(List<WrongItem> items) async {
    var changed = 0;
    for (final item in items) {
      if (item.question_id.isEmpty) continue;
      final existing = await _read(item.question_id);
      if (existing == null) {
        await _write(item);
        changed++;
        continue;
      }
      // 墓碑：移除之后没有再做错（服务端时间不晚于移除时刻）就不复活。
      final tombstone = existing.removed_at;
      if (tombstone != null && item.last_wrong_at <= tombstone) continue;
      // last-write-wins：服务端更旧则保留本地。
      if (item.last_wrong_at < existing.last_wrong_at) continue;
      await _write(item);
      changed++;
    }
    return changed;
  }

  Future<WrongItem?> _read(String questionId) async {
    final rows = await _db.rawQuery(
      'SELECT $_columns FROM wrong_book WHERE question_id = ?',
      <Object?>[questionId],
    );
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  Future<void> _write(WrongItem item) async {
    await _db.rawExecute(
      'INSERT OR REPLACE INTO wrong_book ($_columns) VALUES (?, ?, ?, ?, ?)',
      <Object?>[
        item.question_id,
        item.wrong_count,
        item.last_wrong_at,
        item.mastered ? 1 : 0,
        item.removed_at,
      ],
    );
  }

  static WrongItem _fromRow(Map<String, Object?> row) {
    return WrongItem(
      question_id: row['question_id'] as String,
      wrong_count: (row['wrong_count'] as num).toInt(),
      last_wrong_at: (row['last_wrong_at'] as num).toInt(),
      mastered: (row['mastered'] as num).toInt() != 0,
      removed_at: (row['removed_at'] as num?)?.toInt(),
    );
  }
}

/// 收藏持久实现：`favorites` 表，一行一题；没有墓碑字段（与契约一致）。
class SqliteFavoriteService implements FavoriteService {
  SqliteFavoriteService(this._db);

  final LocalDatabase _db;

  @override
  Future<List<String>> getFavoriteIds() async {
    final rows = await _db.rawQuery(
      'SELECT question_id FROM favorites ORDER BY rowid ASC',
    );
    return rows.map((row) => row['question_id'] as String).toList();
  }

  @override
  Future<List<Favorite>> getFavorites() async {
    final rows = await _db.rawQuery(
      'SELECT question_id, created_at FROM favorites ORDER BY rowid ASC',
    );
    return rows
        .map(
          (row) => Favorite(
            question_id: row['question_id'] as String,
            created_at: (row['created_at'] as num).toInt(),
          ),
        )
        .toList();
  }

  @override
  Future<void> toggleFavorite(String questionId, bool on) async {
    if (on) {
      await _db.rawExecute(
        'INSERT OR REPLACE INTO favorites (question_id, created_at) '
        'VALUES (?, ?)',
        <Object?>[questionId, DateTime.now().millisecondsSinceEpoch],
      );
    } else {
      await _db.rawExecute(
        'DELETE FROM favorites WHERE question_id = ?',
        <Object?>[questionId],
      );
    }
  }

  @override
  Future<int> mergeFromServer(List<Favorite> items) async {
    var changed = 0;
    for (final item in items) {
      if (item.question_id.isEmpty) continue;
      final rows = await _db.rawQuery(
        'SELECT created_at FROM favorites WHERE question_id = ?',
        <Object?>[item.question_id],
      );
      // last-write-wins：服务端更旧则保留本地。
      if (rows.isNotEmpty &&
          item.created_at < (rows.first['created_at'] as num).toInt()) {
        continue;
      }
      await _db.rawExecute(
        'INSERT OR REPLACE INTO favorites (question_id, created_at) '
        'VALUES (?, ?)',
        <Object?>[item.question_id, item.created_at],
      );
      changed++;
    }
    return changed;
  }
}