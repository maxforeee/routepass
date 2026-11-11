/// 本地 kv 抽象接口（规格文档第 4 章 §4.9.1）。
///
/// 以下键是设备本地 UI 状态，换手机不跟随账号，现在和以后都只存本地、
/// 不走账号同步。背后的 DAO 为 `lib/dao/kv_dao.dart`（v3.1 第 12 章 `kv`
/// 表，主键 `(owner_user_id, key)`，同一 key 不同账号互不覆盖）。
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
  List<String>? getStringList(String key) =>
      _stringLists[key] == null ? null : List<String>.unmodifiable(
        _stringLists[key]!,
      );

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
