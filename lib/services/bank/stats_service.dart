/// 学习统计服务抽象接口（规格文档第 4 章 §4.2 第 6 行、§4.3 H-B11）
/// + F26 HTTP 实现。
///
/// 服务的页面：首页 H-B11、统计页、今日完成摘要。
/// [HttpStatsService] 按真实契约直连后端：
/// - `GET /api/v1/stats/overview`：累计 / 今日 / 按模块（byModule 内嵌）；
/// - `GET /api/v1/stats/daily?page=&pageSize=`：按日历史（新的在前，分页）。
///
/// 后端没有独立的 `/stats/by-module` 接口，[getByModule] 从 overview 的
/// byModule 派生；也没有 streakDays 字段，连续学习天数由 /stats/daily
/// 的日期行在客户端推算（只数 answered > 0 的连续日，锚定今天或昨天）。
/// 未登录 / 离线 / 接口未就绪时回落 [fallback]（Mock 全 0），绝不编数字。
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config.dart';
import '../../models/stats.dart';

abstract class StatsService {
  /// 统计总览。Mock：全 0。真实：GET /stats/overview。
  Future<StatsOverview> getOverview();

  /// 按模块统计。Mock：各模块全 0。真实：从 overview.byModule 派生
  /// （后端无独立接口）。
  Future<List<ModuleStat>> getByModule();

  /// 按日统计。Mock：空列表。真实：GET /stats/daily（翻页取全量）。
  Future<List<DailyStats>> getDaily();
}

/// 学习统计接口的 HTTP 实现（F26，跟随 HttpPracticeService 模式）。
///
/// [fallback] 为未登录 / 离线 / 接口未就绪时的本地兜底（生产为
/// MockStatsService：全 0 / 空列表）。[tokenProvider] 生产由 main.dart 注入
/// `authService.cachedAccessToken`；Bearer 附加与 401 刷新重放由
/// [AuthHttpClient] 统一承担。
class HttpStatsService implements StatsService {
  HttpStatsService({
    http.Client? client,
    String? baseUrl,
    this.fallback,
    this.tokenProvider,
  }) : _client = client ?? http.Client(),
       _baseUrl = baseUrl ?? AppConfig.baseUrl;

  final http.Client _client;
  final String _baseUrl;

  /// 接口未就绪 / 请求失败时的本地兜底（不编数据，仍走既有 Mock 行为）。
  final StatsService? fallback;

  /// 返回 access token 的回调；未登录返回 null（不带 Authorization 头）。
  final String? Function()? tokenProvider;

  static const Duration _timeout = Duration(seconds: 10);

  /// 后端 /stats/daily 的单页上限（MAX_PAGE_SIZE = 100）。
  static const int _dailyPageSize = 100;

  /// getOverview 成功后缓存的 byModule 派生结果；getByModule 直接复用，
  /// 不发额外请求（null = 还没成功拉过 overview）。
  List<ModuleStat>? _byModuleCache;

