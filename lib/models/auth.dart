/// 登录/注册结果模型（规格文档第 4 章 §4.7.1；UI 本地对象，非后端契约字段）。
///
/// 字段用 camelCase（与 PracticeSession / ContinueSession 等 UI 本地对象一致）。
library;

import 'user.dart';

/// 登录结果。Mock 演示登录：本地格式校验通过后 success 为 true，user 为本地对象，不发任何网络请求。
///
/// 真实后端（v1.2：登录即注册）在**新手机号首次登录**时随响应下发一次性
/// 12 词恢复码（`restoreCode`）。它是找回密码的唯一凭据，必须展示一次。
class LoginResult {
  const LoginResult({
    required this.success,
    this.user,
    this.message,
    this.restoreCode,
  });

  /// 是否登录成功。
  final bool success;

  /// 登录成功的用户；失败时为 null。
  final User? user;

  /// 失败原因或提示文案；成功时可为 null。
  final String? message;

  /// 新注册账号的一次性恢复码（`restoreCode`）；已有账号或 Mock 为 null。
  final String? restoreCode;

  factory LoginResult.fromJson(Map<String, dynamic> json) {
    return LoginResult(
      success: json['success'] as bool,
      user: json['user'] == null
          ? null
          : User.fromJson(json['user'] as Map<String, dynamic>),
      message: json['message'] as String?,
      restoreCode: json['restoreCode'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'success': success,
      'user': user?.toJson(),
      'message': message,
      'restoreCode': restoreCode,
    };
  }

  @override
  String toString() => 'LoginResult(success: $success)';
}

/// 找回密码结果（F26 chunk 3：`POST /api/v1/auth/recover`）。
///
/// 成功时服务端签发全新双 Token 并**轮换恢复码**：旧 12 词恢复码被消耗，
/// [restoreCode] 是新的唯一凭据，必须一次性展示给用户。
class RecoverResult {
  const RecoverResult({
    required this.success,
    this.user,
    this.message,
    this.restoreCode,
    this.statusCode,
  });

  /// 是否找回成功（成功后会话已按登录流程持久化）。
  final bool success;

  /// 找回成功的用户；失败时为 null。
  final User? user;

  /// 失败原因或提示文案；成功时可为 null。
  final String? message;

  /// 服务端新签发的 12 词恢复码（旧码已失效）；失败时为 null。
  final String? restoreCode;

  /// 失败时的 HTTP 状态码（401 恢复码无效 / 422 格式校验）；
  /// 网络失败或成功时为 null。
  final int? statusCode;

  @override
  String toString() => 'RecoverResult(success: $success)';
}

/// 本地持久化的登录会话（access + refresh 双 Token + 用户）。
///
/// accessToken 由后端签发，TTL 15 分钟；refreshToken TTL 30 天，刷新时轮换。
/// F31 (P2-1)：整体以 JSON 存 flutter_secure_storage（Android Keystore
/// 加密）；旧版明文 kv `auth.session` 只在恢复时作为迁移来源，迁移后即删。
class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.tokenType,
    required this.accessExpiresAt,
    required this.user,
  });

  final String accessToken;
  final String refreshToken;
  final String tokenType;

  /// accessToken 到期时刻（本地时钟）。
  final DateTime accessExpiresAt;

  final User user;

  /// 到期前 60 秒即视为“快过期”，提前刷新，避免请求卡在临界点。
  static const Duration refreshSkew = Duration(seconds: 60);

  bool get isExpiring =>
      DateTime.now().isAfter(accessExpiresAt.subtract(refreshSkew));

  AuthSession copyWith({
    String? accessToken,
    String? refreshToken,
    DateTime? accessExpiresAt,
  }) {
    return AuthSession(
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      tokenType: tokenType,
      accessExpiresAt: accessExpiresAt ?? this.accessExpiresAt,
      user: user,
    );
  }

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String,
      tokenType: json['tokenType'] as String? ?? 'Bearer',
      accessExpiresAt: DateTime.fromMillisecondsSinceEpoch(
        (json['accessExpiresAt'] as num).toInt(),
      ),
      user: User.fromJson(json['user'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'accessToken': accessToken,
      'refreshToken': refreshToken,
      'tokenType': tokenType,
      'accessExpiresAt': accessExpiresAt.millisecondsSinceEpoch,
      'user': user.toJson(),
    };
  }
}

/// 本机设备信息（个人中心“设备”区展示）。
///
/// 后端没有设备列表端点，只有登录时绑定的这一台设备；数据全部来自本机
/// （deviceId 由登录接线生成并持久化，型号 / 版本来自 AppConfig）。
class LocalDeviceInfo {
  const LocalDeviceInfo({
    required this.deviceId,
    required this.deviceModel,
    required this.appVersion,
  });

  final String deviceId;
  final String deviceModel;
  final String appVersion;
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
