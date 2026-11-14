/// 真实后端的认证服务（F19：登录页接线）。
///
/// 契约来源：`/workspace/routepass-server/api/app/api/v1/auth.py`（HEAD cfdce4b）。
/// - `POST /api/v1/auth/login`   {phone, password, deviceId, deviceModel, appVersion}
/// - `POST /api/v1/auth/refresh` {refreshToken}（轮换 refresh token）
/// - `POST /api/v1/auth/logout`  Bearer accessToken
///
/// accessToken TTL 15 分钟，refreshToken 30 天；本服务负责持久化双 Token、
/// 到期前自动刷新，并把 accessToken 暴露给 [AuthHttpClient] 附加到
/// 已鉴权请求上（401 时刷新一次并重放）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../../core/config.dart';
import '../../core/kv_store.dart';
import '../../core/service_locator.dart';
import '../../models/auth.dart';
import '../../models/user.dart';
import '../base/auth_service.dart';

/// 认证接口错误（仅内部使用；登录失败通过 [LoginResult.message] 回给 UI）。
class AuthException implements Exception {
  const AuthException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'AuthException($statusCode): $message';
}

class HttpAuthService extends AuthService {
  HttpAuthService({
    http.Client? client,
    KvStore? kvStore,
    String? baseUrl,
    String? deviceId,
    String? deviceModelOverride,
    String? appVersion,
  }) : _client = client ?? http.Client(),
       _kv = kvStore ?? ServiceLocator.kvStore,
       _baseUrl = baseUrl ?? AppConfig.baseUrl,
       _deviceIdOverride = deviceId,
       _deviceModel = deviceModelOverride,
       _appVersion = appVersion ?? AppConfig.version;

  final http.Client _client;
  final KvStore _kv;
  final String _baseUrl;

  /// 测试可注入固定 deviceId；生产为 null，首次启动生成并持久化。
  final String? _deviceIdOverride;
  final String? _deviceModel;
  final String _appVersion;

  static const Duration _timeout = Duration(seconds: 10);

  AuthSession? _session;
  bool _loaded = false;
  Future<bool>? _refreshing;

  @override
  Future<User?> getCurrentUser() async {
    await _ensureLoaded();
    return _session?.user;
  }

