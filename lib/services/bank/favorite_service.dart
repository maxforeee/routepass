/// 收藏服务抽象接口（规格文档第 4 章 §4.4.4）+ F25 HTTP 实现。
///
/// 服务的页面：答题页收藏按钮、收藏页、首页收藏预览卡。
/// [HttpFavoriteService] 接后端 `api/app/api/v1/favorite.py`：
/// - `GET    /api/v1/favorites`：分页 `{items, page, pageSize, total}`，
///   条目 `{questionId, createdAt, question}`；
/// - `POST   /api/v1/favorites`：body `{questionId}`，幂等（重复收藏返回原条目）；
/// - `DELETE /api/v1/favorites/{questionId}`：返回 `{success, questionId}`。
/// 网络失败 / 接口未就绪（非 200）回落 [local]（生产为 MockFavoriteService）。
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config.dart';
import '../../models/practice.dart' show epochMillisFromJson;
import '../../models/wrong_favorite.dart';

abstract class FavoriteService {
  /// 收藏题号列表（答题页判断收藏态用，不含时间戳）。
  Future<List<String>> getFavoriteIds();

  /// 带收藏时间的收藏条目列表（收藏页 / 首页今日预览算日期用）。
  ///
  /// GET /favorites（返回 §4.8.5 的 `favorites` 条目）。
  Future<List<Favorite>> getFavorites();

  /// 切换收藏态：POST /favorites / DELETE /favorites/{qid}。
  /// Mock：本地内存切换。
  Future<void> toggleFavorite(String questionId, bool on);
}

/// 收藏接口的 HTTP 实现；请求失败 / 接口未就绪时兜底委托 [local]。
class HttpFavoriteService implements FavoriteService {
  HttpFavoriteService({
    required this.local,
    http.Client? client,
    String? baseUrl,
    this.tokenProvider,
  }) : _client = client ?? http.Client(),
       _baseUrl = baseUrl ?? AppConfig.baseUrl;

  /// 本地兜底实现（生产为 MockFavoriteService）。
  final FavoriteService local;

  final http.Client _client;
  final String _baseUrl;

  /// 返回 access token 的回调；null 表示当前没有 Token 机制。
  final String? Function()? tokenProvider;

  static const Duration _timeout = Duration(seconds: 10);
  static const int _pageSize = 100;
  static const int _maxPages = 50;

  @override
  Future<List<String>> getFavoriteIds() async {
    final items = await _fetchAll();
    if (items == null) return local.getFavoriteIds();
    return <String>[
      for (final item in items)
        if (item['questionId'] is String) item['questionId'] as String,
    ];
  }

  @override
  Future<List<Favorite>> getFavorites() async {
    final items = await _fetchAll();
    if (items == null) return local.getFavorites();
    return <Favorite>[
      for (final item in items)
        if (item['questionId'] is String)
          Favorite(
            question_id: item['questionId'] as String,
            created_at: epochMillisFromJson(item['createdAt']) ?? 0,
          ),
    ];
  }

  @override
  Future<void> toggleFavorite(String questionId, bool on) async {
    if (questionId.isEmpty) {
      await local.toggleFavorite(questionId, on);
      return;
    }
    final ok = on
        ? await _post('/api/v1/favorites', <String, Object?>{
            'questionId': questionId,
          })
        : await _delete('/api/v1/favorites/${Uri.encodeComponent(questionId)}');
    if (!ok) await local.toggleFavorite(questionId, on);
  }

  /// 逐页拉全收藏列表；任一页失败返回 null，由调用方整体回落本地。
  Future<List<Map<String, dynamic>>?> _fetchAll() async {
    final items = <Map<String, dynamic>>[];
    for (var page = 1; page <= _maxPages; page++) {
      final decoded = await _get(
        '/api/v1/favorites?page=$page&page_size=$_pageSize',
      );
      if (decoded == null) return null;
      final raw = decoded['items'];
      if (raw is! List) return null;
      for (final item in raw) {
        if (item is Map<String, dynamic>) items.add(item);
      }
      final total = (decoded['total'] as num?)?.toInt() ?? items.length;
      if (raw.isEmpty || items.length >= total) break;
    }
    return items;
  }

  Map<String, String> get _headers {
    final token = tokenProvider?.call();
    return <String, String>{
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

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

  Future<bool> _post(String path, Map<String, Object?> body) async {
    try {
      final response = await _client
          .post(
            Uri.parse('$_baseUrl$path'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// DELETE 200 为成功；404 表示本来就没收藏，目标状态已达成，同样算成功。
  Future<bool> _delete(String path) async {
    try {
      final response = await _client
          .delete(Uri.parse('$_baseUrl$path'), headers: _headers)
          .timeout(_timeout);
      return response.statusCode == 200 || response.statusCode == 404;
    } catch (_) {
      return false;
    }
  }
}
