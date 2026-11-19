// F43：收藏墓碑 + 服务端删除传播。
// - 迁移 v4→v5：冻结的 v4 fixture 升级后与全新 v5 库逻辑 schema 一致
//   （F39/F41 模式；favorites 的 CREATE 原文因 ALTER 追加列而不同，
//   用 PRAGMA table_info 做权威比对，见测试内注释）。
// - 收藏墓碑：取消收藏写墓碑不删行；更旧 / 等于墓碑的服务端条目不复活；
//   严格更新的复活；重新收藏清墓碑且保留原 created_at（F39 M3）。
// - 服务端删除传播（store 层）：完整列表缺席 → 写墓碑；已有墓碑不重写；
//   UPDATE 按 500 分块（F41 H1/H2 宿主参数上限）。
// - 同步完整性闸门：完整拉取才传播删除；total 缺失 / 页数截断 / 拉取
//   失败绝不删除本地数据。
// 真实 SQLite（sqflite_common_ffi），与 f36/f39 测试同一模式。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:routepass/core/kv_store.dart';
import 'package:routepass/core/local_db.dart';
import 'package:routepass/models/wrong_favorite.dart';
import 'package:routepass/services/bank/favorite_service.dart';
import 'package:routepass/services/bank/local_cache_service.dart';
import 'package:routepass/services/bank/sqlite_wrong_favorite_service.dart';
import 'package:routepass/services/bank/sync_http_service.dart';
import 'package:routepass/services/bank/wrong_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// F43：v4 时代（F36/F39/F41）schema 的冻结快照——与 v4 时点
/// localDbSchema 的 8 条 DDL 逐字一致（前 6 条同 f39 的 _v3Schema；
/// wrong_book 与 v4 时点一致；favorites 尚无 removed_at）。刻意不从
/// 当前 localDbSchema 文本过滤推导（F41 M2 同一理由）：v5 清单若变化，
/// 升级库与新库的比对会失败，强制同步更新本快照。
const List<String> _v4Schema = <String>[
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
  '''
CREATE TABLE wrong_book (
  question_id TEXT PRIMARY KEY,
  wrong_count INTEGER NOT NULL,
  last_wrong_at INTEGER NOT NULL,
  mastered INTEGER NOT NULL,
  removed_at INTEGER
)
''',
  '''
CREATE TABLE favorites (
  question_id TEXT PRIMARY KEY,
  created_at INTEGER NOT NULL
)
''',
];

/// F43：记录 rawQuery / rawExecute 的宿主参数个数，断言新增的缺席
/// 墓碑路径与合并一样分块（F41 H1/H2：老版本 SQLite 上限 999）。
class _RecordingDb implements LocalDatabase {
  _RecordingDb(this._inner);

  final LocalDatabase _inner;
  final List<int> queryArgCounts = <int>[];
  final List<int> executeArgCounts = <int>[];

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) {
    queryArgCounts.add(arguments?.length ?? 0);
    return _inner.rawQuery(sql, arguments);
  }

  @override
  Future<void> rawExecute(String sql, [List<Object?>? arguments]) {
    executeArgCounts.add(arguments?.length ?? 0);
    return _inner.rawExecute(sql, arguments);
  }

  @override
  Future<void> close() => _inner.close();
}

/// 记录合并 / 缺席墓碑调用的错题 store fake（同步闸门测试用）。
class _RecordingWrongService implements WrongService {
  final List<List<WrongItem>> merges = <List<WrongItem>>[];
  final List<Set<String>> tombstoneCalls = <Set<String>>[];

  @override
  Future<List<WrongItem>> getWrongBook({
    String? module,
    bool? masteredOnly,
  }) async => const <WrongItem>[];

  @override
  Future<void> addWrong(String questionId) async {}

  @override
  Future<void> markMastered(String questionId) async {}

  @override
  Future<void> removeWrong(
    String questionId, {
    String reason = 'user_removed',
  }) async {}