  @override
  Future<LoginResult> login({
    required String phone,
    required String password,
  }) async {
    final body = <String, String>{
      'phone': phone,
      'password': password,
      'deviceId': await _deviceId(),
      'deviceModel': _deviceModel ?? _defaultDeviceModel(),
      'appVersion': _appVersion,
    };
    try {
      final response = await _client
          .post(
            Uri.parse('$_baseUrl/api/v1/auth/login'),
            headers: const <String, String>{'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      if (response.statusCode != 200) {
        return LoginResult(
          success: false,
          message: _messageFor(
            response,
            fallback: _fallbackMessage(response.statusCode),
          ),
        );
      }
      final decoded = _decodeMap(response);
      final session = _sessionFromLogin(decoded, phone);
      _session = session;
      await _persist(session);
      return LoginResult(
        success: true,
        user: session.user,
        restoreCode: decoded['restoreCode'] as String?,
      );
    } on FormatException {
      return const LoginResult(success: false, message: '登录响应格式错误，请稍后重试');
    } catch (_) {
      return const LoginResult(success: false, message: '网络连接失败，请检查网络后重试');
    }
  }

  @override
  Future<RegisterResult> register({
    required String phone,
    required String password,
    required String nickname,
  }) async {
    // v1.2 登录即注册：后端没有独立 register 端点，复用 login。
    final result = await login(phone: phone, password: password);
    if (!result.success) {
      return RegisterResult(success: false, message: result.message);
    }
    return RegisterResult(
      success: true,
      user: result.user,
      recoveryCode: result.restoreCode,
    );
  }

  @override
  Future<void> logout() async {
    await _ensureLoaded();
    final token = _session?.accessToken;
    if (token != null && token.isNotEmpty) {
      try {
        await _client
            .post(
              Uri.parse('$_baseUrl/api/v1/auth/logout'),
              headers: <String, String>{'Authorization': 'Bearer $token'},
            )
            .timeout(_timeout);
      } catch (_) {
        // 离线也照常清本地会话：登出不能被网络阻塞。
      }
    }
    clearSession();
  }

  @override
  Future<List<Device>> getDevices() async {
    // 后端只做了设备绑定的登录校验，没有下发设备列表的端点；不编造数据。
    return const <Device>[];
  }

  @override
  Future<LocalDeviceInfo?> currentDevice() async {
    return LocalDeviceInfo(
      deviceId: await _deviceId(),
      deviceModel: _deviceModel ?? _defaultDeviceModel(),
      appVersion: _appVersion,
    );
  }

  @override
  Future<String?> getRecoveryCodeHint() async {
    // 恢复码只在注册响应里出现一次，服务端不提供回读；G-03 显示“未设置”。
    return null;
  }

  @override
  Future<String?> accessToken({bool forceRefresh = false}) async {
    await _ensureLoaded();
    final session = _session;
    if (session == null) return null;
    if (forceRefresh || session.isExpiring) {
      await refreshAccessToken();
    }
    return _session?.accessToken;
  }

  @override
  Future<bool> refreshAccessToken() {
    final inFlight = _refreshing;
    if (inFlight != null) return inFlight;
    final future = _doRefresh();
    _refreshing = future;
    return future.whenComplete(() => _refreshing = null);
  }

  Future<bool> _doRefresh() async {
    await _ensureLoaded();
    final session = _session;
    if (session == null || session.refreshToken.isEmpty) return false;
    try {
      final response = await _client
          .post(
            Uri.parse('$_baseUrl/api/v1/auth/refresh'),
            headers: const <String, String>{'Content-Type': 'application/json'},
            body: jsonEncode(<String, String>{
              'refreshToken': session.refreshToken,
            }),
          )
          .timeout(_timeout);
      if (response.statusCode == 200) {
        final decoded = _decodeMap(response);
        final access = decoded['accessToken'] as String?;
        final refresh = decoded['refreshToken'] as String?;
        if (access == null || access.isEmpty || refresh == null) {
          return false;
        }
        final updated = session.copyWith(
          accessToken: access,
          refreshToken: refresh,
          accessExpiresAt: _expiresAt(decoded),
        );
        _session = updated;
        await _persist(updated);
        return true;
      }
      if (response.statusCode == 401 || response.statusCode == 403) {
        // refreshToken 失效 / 被撤销 / 过期：会话结束，回到登录页。
        _expireSession();
      }
      return false;
    } catch (_) {
      // 网络失败不清会话：恢复网络后仍可继续用 refreshToken 换新 Token。
      return false;
    }
  }

  @override
  String? get cachedAccessToken => _session?.accessToken;

  @override
  void clearSession() {
    _session = null;
    _kv.remove(KvStore.keyAuthSession);
  }

  void _expireSession() {
    clearSession();
    onSessionExpired?.call();
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    final raw = _kv.getString(KvStore.keyAuthSession);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        _session = AuthSession.fromJson(decoded);
      } else {
        _kv.remove(KvStore.keyAuthSession);
      }
    } catch (_) {
      _kv.remove(KvStore.keyAuthSession);
    }
  }

  AuthSession _sessionFromLogin(Map<String, dynamic> decoded, String phone) {
    final access = decoded['accessToken'] as String?;
    final refresh = decoded['refreshToken'] as String?;
    final userJson = decoded['user'];
    if (access == null ||
        access.isEmpty ||
        refresh == null ||
        refresh.isEmpty ||
        userJson is! Map<String, dynamic>) {
      throw const FormatException('login response missing tokens/user');
    }
    final id = userJson['id'];
    return AuthSession(
      accessToken: access,
      refreshToken: refresh,
      tokenType: decoded['tokenType'] as String? ?? 'Bearer',
      accessExpiresAt: _expiresAt(decoded),
      user: User(
        id: id?.toString() ?? '',
        username: phone,
        nickname: userJson['nickname'] as String? ?? phone,
        avatar_url: userJson['avatarUrl'] as String?,
      ),
    );
  }

  DateTime _expiresAt(Map<String, dynamic> decoded) {
    final seconds = (decoded['expiresIn'] as num?)?.toInt() ?? 900;
    return DateTime.now().add(Duration(seconds: seconds));
  }

  Future<void> _persist(AuthSession session) async {
    _kv.setString(KvStore.keyAuthSession, jsonEncode(session.toJson()));
  }

  Future<String> _deviceId() async {
    final override = _deviceIdOverride;
    if (override != null && override.isNotEmpty) return override;
    final stored = _kv.getString(KvStore.keyAuthDeviceId);
    if (stored != null && stored.isNotEmpty) return stored;
    final generated = _generateUuid();
    _kv.setString(KvStore.keyAuthDeviceId, generated);
    return generated;
  }

  String _defaultDeviceModel() {
    final version = Platform.operatingSystemVersion;
    return version.isEmpty
        ? Platform.operatingSystem
        : '${Platform.operatingSystem} $version';
  }

  /// UUID v4（36 字符 < 服务端 deviceId 40 字符上限）。
  static String _generateUuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }

  Map<String, dynamic> _decodeMap(http.Response response) {
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('expected JSON object');
    }
    return decoded;
  }

  /// 错误体两种形状都兼容：
  /// - 线上网关：`{"error": {"code": "...", "message": "..."}}`（已实测）；
  /// - FastAPI 原生：`{"detail": "..."}` 或校验数组 `[{msg}]`。
  String _messageFor(http.Response response, {required String fallback}) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) {
        final error = decoded['error'];
        if (error is Map<String, dynamic>) {
          final message = error['message'];
          if (message is String && message.isNotEmpty) return message;
        }
        final detail = decoded['detail'];
        if (detail is String && detail.isNotEmpty) return detail;
        if (detail is List) {
          final messages = detail
              .whereType<Map<String, dynamic>>()
              .map((item) => item['msg'])
              .whereType<String>()
              .where((msg) => msg.isNotEmpty)
              .toList();
          if (messages.isNotEmpty) return messages.join('；');
        }
        final message = decoded['message'];
        if (message is String && message.isNotEmpty) return message;
      }
    } catch (_) {
      // 非 JSON 错误体：用状态码兜底文案。
    }
    return fallback;
  }

  String _fallbackMessage(int statusCode) {
    switch (statusCode) {
      case 401:
        return '手机号或密码错误';
      case 409:
        return '该设备已绑定其他账号，或该账号设备数已达上限';
      case 422:
        return '手机号或密码格式不正确';
      default:
        return '登录失败（HTTP $statusCode）';
    }
  }
}

