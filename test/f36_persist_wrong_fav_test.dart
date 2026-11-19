// F36：错题本 / 收藏本地持久化（wrong_book / favorites，schema v4）。
// 真实 SQLite（sqflite_common_ffi 内存库），与 cache_first_test 同一模式。
import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/core/local_db.dart';
import 'package:routepass/models/wrong_favorite.dart';
import 'package:routepass/services/bank/local_cache_service.dart';
import 'package:routepass/services/bank/sqlite_wrong_favorite_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

WrongItem _wrong(
  String id, {
  int count = 1,
  int lastWrongAt = 2000,
  bool mastered = false,
  int? removedAt,
}) {
  return WrongItem(
    question_id: id,
    wrong_count: count,
    last_wrong_at: lastWrongAt,
    mastered: mastered,
    removed_at: removedAt,
  );
}

void main() {
  late SqfliteLocalDatabase db;
  late SqliteWrongService wrong;
  late SqliteFavoriteService favorites;

  setUpAll(sqfliteFfiInit);

  setUp(() {
    db = SqfliteLocalDatabase(
      dbPath: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    wrong = SqliteWrongService(db);
    favorites = SqliteFavoriteService(db);
  });

  tearDown(() => db.close());

  test('(e) 全新持久 store 为空：不预置演示数据（诚实空态）', () async {
    expect(await wrong.getWrongBook(), isEmpty);
    expect(await favorites.getFavorites(), isEmpty);
    expect(await favorites.getFavoriteIds(), isEmpty);
  });

  test('(a) addWrong + toggleFavorite 落 SQLite：同库第二个 store 实例读回', () async {
    await wrong.addWrong('VLAN-1');
    await wrong.addWrong('VLAN-1');
    await favorites.toggleFavorite('VLAN-1', true);
    await favorites.toggleFavorite('OSPF-1', true);

    // F39 L7：内存库上的“重启”实为同库重读——全新 store 实例、没有任何
    // 同步，证明写入已落 SQLite（服务无状态、直接查库）；不证明跨进程
    // 重启的持久性（那需要真实文件库）。
    final wrong2 = SqliteWrongService(db);
    final favorites2 = SqliteFavoriteService(db);

    final items = await wrong2.getWrongBook();
    expect(items, hasLength(1));
    expect(items.first.question_id, 'VLAN-1');
    expect(items.first.wrong_count, 2);
    expect(items.first.mastered, isFalse);
    expect(items.first.removed_at, isNull);

    // F39 L5：排序契约是 created_at ASC（question_id 打破平局），不再是
    // rowid 插入序；两次收藏可能落在同一毫秒，断言无序成员 + 时间非递减。
    expect(
      await favorites2.getFavoriteIds(),
      unorderedEquals(<String>['VLAN-1', 'OSPF-1']),
    );
    final favs = await favorites2.getFavorites();
    expect(favs, hasLength(2));
    expect(favs.first.created_at, greaterThan(0));
    for (var i = 1; i < favs.length; i++) {
      expect(favs[i].created_at, greaterThanOrEqualTo(favs[i - 1].created_at));
    }
  });

  test('(g) F39 M3：重复收藏已收藏的题保留原 created_at', () async {
    // 服务端物化写入一个确定的 created_at。
    expect(
      await favorites.mergeFromServer(<Favorite>[
        const Favorite(question_id: 'VLAN-1', created_at: 2000),
      ]),
      1,
    );
    // 再收藏（INSERT OR IGNORE）不得把 created_at 顶成 now，
    // 否则后续 LWW 会拿被顶高的本地时间压掉更新的服务端条目。
    await favorites.toggleFavorite('VLAN-1', true);
    expect((await favorites.getFavorites()).single.created_at, 2000);
    // 更新的服务端条目仍能正常覆盖。
    expect(
      await favorites.mergeFromServer(<Favorite>[
        const Favorite(question_id: 'VLAN-1', created_at: 3000),
      ]),
      1,
    );
    expect((await favorites.getFavorites()).single.created_at, 3000);
  });

  test('(a) 取消收藏同库重读仍为取消态', () async {
    await favorites.toggleFavorite('VLAN-1', true);
    await favorites.toggleFavorite('VLAN-1', false);
    final favorites2 = SqliteFavoriteService(db);
    expect(await favorites2.getFavoriteIds(), isEmpty);
  });

  test('(d) markMastered 持久化；再做错 mastered 置回 false 且次数 +1', () async {
    await wrong.addWrong('VLAN-1');
    await wrong.markMastered('VLAN-1');

    final wrong2 = SqliteWrongService(db);
    final mastered = await wrong2.getWrongBook(masteredOnly: true);
    expect(mastered, hasLength(1));
    expect(mastered.first.mastered, isTrue);
    expect(await wrong2.getWrongBook(masteredOnly: false), isEmpty);

    // §4.8.7：wrong_add 强制 mastered=false、wrong_count+1。
    await wrong2.addWrong('VLAN-1');
    final wrong3 = SqliteWrongService(db);
    final items = await wrong3.getWrongBook();
    expect(items.single.mastered, isFalse);
    expect(items.single.wrong_count, 2);
  });

  test('(b) 错题 mergeFromServer：last-write-wins，服务端更旧保留本地', () async {
    expect(
      await wrong.mergeFromServer(<WrongItem>[_wrong('VLAN-1', count: 3)]),
      1,
    );
    // 更旧的服务端条目：不覆盖。
    expect(
      await wrong.mergeFromServer(<WrongItem>[
        _wrong('VLAN-1', count: 9, lastWrongAt: 1000),
      ]),
      0,
    );
    expect((await wrong.getWrongBook()).single.wrong_count, 3);
    // 更新的服务端条目：覆盖。
    expect(
      await wrong.mergeFromServer(<WrongItem>[
        _wrong('VLAN-1', count: 5, lastWrongAt: 3000, mastered: true),
      ]),
      1,
    );
    final item = (await wrong.getWrongBook()).single;
    expect(item.wrong_count, 5);
    expect(item.last_wrong_at, 3000);
    expect(item.mastered, isTrue);
    // F39 M8：时间戳相等 → 覆盖（LWW 是 < 比较，相等不保留本地）。
    expect(
      await wrong.mergeFromServer(<WrongItem>[
        _wrong('VLAN-1', count: 6, lastWrongAt: 3000),
      ]),
      1,
    );
    expect((await wrong.getWrongBook()).single.wrong_count, 6);
    // 服务端独有 → 新增；空 id 跳过。
    expect(
      await wrong.mergeFromServer(<WrongItem>[_wrong('OSPF-1'), _wrong('')]),
      1,
    );
    expect(await wrong.getWrongBook(), hasLength(2));
  });

  test('(b) 收藏 mergeFromServer：last-write-wins，服务端更旧保留本地', () async {
    const local = Favorite(question_id: 'VLAN-1', created_at: 2000);
    expect(await favorites.mergeFromServer(<Favorite>[local]), 1);
    expect(
      await favorites.mergeFromServer(<Favorite>[
        const Favorite(question_id: 'VLAN-1', created_at: 1000),
      ]),
      0,
    );
    expect((await favorites.getFavorites()).single.created_at, 2000);
    // F39 M8/L7：created_at 相等 → 覆盖，返回 1（确定性结果）。
    expect(
      await favorites.mergeFromServer(<Favorite>[
        const Favorite(question_id: 'VLAN-1', created_at: 2000),
      ]),
      1,
    );
    expect((await favorites.getFavorites()).single.created_at, 2000);
    expect(
      await favorites.mergeFromServer(<Favorite>[
        const Favorite(question_id: 'VLAN-1', created_at: 3000),
      ]),
      1,
    );
    expect((await favorites.getFavorites()).single.created_at, 3000);
    // 服务端独有 → 新增；空 id 跳过。
    expect(
      await favorites.mergeFromServer(<Favorite>[
        const Favorite(question_id: 'OSPF-1', created_at: 500),
        const Favorite(question_id: '', created_at: 500),
      ]),
      1,
    );
    expect(await favorites.getFavoriteIds(), hasLength(2));
    // F39 L5：排序按 created_at ASC，不是插入序（OSPF-1@500 在前）。
    expect(await favorites.getFavoriteIds(), <String>['OSPF-1', 'VLAN-1']);
  });

  test('(c) removeWrong 写墓碑：列表隐藏，更旧的服务端数据不复活', () async {
    await wrong.addWrong('VLAN-1');
    await wrong.removeWrong('VLAN-1');
    expect(await wrong.getWrongBook(), isEmpty);

    // 行还在（墓碑，不是删行）。
    final rows = await db.rawQuery(
      'SELECT removed_at FROM wrong_book WHERE question_id = ?',
      <Object?>['VLAN-1'],
    );
    expect(rows, hasLength(1));
    expect(rows.first['removed_at'], isNotNull);

    // F39 L7：同库重读证明墓碑已落 SQLite；更旧的服务端条目不复活。
    final wrong2 = SqliteWrongService(db);
    expect(
      await wrong2.mergeFromServer(<WrongItem>[
        _wrong('VLAN-1', lastWrongAt: 1),
      ]),
      0,
    );
    expect(await wrong2.getWrongBook(), isEmpty);

    // F39 M8：服务端时间恰好等于墓碑 → 不复活（<= 比较）。
    final tombstone = (rows.first['removed_at'] as num).toInt();
    expect(
      await wrong2.mergeFromServer(<WrongItem>[
        _wrong('VLAN-1', lastWrongAt: tombstone),
      ]),
      0,
    );
    expect(await wrong2.getWrongBook(), isEmpty);

    // 移除之后又做错（服务端时间晚于墓碑）→ 复活。
    final future = DateTime.now().millisecondsSinceEpoch + 3600 * 1000;
    expect(
      await wrong2.mergeFromServer(<WrongItem>[
        _wrong('VLAN-1', lastWrongAt: future),
      ]),
      1,
    );
    expect((await wrong2.getWrongBook()).single.question_id, 'VLAN-1');
  });

  test('(c) 移除后再做错（addWrong）复活并清墓碑；移除不存在的题 no-op', () async {
    await wrong.removeWrong('NOPE');
    expect(await wrong.getWrongBook(), isEmpty);

    await wrong.addWrong('VLAN-1');
    await wrong.removeWrong('VLAN-1');
    await wrong.addWrong('VLAN-1');
    final item = (await wrong.getWrongBook()).single;
    expect(item.wrong_count, 2);
    expect(item.removed_at, isNull);
  });

  test('(f) 登出 clearAll：wrong_book / favorites 一并清空', () async {
    await wrong.addWrong('VLAN-1');
    await favorites.toggleFavorite('VLAN-1', true);
    expect(await wrong.getWrongBook(), hasLength(1));
    expect(await favorites.getFavoriteIds(), hasLength(1));

    // 与生产登出同一路径：HttpAuthService.clearAllAccountData →
    // BankLocalCache.clearAll()（同一个库）。
    await SqliteBankLocalCache(db).clearAll();

    expect(await wrong.getWrongBook(), isEmpty);
    expect(await favorites.getFavorites(), isEmpty);
    expect(await favorites.getFavoriteIds(), isEmpty);
    final wrongRows = await db.rawQuery('SELECT * FROM wrong_book');
    final favRows = await db.rawQuery('SELECT * FROM favorites');
    expect(wrongRows, isEmpty);
    expect(favRows, isEmpty);
  });
}