  @override
  Future<int> mergeFromServer(List<WrongItem> items) async {
    merges.add(items);
    return items.length;
  }

  @override
  Future<int> tombstoneAbsentFromServer(Set<String> liveQuestionIds) async {
    tombstoneCalls.add(liveQuestionIds);
    return 0;
  }
}

/// 记录合并 / 缺席墓碑调用的收藏 store fake（同步闸门测试用）。
class _RecordingFavoriteService implements FavoriteService {
  final List<List<Favorite>> merges = <List<Favorite>>[];
  final List<Set<String>> tombstoneCalls = <Set<String>>[];

  @override
  Future<List<String>> getFavoriteIds() async => const <String>[];

  @override
  Future<List<Favorite>> getFavorites() async => const <Favorite>[];

  @override
  Future<void> toggleFavorite(String questionId, bool on) async {}

  @override
  Future<int> mergeFromServer(List<Favorite> items) async {
    merges.add(items);
    return items.length;
  }

  @override
  Future<int> tombstoneAbsentFromServer(Set<String> liveQuestionIds) async {
    tombstoneCalls.add(liveQuestionIds);
    return 0;
  }
}

/// 内存 KvStore fake：只实现 HttpSyncService 实际用到的四个方法
/// （getString / setString / getStringList / setStringList，签名从
/// sync_http_service.dart 的调用点核实）。任务书限定可读文件，未读
/// kv_store.dart 的完整接口，故用 noSuchMethod 兜底——其余成员一旦被
/// 触达立即抛错，不静默吞掉未知调用。
class _FakeKv implements KvStore {
  final Map<String, Object?> _values = <String, Object?>{};

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName;
    final args = invocation.positionalArguments;
    if (name == #getString) {
      return _values[args[0] as String] as String?;
    }
    if (name == #setString) {
      _values[args[0] as String] = args[1];
      return null;
    }
    if (name == #getStringList) {
      return (_values[args[0] as String] as List?)?.cast<String>();
    }
    if (name == #setStringList) {
      _values[args[0] as String] = args[1];
      return null;
    }
    throw UnimplementedError('KvStore 成员未在本 fake 中实现：$name');
  }
}

http.Response _json(Object body, [int status = 200]) {
  return http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    status,
    headers: const <String, String>{'content-type': 'application/json'},
  );
}

const String _iso = '2026-11-19T00:00:00.000Z';

Map<String, Object?> _wrongJson(String id) => <String, Object?>{
  'questionId': id,
  'wrongCount': 1,
  'lastWrongAt': _iso,
  'mastered': false,
};

Map<String, Object?> _favoriteJson(String id) => <String, Object?>{
  'questionId': id,
  'createdAt': _iso,
};

/// 同步 pull 的空页（无变更、无更多页）。
Map<String, Object?> _emptyPullPage() => <String, Object?>{
  'changes': <Object?>[],
  'nextCursor': 0,
  'watermark': 0,
  'hasMore': false,
  'serverTime': _iso,
  'recent_answered': <String>[],
};

