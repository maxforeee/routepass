/// ContentService 的 HTTP 实现（F34：A10 内容清单 + A13 能力/探活）。
///
/// 按真实契约直连后端（跟随 HttpStatsService 模式）：
/// - `GET /api/v1/content/manifest`：内容版本对（后端 camelCase →
///   §4.8 契约 snake_case）；无 active 清单行时后端只返回 `{"pairSeq": 0}`，
///   视为内容未发布，按未就绪回落兜底；
/// - `GET /api/v1/meta/capabilities`：能力声明。后端 features 是 bool map，
///   只取值为 true 的功能键；后端不报 supported_question_types，记空列表，
///   不编造题型；
/// - `GET /api/v1/meta/health`：三层探活（进程 → 数据库 → 内容）。暂无 UI
///   消费方，失败返回 null（未知），绝不把不可达编造成 ok。
///
/// 升级检查（checkUpgrade）后端没有契约字段：`/meta/version` 只返回
/// `{version}`，无 min_supported / compatibility / force（F23 审计确认两侧
/// 都未建），所以恒走 [fallback] 的 Mock 结果（compatibility ok，永不强制
/// 升级），不编造升级判断；splash 的升级检查行为不变。
///
/// 未登录 / 离线 / 接口未就绪时回落 [fallback]（生产为 MockContentService）。
/// Bearer 附加与 401 刷新重放由 main.dart 注入的 [AuthHttpClient] 统一承担。
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config.dart';
import '../../models/content.dart';
import '../base/content_service.dart';

/// `/meta/health` 的探活结果（后端真实形状，非 §4.8 契约模型）。
class MetaHealth {
  const MetaHealth({
    required this.status,
    required this.db,
    this.content,
    this.version,
    this.detail,
  });

  /// `ok` / `degraded`。
  final String status;

  /// `ok` / `down`。
  final String db;

  /// `ready` / `empty`；degraded 时后端不返回该字段。
  final String? content;

  /// 后端服务版本号。
  final String? version;

  /// degraded 时后端给出的异常类名。
  final String? detail;

  factory MetaHealth.fromJson(Map<String, dynamic> json) {
    return MetaHealth(
      status: json['status'] as String? ?? '',
      db: json['db'] as String? ?? '',
      content: json['content'] as String?,
      version: json['version'] as String?,
      detail: json['detail'] as String?,
    );
  }
}

class HttpContentService implements ContentService {
  HttpContentService({
    http.Client? client,
    String? baseUrl,
    this.fallback,
    this.tokenProvider,
  }) : _client = client ?? http.Client(),
       _baseUrl = baseUrl ?? AppConfig.baseUrl;

  final http.Client _client;
  final String _baseUrl;

  /// 接口未就绪 / 请求失败时的本地兜底（不编数据，仍走既有 Mock 行为）。
  final ContentService? fallback;

  /// 返回 access token 的回调；未登录返回 null（不带 Authorization 头）。
  final String? Function()? tokenProvider;

  static const Duration _timeout = Duration(seconds: 10);

  @override
  Future<ContentVersion> getContentVersion() async {
    final data = await _get('/api/v1/content/manifest');
    // 请求失败，或后端无 active 清单行（只回 {"pairSeq": 0}）→ 回落兜底。
    if (data == null || data['bankVersion'] is! String) {
      final local = fallback;
      if (local == null) {
        throw const ContentServiceException('内容版本不可用');
      }
      return local.getContentVersion();
    }
    return ContentVersion(
      pair_seq: (data['pairSeq'] as num?)?.toInt() ?? 0,
      bank_version: data['bankVersion'] as String,
      knowledge_version: data['knowledgeVersion'] as String? ?? '',
      // expectedTotal = 题库题目总数；清单不提供知识点计数，记 0（未知），
      // 绝不拿题目数冒充知识点数。
      bank_count: (data['expectedTotal'] as num?)?.toInt() ?? 0,
      knowledge_count: 0,
      // 端点只返回 active 行（或 since 之后的最新行）。
      status: 'active',
    );
  }

  @override
  Future<UpgradeCheck> checkUpgrade() async {
    // 后端无升级契约字段（见文件头），恒走兜底；无兜底时返回 ok，
    // 永不触发升级（与 Mock 行为一致）。
    final local = fallback;
    if (local == null) {
      return const UpgradeCheck(
        latest: '',
        min_supported: '',
        compatibility: 'ok',
        upgrade_url: '',
        force: false,
      );
    }
    return local.checkUpgrade();
  }

  @override
  Future<Capabilities> getCapabilities() async {
    final data = await _get('/api/v1/meta/capabilities');
    if (data == null) {
      final local = fallback;
      if (local == null) {
        return const Capabilities(
          features: <String>[],
          supported_question_types: <String>[],
        );
      }
      return local.getCapabilities();
    }
    // features 是 bool map：只取服务端明确开启（true）的功能键；
    // groups 是路由分组不是能力，不混入。后端不报 supported_question_types
    // → 空列表，不编造题型。
    final features = data['features'];
    return Capabilities(
      features: <String>[
        if (features is Map<String, dynamic>)
          for (final entry in features.entries)
            if (entry.value == true) entry.key,
      ],
      supported_question_types: const <String>[],
    );
  }

  /// 三层探活（进程 → 数据库 → 内容）。暂无 UI 消费方；请求失败 /
  /// 非 200 / 非 JSON 返回 null（未知），degraded 响应原样解析。
  Future<MetaHealth?> getHealth() async {
    final data = await _get('/api/v1/meta/health');
    if (data == null) return null;
    return MetaHealth.fromJson(data);
  }

  Map<String, String> get _headers {
    final token = tokenProvider?.call();
    return <String, String>{
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  /// 请求：404 / 401 / 网络失败 / 非 JSON 一律返回 null（未就绪），
  /// 由调用方回落兜底，不抛给 UI。
  Future<Map<String, dynamic>?> _get(String path) async {
    try {
      final response = await _client
          .get(Uri.parse('$_baseUrl$path'), headers: _headers)
          .timeout(_timeout);
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}

class ContentServiceException implements Exception {
  const ContentServiceException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'ContentServiceException($message)';
}