/// WrongService / FavoriteService 的 SQLite 持久实现（F36，规格文档
/// 第 4 章 §4.4.4 / §4.8.5，客户端表 `wrong_book` / `favorites`）。
///
/// 与 Mock 的区别：数据落本地 SQLite（与题库缓存共用同一个
/// `LocalDatabase` / `routepass.db`），重启不丢；不预置演示数据，
/// 空库读回空（诚实空态）。合并语义与 Mock 一字不差：
/// last-write-wins（服务端更旧保留本地，时间戳相等 → 覆盖），错题墓碑
/// （removed_at）不被更旧的服务端数据复活。读路径按需查 SQLite，不做
/// 启动阻塞加载。收藏排序契约（F39 L5）：created_at ASC，question_id
/// 打破平局——rowid 会被重写，不是稳定契约。
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
    // F39 M5：本地表没有模块列（WrongItem 也没有 module 字段），module
    // 过滤只能由 HTTP 层对服务端 question.module 做；本实现显式不支持
    // module——传入非 null 时仍返回未过滤的本地全量列表（不过滤、不抛错）。
    // 不抛错的原因：HttpWrongService.getWrongBook 网络失败兜底会原样
    // 透传 module，抛错会打断离线错题本页。调用方不得依赖本地实现做
    // module 过滤（契约见 WrongService.getWrongBook 文档）。
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
    //
    // F39 M4 墓碑契约（与 mergeFromServer 的守卫保持一致）：
    // 这里清墓碑是安全的——addWrong 是真实的「再做错」，写入
    // last_wrong_at = now，而 now 恒晚于 removed_at（移除发生在过去）。
    // 凡墓碑会拦下的服务端条目（last_wrong_at <= removed_at）必然满足
    // last_wrong_at < now，mergeFromServer 的 LWW 同样拦下；中间时间戳
    // （removed_at < ts < now）也被 LWW 拦下。因此单调时钟下两条写路径
    // 的复活守卫一致：只有 ts >= now 的更新错题记录才能覆盖本地。
    // 已知边界：客户端时钟回拨（now < removed_at）时 LWW 覆盖不了墓碑
    // 区间——这是 LWW 契约本身的边界，不是清墓碑引入的新洞。
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
    // F39 L4：批量读已有行（单条 WHERE question_id IN (...)），消除
    // 逐条 SELECT 的 N+1。LocalDatabase 没有事务 API，写仍逐条执行，
    // 属 best-effort：中途失败会留下半合并状态，但每条的合并是幂等的
    // （墓碑 + LWW），重试同一份服务端列表会收敛到同一结果。
    final valid = items.where((item) => item.question_id.isNotEmpty).toList();
    if (valid.isEmpty) return 0;
    final ids = valid.map((item) => item.question_id).toSet().toList();
    final placeholders = List<String>.filled(ids.length, '?').join(', ');
    final rows = await _db.rawQuery(
      'SELECT $_columns FROM wrong_book WHERE question_id IN ($placeholders)',
      ids,
    );
    final existingById = <String, WrongItem>{
      for (final row in rows) (row['question_id'] as String): _fromRow(row),
    };
    var changed = 0;
    for (final item in valid) {
      final existing = existingById[item.question_id];
      if (existing == null) {
        await _write(item);
        existingById[item.question_id] = item;
        changed++;
        continue;
      }
      // 墓碑：移除之后没有再做错（服务端时间不晚于移除时刻）就不复活
      // （相等也不复活，<= 比较，见 F39 M8 测试）。
      final tombstone = existing.removed_at;
      if (tombstone != null && item.last_wrong_at <= tombstone) continue;
      // last-write-wins：服务端更旧则保留本地（相等 → 覆盖，< 比较）。
      if (item.last_wrong_at < existing.last_wrong_at) continue;
      await _write(item);
      existingById[item.question_id] = item;
      changed++;
    }
    return changed;
  }

  Future<void> _write(WrongItem item) async {
    // F39 L5：与 addWrong 对称——ON CONFLICT DO UPDATE 原地改行，
    // 不用 INSERT OR REPLACE 的删后重插（会改 rowid）。
    await _db.rawExecute(
      'INSERT INTO wrong_book ($_columns) VALUES (?, ?, ?, ?, ?) '
      'ON CONFLICT(question_id) DO UPDATE SET '
      'wrong_count = excluded.wrong_count, '
      'last_wrong_at = excluded.last_wrong_at, '
      'mastered = excluded.mastered, '
      'removed_at = excluded.removed_at',
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
    // F39 L5：created_at ASC 是稳定排序契约，question_id 打破平局；
    // rowid 会被重写（历史 INSERT OR REPLACE），不是契约。
    final rows = await _db.rawQuery(
      'SELECT question_id FROM favorites '
      'ORDER BY created_at ASC, question_id ASC',
    );
    return rows.map((row) => row['question_id'] as String).toList();
  }

  @override
  Future<List<Favorite>> getFavorites() async {
    final rows = await _db.rawQuery(
      'SELECT question_id, created_at FROM favorites '
      'ORDER BY created_at ASC, question_id ASC',
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
      // F39 M3：INSERT OR IGNORE——已收藏的题重复收藏保留原 created_at
      // 与排序，不重写行、不把时间戳顶成 now（否则后续 mergeFromServer
      // 的 LWW 会拿被顶高的本地时间去压更新的服务端 created_at）。
      await _db.rawExecute(
        'INSERT OR IGNORE INTO favorites (question_id, created_at) '
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
    // F39 L4：批量读已有行（单条 WHERE question_id IN (...)）。
    // LocalDatabase 没有事务 API，写仍逐条执行，属 best-effort：
    // 每条合并幂等（LWW），重试同一份服务端列表会收敛到同一结果。
    final valid = items.where((item) => item.question_id.isNotEmpty).toList();
    if (valid.isEmpty) return 0;
    final ids = valid.map((item) => item.question_id).toSet().toList();
    final placeholders = List<String>.filled(ids.length, '?').join(', ');
    final rows = await _db.rawQuery(
      'SELECT question_id, created_at FROM favorites '
      'WHERE question_id IN ($placeholders)',
      ids,
    );
    final createdAtById = <String, int>{
      for (final row in rows)
        (row['question_id'] as String): (row['created_at'] as num).toInt(),
    };
    var changed = 0;
    for (final item in valid) {
      final existing = createdAtById[item.question_id];
      // last-write-wins：服务端更旧则保留本地（相等 → 覆盖，见 F39 M8/L7）。
      if (existing != null && item.created_at < existing) continue;
      // F39 L5：ON CONFLICT DO UPDATE 原地改行，rowid 保持稳定。
      await _db.rawExecute(
        'INSERT INTO favorites (question_id, created_at) VALUES (?, ?) '
        'ON CONFLICT(question_id) DO UPDATE SET '
        'created_at = excluded.created_at',
        <Object?>[item.question_id, item.created_at],
      );
      createdAtById[item.question_id] = item.created_at;
      changed++;
    }
    return changed;
  }
}