void main() {
  setUpAll(sqfliteFfiInit);

  group('F43 迁移 v4→v5', () {
    test('v4 老库升级后与全新 v5 库逻辑 schema 一致，既有行保留', () async {
      final dir = Directory.systemTemp.createTempSync('f43_migration');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/upgrade.db';

      // v4 老库：冻结快照建表，并预置一行收藏 / 一行错题（升级不得丢）。
      final v4 = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 4,
          onCreate: (db, version) async {
            for (final statement in _v4Schema) {
              await db.execute(statement);
            }
          },
        ),
      );
      await v4.execute(
        'INSERT INTO favorites (question_id, created_at) VALUES (?, ?)',
        <Object?>['VLAN-1', 2000],
      );
      await v4.execute(
        'INSERT INTO wrong_book (question_id, wrong_count, last_wrong_at, '
        'mastered, removed_at) VALUES (?, ?, ?, ?, ?)',
        <Object?>['VLAN-9', 2, 3000, 0, null],
      );
      await v4.close();

      // 以 SqfliteLocalDatabase 重开触发 onUpgrade(4→5)。
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

      // favorites 的 CREATE 原文不参与逐字比对：ALTER TABLE ADD COLUMN
      // 会把列定义追加进 sqlite_master.sql 的旧 CREATE 文本，与全新库
      // 内联写法的空白必然不同（逻辑 schema 相同）。权威比对用
      // PRAGMA table_info；其余对象的 CREATE 原文仍逐字一致。
      const masterSql =
          'SELECT type, name, tbl_name, sql FROM sqlite_master '
          "WHERE name NOT LIKE 'sqlite_%' AND name <> 'favorites' "
          'ORDER BY type, name';
      expect(
        await upgraded.rawQuery(masterSql),
        await fresh.rawQuery(masterSql),
      );
      const favMasterSql =
          "SELECT type, name, tbl_name FROM sqlite_master WHERE name = 'favorites'";
      expect(
        await upgraded.rawQuery(favMasterSql),
        await fresh.rawQuery(favMasterSql),
      );
      const tables = <String>[
        'set_overview',
        'cached_questions',
        'attempts',
        'sync_queue',
        'set_meta',
        'wrong_book',
        'favorites',
      ];
      for (final table in tables) {
        expect(
          await upgraded.rawQuery('PRAGMA table_info($table)'),
          await fresh.rawQuery('PRAGMA table_info($table)'),
          reason: 'table_info($table) 升级库与新库必须一致',
        );
      }
      expect(
        await upgraded.rawQuery('PRAGMA user_version'),
        await fresh.rawQuery('PRAGMA user_version'),
      );

      // 既有行保留：收藏行补上的 removed_at 为 null（未移除）。
      expect(
        await upgraded.rawQuery(
          'SELECT question_id, created_at, removed_at FROM favorites',
        ),
        <Map<String, Object?>>[
          <String, Object?>{
            'question_id': 'VLAN-1',
            'created_at': 2000,
            'removed_at': null,
          },
        ],
      );
      expect(
        await upgraded.rawQuery('SELECT * FROM wrong_book'),
        <Map<String, Object?>>[
          <String, Object?>{
            'question_id': 'VLAN-9',
            'wrong_count': 2,
            'last_wrong_at': 3000,
            'mastered': 0,
            'removed_at': null,
          },
        ],
      );

      // 升级库上墓碑契约立即可用：取消收藏 → 隐藏；更旧的服务端不复活。
      final favOnUpgraded = SqliteFavoriteService(upgraded);
      expect(await favOnUpgraded.getFavoriteIds(), <String>['VLAN-1']);
      await favOnUpgraded.toggleFavorite('VLAN-1', false);
      expect(await favOnUpgraded.getFavoriteIds(), isEmpty);
      expect(
        await favOnUpgraded.mergeFromServer(<Favorite>[
          const Favorite(question_id: 'VLAN-1', created_at: 1000),
        ]),
        0,
      );
      expect(await favOnUpgraded.getFavoriteIds(), isEmpty);
    });
  });

  group('F43 收藏墓碑（store 层）', () {
    late SqfliteLocalDatabase db;
    late SqliteWrongService wrong;
    late SqliteFavoriteService favorites;

    setUp(() {
      db = SqfliteLocalDatabase(
        dbPath: inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      );
      wrong = SqliteWrongService(db);
      favorites = SqliteFavoriteService(db);
    });

    tearDown(() => db.close());

    test('取消收藏写墓碑不删行；更旧 / 等于墓碑不复活，严格更新复活', () async {
      await favorites.toggleFavorite('VLAN-1', true);
      await favorites.toggleFavorite('VLAN-1', false);
      expect(await favorites.getFavoriteIds(), isEmpty);
      expect(await favorites.getFavorites(), isEmpty);

      // 行还在（墓碑，不是删行）。
      final rows = await db.rawQuery(
        'SELECT removed_at FROM favorites WHERE question_id = ?',
        <Object?>['VLAN-1'],
      );
      expect(rows, hasLength(1));
      expect(rows.first['removed_at'], isNotNull);
      final tombstone = (rows.first['removed_at'] as num).toInt();

      // 更旧的服务端条目不复活。
      expect(
        await favorites.mergeFromServer(<Favorite>[
          const Favorite(question_id: 'VLAN-1', created_at: 1),
        ]),
        0,
      );
      expect(await favorites.getFavoriteIds(), isEmpty);
      // 恰好等于墓碑也不复活（<= 比较，与错题本 F39 M8 同一规则）。
      expect(
        await favorites.mergeFromServer(<Favorite>[
          Favorite(question_id: 'VLAN-1', created_at: tombstone),
        ]),
        0,
      );
      expect(await favorites.getFavoriteIds(), isEmpty);
      // 严格更新的服务端条目复活并清墓碑（文档化复活契约，F41 M1）。
      expect(
        await favorites.mergeFromServer(<Favorite>[
          Favorite(question_id: 'VLAN-1', created_at: tombstone + 1),
        ]),
        1,
      );
      expect(await favorites.getFavoriteIds(), <String>['VLAN-1']);
      expect((await favorites.getFavorites()).single.created_at, tombstone + 1);
      final revived = await db.rawQuery(
        'SELECT removed_at FROM favorites WHERE question_id = ?',
        <Object?>['VLAN-1'],
      );
      expect(revived.single['removed_at'], isNull);
    });

    test('重新收藏清墓碑且保留原 created_at（F39 M3 不被顶高）', () async {
      expect(
        await favorites.mergeFromServer(<Favorite>[
          const Favorite(question_id: 'VLAN-1', created_at: 2000),
        ]),
        1,
      );
      await favorites.toggleFavorite('VLAN-1', false);
      expect(await favorites.getFavoriteIds(), isEmpty);

      // 重新收藏：复活，但 created_at 仍是原收藏时间 2000，不是 now。
      await favorites.toggleFavorite('VLAN-1', true);
      expect((await favorites.getFavorites()).single.created_at, 2000);
      final rows = await db.rawQuery(
        'SELECT removed_at FROM favorites WHERE question_id = ?',
        <Object?>['VLAN-1'],
      );
      expect(rows.single['removed_at'], isNull);

      // 本地时间未被顶高 → 更新的服务端条目仍能正常覆盖（LWW 不被污染）。
      expect(
        await favorites.mergeFromServer(<Favorite>[
          const Favorite(question_id: 'VLAN-1', created_at: 3000),
        ]),
        1,
      );
      expect((await favorites.getFavorites()).single.created_at, 3000);
    });

    test('错题本缺席墓碑：只埋缺席的存活行，已有墓碑时间戳不重写', () async {
      expect(
        await wrong.mergeFromServer(<WrongItem>[
          const WrongItem(
            question_id: 'A',
            wrong_count: 1,
            last_wrong_at: 2000,
            mastered: false,
          ),
          const WrongItem(
            question_id: 'B',
            wrong_count: 1,
            last_wrong_at: 2000,
            mastered: false,
          ),
          const WrongItem(
            question_id: 'C',
            wrong_count: 1,
            last_wrong_at: 2000,
            mastered: false,
          ),
        ]),
        3,
      );
      await wrong.removeWrong('C');
      final cBefore = await db.rawQuery(
        'SELECT removed_at FROM wrong_book WHERE question_id = ?',
        <Object?>['C'],
      );
      final cTombstone = (cBefore.single['removed_at'] as num).toInt();

      // 服务端完整列表只剩 A：B 缺席 → 埋；C 已有墓碑不重写；A 不动。
      expect(await wrong.tombstoneAbsentFromServer(<String>{'A'}), 1);
      expect(
        (await wrong.getWrongBook()).map((item) => item.question_id),
        <String>['A'],
      );
      final bRow = await db.rawQuery(
        'SELECT removed_at FROM wrong_book WHERE question_id = ?',
        <Object?>['B'],
      );
      expect(bRow.single['removed_at'], isNotNull);
      final cAfter = await db.rawQuery(
        'SELECT removed_at FROM wrong_book WHERE question_id = ?',
        <Object?>['C'],
      );
      expect(cAfter.single['removed_at'], cTombstone);

      // 幂等：同一份完整列表再来一次，没有新墓碑。
      expect(await wrong.tombstoneAbsentFromServer(<String>{'A'}), 0);
      // 空的全量列表（服务端删光了）→ 存活的 A 也埋。
      expect(await wrong.tombstoneAbsentFromServer(<String>{}), 1);
      expect(await wrong.getWrongBook(), isEmpty);

      // 缺席墓碑与用户墓碑同一守卫：严格更新的服务端条目仍可复活。
      final future = DateTime.now().millisecondsSinceEpoch + 3600 * 1000;
      expect(
        await wrong.mergeFromServer(<WrongItem>[
          WrongItem(
            question_id: 'A',
            wrong_count: 2,
            last_wrong_at: future,
            mastered: false,
          ),
        ]),
        1,
      );
      expect((await wrong.getWrongBook()).single.question_id, 'A');
    });

    test('收藏缺席墓碑：只埋缺席的存活行，已有墓碑时间戳不重写', () async {
      expect(
        await favorites.mergeFromServer(<Favorite>[
          const Favorite(question_id: 'A', created_at: 2000),
          const Favorite(question_id: 'B', created_at: 2000),
          const Favorite(question_id: 'C', created_at: 2000),
        ]),
        3,
      );
      await favorites.toggleFavorite('C', false);
      final cBefore = await db.rawQuery(
        'SELECT removed_at FROM favorites WHERE question_id = ?',
        <Object?>['C'],
      );
      final cTombstone = (cBefore.single['removed_at'] as num).toInt();

      expect(await favorites.tombstoneAbsentFromServer(<String>{'A'}), 1);
      expect(await favorites.getFavoriteIds(), <String>['A']);
      final bRow = await db.rawQuery(
        'SELECT removed_at FROM favorites WHERE question_id = ?',
        <Object?>['B'],
      );
      expect(bRow.single['removed_at'], isNotNull);
      final cAfter = await db.rawQuery(
        'SELECT removed_at FROM favorites WHERE question_id = ?',
        <Object?>['C'],
      );
      expect(cAfter.single['removed_at'], cTombstone);
      // A 的 created_at 不被触碰。
      expect((await favorites.getFavorites()).single.created_at, 2000);

      expect(await favorites.tombstoneAbsentFromServer(<String>{'A'}), 0);
      expect(await favorites.tombstoneAbsentFromServer(<String>{}), 1);
      expect(await favorites.getFavoriteIds(), isEmpty);
    });

    test('登出 clearAll：墓碑行与存活行一并清空（F25 规则不回归）', () async {
      await wrong.addWrong('VLAN-1');
      await wrong.removeWrong('VLAN-1');
      await favorites.toggleFavorite('OSPF-1', true);
      await favorites.toggleFavorite('OSPF-1', false);
      await favorites.toggleFavorite('VLAN-2', true);

      await SqliteBankLocalCache(db).clearAll();

      expect(await wrong.getWrongBook(), isEmpty);
      expect(await favorites.getFavorites(), isEmpty);
      expect(await db.rawQuery('SELECT * FROM wrong_book'), isEmpty);
      expect(await db.rawQuery('SELECT * FROM favorites'), isEmpty);
    });

    test('F41 约束：1200 条缺席墓碑的 UPDATE 分块，宿主参数不超限', () async {
      final inner = SqfliteLocalDatabase(
        dbPath: inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      );
      final spy = _RecordingDb(inner);
      addTearDown(spy.close);
      final favorites = SqliteFavoriteService(spy);

      const total = 1200;
      expect(
        await favorites.mergeFromServer(<Favorite>[
          for (var i = 0; i < total; i++)
            Favorite(question_id: 'Q-$i', created_at: 1000 + i),
        ]),
        total,
      );
      // 服务端全量为空 → 1200 条全部缺席。修复前若用单条 NOT IN / IN
      // 带全量 id，真机（老版本 SQLite 上限 999）会抛 too many SQL
      // variables；测试宿主上限较宽，用参数计数断言分块本身。
      expect(await favorites.tombstoneAbsentFromServer(<String>{}), total);
      expect(await favorites.getFavoriteIds(), isEmpty);
      expect(
        await inner.rawQuery(
          'SELECT COUNT(*) AS n FROM favorites WHERE removed_at IS NOT NULL',
        ),
        <Map<String, Object?>>[
          <String, Object?>{'n': total},
        ],
      );
      expect(spy.queryArgCounts, everyElement(lessThanOrEqualTo(500)));
      // UPDATE 参数 = 1 个时间戳 + 至多 500 个 id。
      expect(spy.executeArgCounts, everyElement(lessThanOrEqualTo(501)));
    });
  });

  test('HTTP 实现把缺席墓碑委托给 local（与 mergeFromServer 同一模式）', () async {
    final wrongLocal = _RecordingWrongService();
    final favoriteLocal = _RecordingFavoriteService();
    final wrongHttp = HttpWrongService(local: wrongLocal);
    final favoriteHttp = HttpFavoriteService(local: favoriteLocal);

    expect(await wrongHttp.tombstoneAbsentFromServer(<String>{'A'}), 0);
    expect(await favoriteHttp.tombstoneAbsentFromServer(<String>{'B'}), 0);
    expect(wrongLocal.tombstoneCalls, <Set<String>>[
      <String>{'A'},
    ]);
    expect(favoriteLocal.tombstoneCalls, <Set<String>>[
      <String>{'B'},
    ]);
  });

  group('F43 同步完整性闸门（HttpSyncService.syncNow）', () {
    /// 组装注入 store 的同步服务；wrongHandler / favoriteHandler 按页
    /// 返回列表接口响应。baseline 404、pull 空页 → 只走物化路径。
    HttpSyncService buildSync({
      required http.Response Function(int page) wrongHandler,
      required http.Response Function(int page) favoriteHandler,
      required _RecordingWrongService wrongStore,
      required _RecordingFavoriteService favoriteStore,
    }) {
      final client = MockClient((request) async {
        final path = request.url.path;
        if (path == '/api/v1/sync/baseline') {
          return _json(<String, Object?>{}, 404);
        }
        if (path == '/api/v1/sync/pull') return _json(_emptyPullPage());
        final page = int.parse(request.url.queryParameters['page'] ?? '1');
        if (path == '/api/v1/wrong-book') return wrongHandler(page);
        if (path == '/api/v1/favorites') return favoriteHandler(page);
        return _json(<String, Object?>{}, 404);
      });
      return HttpSyncService(
        client: client,
        baseUrl: 'http://test.local',
        tokenProvider: () => 'token',
        kvStore: _FakeKv(),
        wrongService: wrongStore,
        favoriteService: favoriteStore,
      );
    }

    test('完整拉取：缺席判定生效，两类 store 都收到服务端存活 id 集合', () async {
      final wrongStore = _RecordingWrongService();
      final favoriteStore = _RecordingFavoriteService();
      final sync = buildSync(
        wrongHandler: (page) => _json(<String, Object?>{
          'items': <Object?>[_wrongJson('Q-A')],
          'page': page,
          'pageSize': 100,
          'total': 1,
        }),
        favoriteHandler: (page) => _json(<String, Object?>{
          'items': <Object?>[_favoriteJson('Q-A')],
          'page': page,
          'pageSize': 100,
          'total': 1,
        }),
        wrongStore: wrongStore,
        favoriteStore: favoriteStore,
      );

      final result = await sync.syncNow();

      expect(result.ok, isTrue);
      expect(wrongStore.merges, hasLength(1));
      expect(wrongStore.merges.single.single.question_id, 'Q-A');
      expect(favoriteStore.merges, hasLength(1));
      expect(wrongStore.tombstoneCalls, <Set<String>>[
        <String>{'Q-A'},
      ]);
      expect(favoriteStore.tombstoneCalls, <Set<String>>[
        <String>{'Q-A'},
      ]);
      // 文案计数仍是合并条数（墓碑条数不计入）。
      expect(result.message, contains('错题本已更新 1 条'));
      expect(result.message, contains('收藏已更新 1 条'));
    });

    test('total 缺失（不完整）：照常合并，但绝不传播删除', () async {
      final wrongStore = _RecordingWrongService();
      final favoriteStore = _RecordingFavoriteService();
      final sync = buildSync(
        wrongHandler: (page) => _json(<String, Object?>{
          'items': <Object?>[_wrongJson('Q-A')],
          'page': page,
          'pageSize': 100,
        }),
        favoriteHandler: (page) => _json(<String, Object?>{
          'items': <Object?>[_favoriteJson('Q-A')],
          'page': page,
          'pageSize': 100,
        }),
        wrongStore: wrongStore,
        favoriteStore: favoriteStore,
      );

      final result = await sync.syncNow();

      expect(result.ok, isTrue);
      expect(wrongStore.merges, hasLength(1));
      expect(favoriteStore.merges, hasLength(1));
      expect(wrongStore.tombstoneCalls, isEmpty);
      expect(favoriteStore.tombstoneCalls, isEmpty);
    });

    test('页数上限截断（50 页 × 100 < total）：错题不传播删除，收藏完整照常', () async {
      final wrongStore = _RecordingWrongService();
      final favoriteStore = _RecordingFavoriteService();
      final sync = buildSync(
        wrongHandler: (page) => _json(<String, Object?>{
          'items': <Object?>[
            for (var i = 0; i < 100; i++) _wrongJson('W-$page-$i'),
          ],
          'page': page,
          'pageSize': 100,
          'total': 999999,
        }),
        favoriteHandler: (page) => _json(<String, Object?>{
          'items': <Object?>[_favoriteJson('Q-A')],
          'page': page,
          'pageSize': 100,
          'total': 1,
        }),
        wrongStore: wrongStore,
        favoriteStore: favoriteStore,
      );

      final result = await sync.syncNow();

      expect(result.ok, isTrue);
      // 截断的 5000 条照常合并（新增是安全的），但缺席 ≠ 删除。
      expect(wrongStore.merges.single, hasLength(5000));
      expect(wrongStore.tombstoneCalls, isEmpty);
      // 完整性按类别独立判定：收藏拉全了，照常传播。
      expect(favoriteStore.tombstoneCalls, <Set<String>>[
        <String>{'Q-A'},
      ]);
    });

    test('中途页失败：该类别不合并也不传播删除，文案如实报未更新', () async {
      final wrongStore = _RecordingWrongService();
      final favoriteStore = _RecordingFavoriteService();
      final sync = buildSync(
        wrongHandler: (page) {
          if (page >= 2) return _json(<String, Object?>{}, 500);
          return _json(<String, Object?>{
            'items': <Object?>[_wrongJson('Q-A')],
            'page': page,
            'pageSize': 100,
            'total': 2,
          });
        },
        favoriteHandler: (page) => _json(<String, Object?>{
          'items': <Object?>[_favoriteJson('Q-A')],
          'page': page,
          'pageSize': 100,
          'total': 1,
        }),
        wrongStore: wrongStore,
        favoriteStore: favoriteStore,
      );

      final result = await sync.syncNow();

      expect(result.ok, isTrue);
      expect(wrongStore.merges, isEmpty);
      expect(wrongStore.tombstoneCalls, isEmpty);
      expect(result.message, contains('错题本未更新（拉取失败）'));
      expect(favoriteStore.tombstoneCalls, <Set<String>>[
        <String>{'Q-A'},
      ]);
    });
  });
}
