/// W1：web 平台的 SQLite 装配（sqflite_common_ffi_web）。
///
/// sqlite3 wasm + IndexedDB 持久化；数据库名即路径（无文件系统目录）。
/// 构建前需 `dart run sqflite_common_ffi_web:setup` 把 wasm/worker
/// 资产拷进 web/。Android 不导入本文件（条件导入见 local_db.dart）。
library;

import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

DatabaseFactory get platformDatabaseFactory => databaseFactoryFfiWeb;

Future<String> platformDatabasePath(String fileName) async => fileName;
