/// 登录/注册结果模型（规格文档第 4 章 §4.7.1；UI 本地对象，非后端契约字段）。
///
/// 字段用 camelCase（与 PracticeSession / ContinueSession 等 UI 本地对象一致）。
library;

import 'user.dart';

/// 登录结果。Mock 演示登录：本地格式校验通过后 success 为 true，user 为本地对象，不发任何网络请求。
class LoginResult {
  const LoginResult({required this.success, this.user, this.message});

  /// 是否登录成功。
  final bool success;

  /// 登录成功的用户；失败时为 null。
  final User? user;

  /// 失败原因或提示文案；成功时可为 null。
  final String? message;

  factory LoginResult.fromJson(Map<String, dynamic> json) {
    return LoginResult(
      success: json['success'] as bool,
      user: json['user'] == null
          ? null
          : User.fromJson(json['user'] as Map<String, dynamic>),
      message: json['message'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'success': success,
      'user': user?.toJson(),
      'message': message,
    };
  }

  @override
  String toString() => 'LoginResult(success: $success)';
}

/// 注册结果。Mock 与登录相同的本地演示流程；recoveryCode 只在以后真实注册成功后才有值。
class RegisterResult {
  const RegisterResult({
    required this.success,
    this.user,
    this.message,
    this.recoveryCode,
  });

  /// 是否注册成功。
  final bool success;

  /// 注册成功的用户；失败时为 null。
  final User? user;

  /// 失败原因或提示文案；成功时可为 null。
  final String? message;

  /// 注册成功后发的 12 词恢复码（v3.1 D17）；Mock 演示流程下为 null。
  final String? recoveryCode;

  factory RegisterResult.fromJson(Map<String, dynamic> json) {
    return RegisterResult(
      success: json['success'] as bool,
      user: json['user'] == null
          ? null
          : User.fromJson(json['user'] as Map<String, dynamic>),
      message: json['message'] as String?,
      recoveryCode: json['recoveryCode'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'success': success,
      'user': user?.toJson(),
      'message': message,
      'recoveryCode': recoveryCode,
    };
  }

  @override
  String toString() => 'RegisterResult(success: $success)';
}
