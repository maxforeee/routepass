// F39 L8：v3→v4 迁移测试——v3 老库升级后的 schema 必须与全新 v4 库
// 完全一致（v3→v4 分支只在升级路径执行，onCreate 从不走它）。
// 真实 SQLite（sqflite_common_ffi）：老库用临时文件库，新库用内存库。
// F41 M2：v3 fixture 改为冻结的历史快照（_v3Schema），不再从
// localDbSchema 文本过滤；F41 H1/H2：合并分块回归（>999 条不超限）。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/core/local_db.dart';
import 'package:routepass/models/wrong_favorite.dart';
import 'package:routepass/services/bank/sqlite_wrong_favorite_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// F41 M2：v3 时代（F35）schema 的冻结快照——与 v3 时点 localDbSchema
/// 的前 6 条 DDL 逐字一致（sqlite_master 比对 CREATE 原文，空白都不能
/// 差）。刻意不从 localDbSchema 文本过滤推导：过滤会把未来仅提及
/// wrong_book / favorites 表名的语句静默丢弃，也不会移除后来新增的
/// v4-only DDL，测试可能在「假 v3」上通过。v4 清单前 6 条若变化，升级库
/// 与新库的逐字比对会失败，强制同步更新本快照。
const List<String> _v3Schema = <String>[
  '''
  CREATE TABLE set_overview (
    set_id TEXT PRIMARY KEY,
    total INTEGER NOT NULL,
    done INTEGER NOT NULL,
    remaining INTEGER NOT NULL,
    single_count INTEGER NOT NULL,
    multiple_count INTEGER NOT NULL,
    accuracy REAL,
    by_module TEXT,
    updated_at INTEGER NOT NULL
  )
  ''',
  '''
  CREATE TABLE cached_questions (
    set_id TEXT NOT NULL,
    question_id TEXT NOT NULL,
    module TEXT NOT NULL,
    payload TEXT NOT NULL,
    updated_at INTEGER NOT NULL,
    PRIMARY KEY (set_id, question_id)
  )
  ''',
  '''
  CREATE INDEX idx_cached_questions_set
  ON cached_questions (set_id, updated_at)
  ''',
  '''
  CREATE TABLE attempts (
    set_id TEXT NOT NULL,
    question_id TEXT NOT NULL,
    chosen TEXT NOT NULL,
    correct INTEGER,
    updated_at INTEGER NOT NULL,
    PRIMARY KEY (set_id, question_id)
  )
  ''',
  '''
  CREATE TABLE sync_queue (
    op_id TEXT PRIMARY KEY,
    kind TEXT NOT NULL,
    payload TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    synced INTEGER NOT NULL DEFAULT 0,
    synced_at INTEGER
  )
  ''',
  '''
  CREATE TABLE set_meta (
    set_id TEXT PRIMARY KEY,
    session_id TEXT,
    bank_synced_at INTEGER
  )
  ''',
];

/// F41 H1/H2：记录每次 rawQuery 的宿主参数个数，断言合并的 IN 查询
/// 分块后不超 SQLite 老版本上限（999）。
class _RecordingDb implements LocalDatabase {
  _RecordingDb(this._inner);

  final LocalDatabase _inner;
  final List<int> queryArgCounts = <int>[];

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) {
    queryArgCounts.add(arguments?.length ?? 0);
    return _inner.rawQuery(sql, arguments);
  }

  @override
  Future<void> rawExecute(String sql, [List<Object?>? arguments]) =>
      _inner.rawExecute(sql, arguments);

  @override
  Future<void> close() => _inner.close();
}

void main() {
  setUpAll(sqfliteFfiInit);

  test('v3 老库升级 v4 后与全新 v4 库 schema 完全一致', () async {
    final dir = Directory.systemTemp.createTempSync('f39_migration');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/upgrade.db';

    // v3 老库只建 _v3Schema 六张表 / 索引（v4 只新增了 wrong_book /
    // favorites；set_overview 的 accuracy / by_module 在 v2 / v3 已加）。
    final v3 = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 3,
        onCreate: (db, version) async {
          for (final statement in _v3Schema) {
            await db.execute(statement);
          }
        },
      ),
    );
    await v3.close();

    // 以 SqfliteLocalDatabase 重开触发 onUpgrade(3→4)。
    final upgraded = SqfliteLocalDatabase(
      dbPath: path,
      factory: databaseFactoryFfi,
    );
    addTearDown(upgraded.close);
    await upgraded.rawQuery('SELECT 1');

    final fresh = SqfliteLocalDatabase(
      dbPath: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(fresh.close);
    await fresh.rawQuery('SELECT 1');

    // 逐条比对 sqlite_master（type / name / tbl_name / CREATE 原文）：
    // v3→v4 升级只执行同一份 DDL，无 ALTER 痕迹，sql 文本应与新库逐字一致。
    Future<List<Map<String, Object?>>> schema(LocalDatabase db) => db.rawQuery(
      'SELECT type, name, tbl_name, sql FROM sqlite_master '
      "WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name",
    );
    expect(await schema(upgraded), await schema(fresh));
    expect(
      await upgraded.rawQuery('PRAGMA user_version'),
      await fresh.rawQuery('PRAGMA user_version'),
    );

    // 升级库的新表可用：空库读回空（诚实空态，不预置数据）。
    expect(await upgraded.rawQuery('SELECT * FROM wrong_book'), isEmpty);
    expect(await upgraded.rawQuery('SELECT * FROM favorites'), isEmpty);
  });

  test('F41 H1/H2：1200 条合并的 IN 查询分块，单条宿主参数不超 500', () async {
    final db = SqfliteLocalDatabase(
      dbPath: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    final spy = _RecordingDb(db);
    addTearDown(spy.close);
    final wrong = SqliteWrongService(spy);
    final favorites = SqliteFavoriteService(spy);

    // 1200 > 999（老版本 Android SQLite 上限）：修复前单条 IN 带 1200
    // 个参数，真机会抛 too many SQL variables；测试宿主上限较宽，
    // 用参数计数断言分块本身。
    const total = 1200;
    expect(
      await wrong.mergeFromServer(<WrongItem>[
        for (var i = 0; i < total; i++)
          WrongItem(
            question_id: 'Q-$i',
            wrong_count: 1,
            last_wrong_at: 1000 + i,
            mastered: false,
          ),
      ]),
      total,
    );
    expect(
      await favorites.mergeFromServer(<Favorite>[
        for (var i = 0; i < total; i++)
          Favorite(question_id: 'Q-$i', created_at: 1000 + i),
      ]),
      total,
    );

    expect(spy.queryArgCounts, everyElement(lessThanOrEqualTo(500)));
    // 分块不改合并语义：条目全部落库、读回完整。
    expect(await wrong.getWrongBook(), hasLength(total));
    expect(await favorites.getFavoriteIds(), hasLength(total));
  });
}
