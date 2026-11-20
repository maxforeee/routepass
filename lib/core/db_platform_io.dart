/// W1：原生平台（Android / iOS）的 SQLite 装配。
///
/// 沿用 sqflite 默认工厂与数据库目录，行为与 W1 之前完全一致；
/// 由 local_db.dart 的条件导入在非 web 平台选中本文件。
library;

import 'package:sqflite/sqflite.dart';

DatabaseFactory get platformDatabaseFactory => databaseFactory;

Future<String> platformDatabasePath(String fileName) async =>
    '${await getDatabasesPath()}/$fileName';