  @override
  Future<StatsOverview> getOverview() async {
    final data = await _get('/api/v1/stats/overview');
    if (data == null) {
      final local = fallback;
      if (local == null) {
        throw const StatsServiceException('统计总览不可用');
      }
      return local.getOverview();
    }
    final today = data['today'] is Map<String, dynamic>
        ? data['today'] as Map<String, dynamic>
        : const <String, dynamic>{};
    _byModuleCache = _moduleList(data);
    // 连续学习天数：后端不提供，由 /stats/daily 的日期行客户端推算。
    final streak = await _streakDays();
    return StatsOverview(
      answeredTotal: (data['totalAnswered'] as num?)?.toInt() ?? 0,
      correctRate: ((data['accuracy'] as num?)?.toDouble() ?? 0) / 100,
      streakDays: streak,
      todayAnswered: (today['answered'] as num?)?.toInt() ?? 0,
      todayCorrect: (today['correct'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<List<ModuleStat>> getByModule() async {
    final cached = _byModuleCache;
    if (cached != null) return cached;
    // 冷启动（没有先调 getOverview）：拉一次 overview 派生，无独立接口。
    final data = await _get('/api/v1/stats/overview');
    if (data == null) {
      final local = fallback;
      if (local == null) return const <ModuleStat>[];
      return local.getByModule();
    }
    final modules = _moduleList(data);
    _byModuleCache = modules;
    return modules;
  }

  @override
  Future<List<DailyStats>> getDaily() async {
    final rows = <DailyStats>[];
    var page = 1;
    while (true) {
      final data = await _get(
        '/api/v1/stats/daily?page=$page&pageSize=$_dailyPageSize',
      );
      if (data == null) {
        // 第一页就失败：整体回落兜底；翻页中途失败：保留已取到的真实行。
        if (page == 1) {
          final local = fallback;
          if (local == null) return const <DailyStats>[];
          return local.getDaily();
        }
        break;
      }
      final items = _itemList(data);
      rows.addAll(items.map(_dailyFromJson));
      final total = (data['total'] as num?)?.toInt() ?? rows.length;
      if (items.isEmpty || rows.length >= total) break;
      page++;
    }
    return rows;
  }

  /// 连续学习天数：从最新页往回翻，日期链一旦断开（缺口 / 0 答题日 /
  /// 锚点不是今天或昨天）即停，不必翻完全部历史。
  Future<int> _streakDays() async {
    final rows = <DailyStats>[];
    var page = 1;
    while (true) {
      final data = await _get(
        '/api/v1/stats/daily?page=$page&pageSize=$_dailyPageSize',
      );
      if (data == null) break;
      final items = _itemList(data);
      rows.addAll(items.map(_dailyFromJson));
      final result = _streakFromRows(rows, DateTime.now());
      final total = (data['total'] as num?)?.toInt() ?? rows.length;
      if (result.settled || items.isEmpty || rows.length >= total) {
        return result.days;
      }
      page++;
    }
    // 翻页中途网络失败：返回已验证的连续天数（只会少算，不会编造）。
    return _streakFromRows(rows, DateTime.now()).days;
  }

  /// 纯函数：从按日行推算连续学习天数（供测试直接调用）。
  /// 规则：只数 answered > 0 的连续日历日，链尾锚定今天或昨天。
  static int streakDaysFromDaily(List<DailyStats> rows, {DateTime? now}) {
    return _streakFromRows(rows, now ?? DateTime.now()).days;
  }

  /// settled = 已取到的行足以定论（链断 / 锚点不合法 / 无数据），
  /// 不需要再翻下一页；false = 已取行全部连上，下一页可能延长链条。
  static ({int days, bool settled}) _streakFromRows(
    List<DailyStats> rows,
    DateTime now,
  ) {
    final sorted = [...rows]
      ..sort((a, b) => b.stat_date.compareTo(a.stat_date));
    final active = sorted.where((r) => r.answered > 0);
    if (active.isEmpty) return (days: 0, settled: true);
    final newest = DateTime.tryParse(active.first.stat_date);
    if (newest == null) return (days: 0, settled: true);
    final anchor = DateTime(newest.year, newest.month, newest.day);
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    if (anchor != today && anchor != yesterday) {
      return (days: 0, settled: true);
    }
    var expected = anchor;
    var days = 0;
    for (final row in sorted) {
      final parsed = DateTime.tryParse(row.stat_date);
      if (parsed == null) return (days: days, settled: true);
      final day = DateTime(parsed.year, parsed.month, parsed.day);
      // 比锚点新的行（含 0 答题日）与重复日期：跳过。
      if (day.isAfter(expected)) continue;
      // 缺口（缺行）或当日 0 答题：链条到此为止。
      if (day.isBefore(expected) || row.answered <= 0) {
        return (days: days, settled: true);
      }
      days++;
      expected = DateTime(expected.year, expected.month, expected.day - 1);
    }
    return (days: days, settled: false);
  }

  /// overview.byModule → ModuleStat。后端不提供模块题目总数，
  /// total 记 0（未知），绝不拿 answered 冒充 total。
  static List<ModuleStat> _moduleList(Map<String, dynamic> data) {
    return _itemList(data, key: 'byModule').map(_moduleFromJson).toList();
  }

  static ModuleStat _moduleFromJson(Map<String, dynamic> json) {
    return ModuleStat(
      module: json['module'] as String? ?? '',
      total: 0,
      answered: (json['answered'] as num?)?.toInt() ?? 0,
      correctRate: ((json['accuracy'] as num?)?.toDouble() ?? 0) / 100,
    );
  }

  /// 后端 {date, answered, correct, durationSec} → 契约模型
  /// DailyStats（snake_case，§4.8）。
  static DailyStats _dailyFromJson(Map<String, dynamic> json) {
    return DailyStats(
      stat_date: json['date'] as String? ?? '',
      answered: (json['answered'] as num?)?.toInt() ?? 0,
      correct: (json['correct'] as num?)?.toInt() ?? 0,
      duration_sec: (json['durationSec'] as num?)?.toInt() ?? 0,
    );
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

  static List<Map<String, dynamic>> _itemList(
    Map<String, dynamic> data, {
    String key = 'items',
  }) {
    final items = data[key];
    if (items is! List) return const <Map<String, dynamic>>[];
    return items.whereType<Map<String, dynamic>>().toList();
  }
}

class StatsServiceException implements Exception {
  const StatsServiceException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'StatsServiceException($message)';
}
