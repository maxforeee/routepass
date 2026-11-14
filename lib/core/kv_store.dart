/// 本地 kv 抽象接口（规格文档第 4 章 §4.9.1）。
///
/// 以下键是设备本地 UI 状态，换手机不跟随账号，现在和以后都只存本地、
/// 不走账号同步。背后的 DAO 为 `lib/dao/kv_dao.dart`（v3.1 第 12 章 `kv`
/// 表，主键 `(owner_user_id, key)`，同一 key 不同账号互不覆盖）。
library;

import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

abstract class KvStore {
  /// `kb.expandedIds`：知识库页同节单开手风琴的展开态（JSON 数组，
  /// 如 `["VLAN-01-03"]`）。用户点倒三角展开/收起时写入。
  static const String keyKbExpandedIds = 'kb.expandedIds';

  /// `toolbox.recent`：工具箱 T-04 最近使用（JSON 数组，如
  /// `["subnet", "ping"]`，最多 5 个）。用户用完一个工具时写入。
  static const String keyToolboxRecent = 'toolbox.recent';

  /// `home.continue`：首页 H-B1 继续学习的进度指针（JSON 对象
  /// `{mode, questionId, answeredCount, totalCount}`）。答题会话中途退出时
  /// 写入；会话完成时清除。
  static const String keyHomeContinue = 'home.continue';

  /// `ui.lastTab`：上次停留的底栏目的地（string，如 `"knowledge"`，
  /// 下次启动恢复）。切 tab 时写入。
  static const String keyUiLastTab = 'ui.lastTab';

  /// `daily.answer`：每日一练当天的作答（JSON 对象
  /// `{date, questionId, selectedKey}`，date 为 `yyyy-MM-dd`）。设备本地，
  /// 一天一条；日期不匹配当天即视为未作答（第二天自动刷新）。
  static const String keyDailyAnswer = 'daily.answer';

  /// `daily.drawn`：每日一练当天抽中的题（F17，JSON 对象
  /// `{date, question}`，date 为 `yyyy-MM-dd`，question 为 DailyQuestion
  /// JSON）。日期锁：同一天直接返回存好的题（不重抽、不走网络），
  /// 第二天重抽并覆盖。必须持久化（重启不丢），见 SharedPreferencesKvStore。
  static const String keyDailyDrawn = 'daily.drawn';

  /// `answer.records`：答题记录（F19，JSON 数组，按 updatedAt 倒序）。
  static const String keyAnswerRecords = 'answer.records';

  /// `answer.target`：上次练习目标（F19，int 字符串，缺省 20）。
  static const String keyAnswerTarget = 'answer.target';

  /// 进行态 key：`answer.session.<mode>.<setId>`（练习与考试分开）。
  static String answerSessionKey(String mode, String setId) =>
      'answer.session.$mode.$setId';

  /// 读取字符串值，不存在时返回 null。
  String? getString(String key);

  /// 写入字符串值。
  void setString(String key, String value);

  /// 读取字符串列表值，不存在时返回 null。
  List<String>? getStringList(String key);

  /// 写入字符串列表值。
  void setStringList(String key, List<String> value);

  /// 删除键。
  void remove(String key);
}

/// 基于 Map 的内存实现，用于测试与接后端前的过渡。
class InMemoryKvStore implements KvStore {
  final Map<String, String> _strings = <String, String>{};
  final Map<String, List<String>> _stringLists = <String, List<String>>{};

  @override
  String? getString(String key) => _strings[key];

  @override
  void setString(String key, String value) {
    _strings[key] = value;
    _stringLists.remove(key);
  }

  @override
  List<String>? getStringList(String key) => _stringLists[key] == null
      ? null
      : List<String>.unmodifiable(_stringLists[key]!);

  @override
  void setStringList(String key, List<String> value) {
    _stringLists[key] = List<String>.of(value);
    _strings.remove(key);
  }

  @override
  void remove(String key) {
    _strings.remove(key);
    _stringLists.remove(key);
  }
}

/// shared_preferences -backed 持久实现（F17）：重启不丢，每日一练的
/// 日期锁（`daily.drawn`）与作答（`daily.answer`）等本地状态用它落盘。
/// main.dart 在 runApp 前用 [create] 装配进 ServiceLocator.kvStore；
/// 测试仍用 [InMemoryKvStore]。接口与内存实现完全一致，调用方不动。
class SharedPreferencesKvStore implements KvStore {
  SharedPreferencesKvStore._(this._prefs);

  final SharedPreferences _prefs;

  /// 异步加载平台存储；在 runApp 前调用一次。
  static Future<SharedPreferencesKvStore> create() async {
    return SharedPreferencesKvStore._(await SharedPreferences.getInstance());
  }

  @override
  String? getString(String key) => _prefs.getString(key);

  @override
  void setString(String key, String value) {
    unawaited(_prefs.setString(key, value));
  }

  @override
  List<String>? getStringList(String key) => _prefs.getStringList(key);

  @override
  void setStringList(String key, List<String> value) {
    unawaited(_prefs.setStringList(key, value));
  }

  @override
  void remove(String key) {
    unawaited(_prefs.remove(key));
  }
}
