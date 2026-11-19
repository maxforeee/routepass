/// 本地 SQLite 数据库（F19 cache-first 数据层）。
///
/// 只暴露最小的 raw SQL 接口，缓存语义集中在
/// `lib/services/bank/local_cache_service.dart`。测试不碰真实 SQLite，
/// 用同一接口的内存实现；生产装配 `SqfliteLocalDatabase`（Android / iOS）。
library;

import 'package:sqflite/sqflite.dart';

/// F36：错题本本地持久表（§4.8.5）。removed_at 为移除墓碑（null = 未移除）。
/// 裸 CREATE TABLE：onCreate 只在全新库执行，v3→v4 升级时表必然不存在，
/// 与其余五张表保持一致（F39 M6）。
const String _wrongBookTableDdl = '''
CREATE TABLE wrong_book (
  question_id TEXT PRIMARY KEY,
  wrong_count INTEGER NOT NULL,
  last_wrong_at INTEGER NOT NULL,
  mastered INTEGER NOT NULL,
  removed_at INTEGER
)
''';

/// F36：收藏本地持久表（§4.8.5）。收藏没有墓碑字段。
const String _favoritesTableDdl = '''
CREATE TABLE favorites (
  question_id TEXT PRIMARY KEY,
  created_at INTEGER NOT NULL
)
''';

/// 客户端 SQLite 表结构（v4）。
///
/// 与 v1.2 设计一致：服务端 PostgreSQL 为准，客户端 SQLite 只做本地缓存
/// 与待同步队列；缓存表以 `set_id` 为本地分区键。
/// v2（F26）：set_overview 增加可空 accuracy 列（null = 未知，不写假 0）。
/// v3（F35）：set_overview 增加可空 by_module 列（每模块题量映射的 JSON；
/// null = 未知，读回 null，前置页显示“题量待接口”，不编映射）。
/// v4（F36）：新增 wrong_book / favorites 两张本地持久表（§4.8.5），
/// 错题本与收藏重启不丢；不预置演示数据，空库读回空（诚实空态）。
const List<String> localDbSchema = <String>[
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
  _wrongBookTableDdl,
  _favoritesTableDdl,
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

  static const int schemaVersion = 4;
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
        onUpgrade: (db, oldVersion, newVersion) async {
          // v1 → v2（F26）：老库补 accuracy 列，既有行保持 null（未知）。
          if (oldVersion < 2) {
            await db.execute(
              'ALTER TABLE set_overview ADD COLUMN accuracy REAL',
            );
          }
          // v2 → v3（F35）：老库补 by_module 列，既有行保持 null（未知）。
          if (oldVersion < 3) {
            await db.execute(
              'ALTER TABLE set_overview ADD COLUMN by_module TEXT',
            );
          }
          // v3 → v4（F36）：老库补错题本 / 收藏持久表（空表，不预置数据）。
          if (oldVersion < 4) {
            await db.execute(_wrongBookTableDdl);
            await db.execute(_favoritesTableDdl);
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
