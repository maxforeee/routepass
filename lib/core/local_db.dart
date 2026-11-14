/// 本地 SQLite 数据库（F19 cache-first 数据层）。
///
/// 只暴露最小的 raw SQL 接口，缓存语义集中在
/// `lib/services/bank/local_cache_service.dart`。测试不碰真实 SQLite，
/// 用同一接口的内存实现；生产装配 `SqfliteLocalDatabase`（Android / iOS）。
library;

import 'package:sqflite/sqflite.dart';

/// 客户端 SQLite 表结构（v1）。
///
/// 与 v1.2 设计一致：服务端 PostgreSQL 为准，客户端 SQLite 只做本地缓存
/// 与待同步队列；所有表都以 `set_id` 为本地分区键。
const List<String> localDbSchema = <String>[
  '''
  CREATE TABLE set_overview (
    set_id TEXT PRIMARY KEY,
    total INTEGER NOT NULL,
    done INTEGER NOT NULL,
    remaining INTEGER NOT NULL,
    single_count INTEGER NOT NULL,
    multiple_count INTEGER NOT NULL,
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

/// 最小本地数据库接口：执行写语句 / 查询行。
abstract class LocalDatabase {
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]);

  Future<void> rawExecute(String sql, [List<Object?>? arguments]);

  Future<void> close();
}

/// sqflite 实现：懒打开 `routepass.db`，首次打开时建表。
class SqfliteLocalDatabase implements LocalDatabase {
  SqfliteLocalDatabase({this.dbPath, DatabaseFactory? factory})
    : dbFactory = factory ?? databaseFactory;

  static const int schemaVersion = 1;
  static const String defaultFileName = 'routepass.db';

  final String? dbPath;
  final DatabaseFactory dbFactory;
  Future<Database>? _opening;

  Future<Database> get _db => _opening ??= _open();

  Future<Database> _open() async {
    final path = dbPath ?? '${await getDatabasesPath()}/$defaultFileName';
    final db = await dbFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onCreate: (db, version) async {
          for (final statement in localDbSchema) {
            await db.execute(statement);
          }
        },
      ),
    );
    return db;
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async {
    return (await _db).rawQuery(sql, arguments);
  }

  @override
  Future<void> rawExecute(String sql, [List<Object?>? arguments]) async {
    await (await _db).execute(sql, arguments);
  }

  @override
  Future<void> close() async {
    final opening = _opening;
    _opening = null;
    if (opening != null) {
      final db = await opening;
      await db.close();
    }
  }
}
