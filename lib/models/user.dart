// 字段名必须与规格文档 §4.8 数据契约一字不差（snake_case），故忽略本 lint。
// ignore_for_file: non_constant_identifier_names
/// 用户与设备模型（规格文档第 4 章 §4.8 数据契约）。
///
/// 字段名与数据契约一字不差；服务端返回的数据也必须符合同一契约，
/// 否则校验器（v3.1 附录 B）报错。
library;

/// 用户信息。
class User {
  const User({
    required this.id,
    required this.username,
    required this.nickname,
    this.avatar_url,
  });

  /// 用户 id。
  final String id;

  /// 用户名（登录账号）。
  final String username;

  /// 昵称（展示用）。
  final String nickname;

  /// 头像地址（可为 null）。
  final String? avatar_url;

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      username: json['username'] as String,
      nickname: json['nickname'] as String,
      avatar_url: json['avatar_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'username': username,
      'nickname': nickname,
      'avatar_url': avatar_url,
    };
  }

  @override
  String toString() => 'User($id, $username)';
}

/// 设备信息。
class Device {
  const Device({
    required this.id,
    required this.name,
    required this.last_active_at,
    required this.is_current,
  });

  /// 设备 id。
  final String id;

  /// 设备名称（展示用）。
  final String name;

  /// 最近活跃时间戳（毫秒）。
  final int last_active_at;

  /// 是否为当前设备。
  final bool is_current;

  factory Device.fromJson(Map<String, dynamic> json) {
    return Device(
      id: json['id'] as String,
      name: json['name'] as String,
      last_active_at: json['last_active_at'] as int,
      is_current: json['is_current'] as bool,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'last_active_at': last_active_at,
      'is_current': is_current,
    };
  }

  @override
  String toString() => 'Device($id, $name)';
}