/// 已鉴权请求客户端：附加 `Authorization: Bearer <accessToken>`；
/// 遇到 401 时刷新一次 Token 并重放请求；刷新被拒则把 401 交还调用方。
///
/// accessToken 只有 15 分钟，没有这一层 S11 调用会在 15 分钟后集体 401。
class AuthHttpClient extends http.BaseClient {
  AuthHttpClient({required this.auth, http.Client? inner})
    : _inner = inner ?? http.Client();

  final AuthService auth;
  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // 只有普通 Request 可安全重放（服务层只发 get/post 字符串体）。
    if (request is! http.Request) return _inner.send(request);

    final token = await auth.accessToken();
    var response = await _inner.send(_clone(request, token));
    if (response.statusCode != 401) return response;

    final refreshed = await auth.refreshAccessToken();
    if (!refreshed) return response;

    try {
      await response.stream.drain<void>();
    } catch (_) {
      // 原响应体读不出也不影响重放。
    }
    return _inner.send(_clone(request, auth.cachedAccessToken));
  }

  http.Request _clone(http.Request source, String? token) {
    final copy = http.Request(source.method, source.url)
      ..headers.addAll(source.headers)
      ..followRedirects = source.followRedirects
      ..maxRedirects = source.maxRedirects
      ..persistentConnection = source.persistentConnection
      ..bodyBytes = source.bodyBytes;
    if (token != null && token.isNotEmpty) {
      copy.headers['Authorization'] = 'Bearer $token';
    } else {
      copy.headers.remove('Authorization');
    }
    return copy;
  }
}
