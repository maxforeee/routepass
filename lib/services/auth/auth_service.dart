/// 真实后端的认证服务（F19：登录页接线）。
///
/// 契约来源：`/workspace/routepass-server/api/app/api/v1/auth.py`（HEAD cfdce4b）。
/// - `POST /api/v1/auth/login`   {phone, password, deviceId, deviceModel, appVersion}
/// - `POST /api/v1/auth/refresh` {refreshToken}（轮换 refresh token）
/// - `POST /api/v1/auth/logout`  Bearer accessToken
/// - `GET  /api/v1/auth/devices` Bearer accessToken（F34 B3：绑定设备列表）
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
import '../bank/local_cache_service.dart';
import '../base/auth_service.dart';
import 'secure_session_store.dart';

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
    SecureSessionStore? secureStore,
    String? baseUrl,
    String? deviceId,
    String? deviceModelOverride,
    String? appVersion,
    this._localCache,
    this.fallback,
  }) : _client = client ?? http.Client(),
       _kv = kvStore ?? ServiceLocator.kvStore,
       _secure = secureStore ?? FlutterSecureSessionStore(),
       _baseUrl = baseUrl ?? AppConfig.baseUrl,
       _deviceIdOverride = deviceId,
       _deviceModel = deviceModelOverride,
       _appVersion = appVersion ?? AppConfig.version;

  final http.Client _client;
  final KvStore _kv;

  /// F31 (P2-1)：双 Token + 用户整体存加密存储；kv `auth.session`
  /// 只作为旧版本明文会话的迁移来源，迁移后即删。
  final SecureSessionStore _secure;
  final String _baseUrl;

  /// F25：登出时一并清空的 SQLite 缓存（main.dart 装配同一实例）。
  final BankLocalCache? _localCache;

  /// 测试可注入固定 deviceId；生产为 null，首次启动生成并持久化。
  final String? _deviceIdOverride;
  final String? _deviceModel;
  final String _appVersion;

  /// F34 (B3)：未登录 / 离线 / 接口未就绪时的本地兜底（生产为
  /// MockAuthService：空列表，绝不编造设备）。
  final AuthService? fallback;

  /// F34 (B3)：getDevices 的已鉴权客户端（AuthHttpClient：附加 Bearer、
  /// 401 刷新一次并重放）。它依赖本服务，由 main.dart 在构造后赋值
  ///（与 onSessionExpired 相同的装配顺序）。
  http.Client? authClient;

  static const Duration _timeout = Duration(seconds: 10);

  AuthSession? _session;
  Future<void>? _loading;
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
  Future<RecoverResult> recover({
    required String phone,
    required String restoreCode,
    required String newPassword,
  }) async {
    final body = <String, String>{
      'phone': phone,
      'restoreCode': restoreCode,
      'newPassword': newPassword,
    };
    try {
      final response = await _client
          .post(
            Uri.parse('$_baseUrl/api/v1/auth/recover'),
            headers: const <String, String>{'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      if (response.statusCode != 200) {
        return RecoverResult(
          success: false,
          message: _messageFor(
            response,
            fallback: _recoverFallbackMessage(response.statusCode),
          ),
          statusCode: response.statusCode,
        );
      }
      final decoded = _decodeMap(response);
      final session = _sessionFromLogin(decoded, phone);
      _session = session;
      await _persist(session);
      return RecoverResult(
        success: true,
        user: session.user,
        restoreCode: decoded['restoreCode'] as String?,
      );
    } on FormatException {
      return const RecoverResult(success: false, message: '找回密码响应格式错误，请稍后重试');
    } catch (_) {
      return const RecoverResult(success: false, message: '网络连接失败，请检查网络后重试');
    }
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
        // 离线也照常清本地数据：登出不能被网络阻塞。
      }
    }
    await clearAllAccountData();
  }

  @override
  Future<List<Device>> getDevices() async {
    await _ensureLoaded();
    if (_session == null) return _fallbackDevices();
    try {
      final response = await (authClient ?? _client)
          .get(Uri.parse('$_baseUrl/api/v1/auth/devices'))
          .timeout(_timeout);
      if (response.statusCode != 200) return _fallbackDevices();
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final items = decoded is Map<String, dynamic> ? decoded['devices'] : null;
      if (items is! List) return _fallbackDevices();
      // 服务端已按 last_active_at 倒序；保持原序，缺字段行丢弃，不编造。
      return items
          .whereType<Map<String, dynamic>>()
          .map(_deviceFromJson)
          .whereType<Device>()
          .toList();
    } catch (_) {
      return _fallbackDevices();
    }
  }

  Future<List<Device>> _fallbackDevices() {
    return fallback?.getDevices() ??
        Future<List<Device>>.value(const <Device>[]);
  }

  /// GET /auth/devices 行 → 契约模型 Device（§4.8）：
  /// device_name → name，ISO 时间 → 毫秒时间戳，is_current 原样。
  static Device? _deviceFromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final lastActive = DateTime.tryParse(
      json['last_active_at'] as String? ?? '',
    );
    if (id is! String || id.isEmpty || lastActive == null) return null;
    final name = json['device_name'];
    return Device(
      id: id,
      name: name is String && name.isNotEmpty ? name : '未知设备',
      last_active_at: lastActive.millisecondsSinceEpoch,
      is_current: json['is_current'] as bool? ?? false,
      app_version: json['app_version'] as String?,
    );
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
        await _expireSession();
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
  Future<void> clearSession() async {
    _session = null;
    _kv.remove(KvStore.keyAuthSession);
    await _secure.delete();
  }

  @override
  Future<void> clearAllAccountData() async {
    await clearSession();
    _kv.clearAccountData();
    final cache = _localCache;
    if (cache == null) return;
    try {
      await cache.clearAll();
    } catch (_) {
      // SQLite 清除失败不阻塞登出：会话与 kv 已清，本地登出必须完成。
    }
  }

  Future<void> _expireSession() async {
    await clearSession();
    onSessionExpired?.call();
  }

  Future<void> _ensureLoaded() {
    // 加密读取是异步的：并发调用共享同一次加载，避免重复迁移。
    return _loading ??= _loadSession();
  }

  /// F31 (P2-1)：优先读加密存储；没有则把旧版明文 kv `auth.session`
  /// 迁移进来（先写加密、成功后再删明文），老用户升级不被登出。
  Future<void> _loadSession() async {
    String? secureRaw;
    try {
      secureRaw = await _secure.read();
    } catch (_) {
      // Keystore 异常（如备份恢复后密钥失效）不阻塞启动：
      // 回退尝试旧明文会话，仍在登录态。
    }
    if (secureRaw != null && secureRaw.isNotEmpty) {
      final session = _tryDecodeSession(secureRaw);
      if (session != null) {
        _session = session;
        // 清掉可能残留的明文副本（如上次迁移中断）。
        _kv.remove(KvStore.keyAuthSession);
        return;
      }
      await _secure.delete();
    }
    final legacyRaw = _kv.getString(KvStore.keyAuthSession);
    if (legacyRaw == null || legacyRaw.isEmpty) return;
    final session = _tryDecodeSession(legacyRaw);
    if (session == null) {
      _kv.remove(KvStore.keyAuthSession);
      return;
    }
    _session = session;
    try {
      await _secure.write(jsonEncode(session.toJson()));
      _kv.remove(KvStore.keyAuthSession);
    } catch (_) {
      // 迁移写入失败：保留明文副本下次启动重试，本次会话照常可用。
    }
  }

  AuthSession? _tryDecodeSession(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return AuthSession.fromJson(decoded);
      }
    } catch (_) {
      // 损坏的会话按未登录处理，由调用方删除对应存储。
    }
    return null;
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
    await _secure.write(jsonEncode(session.toJson()));
    // 任何写入后都不允许明文副本残留（含旧版本升级后的首次登录）。
    _kv.remove(KvStore.keyAuthSession);
  }

  Future<String> _deviceId() async {
    final override = _deviceIdOverride;
    if (override != null && override.isNotEmpty) return override;
    final stored = _kv.getString(KvStore.keyAuthDeviceId);
    if (stored != null && stored.isNotEmpty) return stored;
    final generated = generateUuidV4();
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
  /// F28：公开复用——轮回作答 / 结算的 opId 用同款生成器，不引新依赖。
  static String generateUuidV4() {
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

  String _recoverFallbackMessage(int statusCode) {
    switch (statusCode) {
      case 401:
        // 服务端不区分“手机号不存在”与“恢复码错误”，统一按恢复码无效提示。
        return '恢复码无效，请核对后重试';
      case 422:
        return '手机号或新密码格式不正确';
      default:
        return '找回密码失败（HTTP $statusCode）';
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
