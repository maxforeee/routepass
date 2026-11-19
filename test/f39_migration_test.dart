// F39 L8：v3→v4 迁移测试——v3 老库升级后的 schema 必须与全新 v4 库
// 完全一致（v3→v4 分支只在升级路径执行，onCreate 从不走它）。
// 真实 SQLite（sqflite_common_ffi）：老库用临时文件库，新库用内存库。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/core/local_db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('v3 老库升级 v4 后与全新 v4 库 schema 完全一致', () async {
    final dir = Directory.systemTemp.createTempSync('f39_migration');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/upgrade.db';

    // v3 schema = v4 清单去掉 F36 两张持久表（v4 只新增了
    // wrong_book / favorites；set_overview 的 accuracy / by_module
    // 在 v2 / v3 已加，v3 老库建表文本与 v4 清单逐字相同）。
    final v3Schema = localDbSchema
        .where((s) => !s.contains('wrong_book') && !s.contains('favorites'))
        .toList();
    final v3 = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 3,
        onCreate: (db, version) async {
          for (final statement in v3Schema) {
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
}
