/// QuestionRepository 的 HTTP 装饰器（F26 chunk 2，F23 A6）。
///
/// 只改 [getModules] 的读路径：`GET /api/v1/bank/modules` 返回
/// `{"modules": [{"module", "questionCount"}]}`（公开接口，无需鉴权；
/// 真实模块名与题量，如 ACL / H3CNE / NAT / OSPF / VLAN / 基础知识 / 子网）。
/// 每行映射为 ModuleStat(module, total = questionCount)；后端不提供
/// 已答数 / 正确率，answered / correctRate 记 0（未知），绝不虚构。
/// 未登录 / 离线 / 接口失败一律回落 [delegate]（生产为 Mock：5 模块全 0），
/// 不抛给 UI。其余方法（抽题 / 单题 / 套卷统计 / 概览）原样委托，不改行为。
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config.dart';
import '../../models/question.dart';
import '../../models/stats.dart';
import 'question_repo.dart';

class HttpQuestionRepository implements QuestionRepository {
  HttpQuestionRepository({
    required this.delegate,
    http.Client? client,
    String? baseUrl,
    this.tokenProvider,
  }) : _client = client ?? http.Client(),
       _baseUrl = baseUrl ?? AppConfig.baseUrl;

  /// getModules 失败 / 未登录时的兜底仓储（其余方法始终委托它）。
  final QuestionRepository delegate;

  final http.Client _client;
  final String _baseUrl;

  /// 返回 access token 的回调；未登录返回 null → 直接走兜底，不发请求。
  /// 生产由 main.dart 注入 `authService.cachedAccessToken`；Bearer 附加与
  /// 401 刷新重放由注入的 [AuthHttpClient] 统一承担（接口本身公开）。
  final String? Function()? tokenProvider;

  static const Duration _timeout = Duration(seconds: 10);

  @override
  Future<List<ModuleStat>> getModules() async {
    final token = tokenProvider?.call();
    if (token == null || token.isEmpty) return delegate.getModules();
    final data = await _get('/api/v1/bank/modules', token);
    if (data == null) return delegate.getModules();
    final items = data['modules'];
    if (items is! List) return delegate.getModules();
    return items
        .whereType<Map<String, dynamic>>()
        .map(_moduleFromJson)
        .toList();
  }

  /// 后端 {module, questionCount} → ModuleStat。answered / correctRate
  /// 后端不提供，记 0（未知），绝不拿题量冒充已答数。
  static ModuleStat _moduleFromJson(Map<String, dynamic> json) {
    return ModuleStat(
      module: json['module'] as String? ?? '',
      total: (json['questionCount'] as num?)?.toInt() ?? 0,
      answered: 0,
      correctRate: 0.0,
    );
  }

  /// 请求：404 / 401 / 网络失败 / 非 JSON 一律返回 null（未就绪），
  /// 由调用方回落兜底，不抛给 UI。
  Future<Map<String, dynamic>?> _get(String path, String token) async {
    try {
      final response = await _client
          .get(
            Uri.parse('$_baseUrl$path'),
            headers: <String, String>{
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(_timeout);
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<Question>> drawQuestions({
    required String mode,
    required int drawCount,
    String? module,
    String? knowledgePointId,
  }) => delegate.drawQuestions(
    mode: mode,
    drawCount: drawCount,
    module: module,
    knowledgePointId: knowledgePointId,
  );

  @override
  Future<Question?> getQuestionById(String id) => delegate.getQuestionById(id);

  @override
  Future<List<ModuleStat>> getSetModuleStats({required String setId}) =>
      delegate.getSetModuleStats(setId: setId);

  @override
  Future<BankSetOverview?> getSetOverview({required String setId}) =>
      delegate.getSetOverview(setId: setId);
}
