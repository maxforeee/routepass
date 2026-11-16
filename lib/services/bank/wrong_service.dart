/// 错题本服务抽象接口（规格文档第 4 章 §4.4.4）+ F25 HTTP 实现。
///
/// 服务的页面：首页 H-B6、错题本页、考试评分页「加入错题本」。
/// [HttpWrongService] 接后端 `api/app/api/v1/wrong.py`：
/// - `GET    /api/v1/wrong-book`：分页 `{items, page, pageSize, total}`，
///   条目 `{questionId, wrongCount, lastWrongAt, mastered, question}`；
/// - `POST   /api/v1/wrong-book`：body `{questionId}`，幂等（已存在返回原条目）；
/// - `DELETE /api/v1/wrong-book/{questionId}`：返回 `{success, questionId}`。
/// 服务端没有「已掌握」接口，[WrongService.markMastered] 仍委托本地实现。
/// 网络失败 / 接口未就绪（非 200）回落 [local]（生产为 MockWrongService）。
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config.dart';
import '../../models/practice.dart' show epochMillisFromJson;
import '../../models/wrong_favorite.dart';

abstract class WrongService {
  /// 错题列表。HTTP：GET /wrong-book；Mock：本地内存列表。
  Future<List<WrongItem>> getWrongBook({String? module, bool? masteredOnly});

  /// 用户显式「加入错题本」（F25 考试评分页）。HTTP：POST /wrong-book
  /// body `{questionId}`；已存在时服务端幂等返回原条目。
  Future<void> addWrong(String questionId);

  /// 用户在错题本点“已掌握”。服务端暂无 master 接口，HTTP 实现也委托本地。
  /// 注意：wrong_add（又做错）必须把 mastered 置 false（v3.1 第 8 章，见 §4.8.7）。
  Future<void> markMastered(String questionId);

  /// 用户点“移除”。HTTP：DELETE /wrong-book/{qid}；Mock：本地移除。
  /// 只允许用户显式移除与题库更新失效两种触发（v3.1 第 8 章 wrong_remove 触发条件表）。
  Future<void> removeWrong(String questionId, {String reason = 'user_removed'});

  /// F26 同步物化：把服务端条目按 question_id + last_wrong_at
  /// last-write-wins 并入本地 store，返回实际新增 / 更新的条数。
  /// 服务端独有 → 新增；本地更新 → 保留本地；本地墓碑（removed_at）
  /// 不被更旧的服务端数据复活。默认 no-op（测试 fake 无需实现）。
  Future<int> mergeFromServer(List<WrongItem> items) async => 0;
}

/// 错题本接口的 HTTP 实现；请求失败 / 接口未就绪时兜底委托 [local]。
class HttpWrongService implements WrongService {
  HttpWrongService({
    required this.local,
    http.Client? client,
    String? baseUrl,
    this.tokenProvider,
  }) : _client = client ?? http.Client(),
       _baseUrl = baseUrl ?? AppConfig.baseUrl;

  /// 本地兜底实现（生产为 MockWrongService）。
  final WrongService local;

  final http.Client _client;
  final String _baseUrl;

  /// 返回 access token 的回调；null 表示当前没有 Token 机制。
  final String? Function()? tokenProvider;

  static const Duration _timeout = Duration(seconds: 10);
  static const int _pageSize = 100;
  static const int _maxPages = 50;

  @override
  Future<List<WrongItem>> getWrongBook({
    String? module,
    bool? masteredOnly,
  }) async {
    final items = await _fetchAll();
    if (items == null) {
      return local.getWrongBook(module: module, masteredOnly: masteredOnly);
    }
    final result = <WrongItem>[];
    for (final item in items) {
      final id = item['questionId'];
      if (id is! String || id.isEmpty) continue;
      final question = item['question'];
      final questionModule = question is Map<String, dynamic>
          ? question['module'] as String?
          : null;
      if (module != null && questionModule != module) continue;
      final mastered = item['mastered'] as bool? ?? false;
      if (masteredOnly != null && mastered != masteredOnly) continue;
      result.add(
        WrongItem(
          question_id: id,
          wrong_count: (item['wrongCount'] as num?)?.toInt() ?? 1,
          last_wrong_at: epochMillisFromJson(item['lastWrongAt']) ?? 0,
          mastered: mastered,
        ),
      );
    }
    return result;
  }

  @override
  Future<void> addWrong(String questionId) async {
    if (questionId.isEmpty) return;
    final ok = await _post('/api/v1/wrong-book', <String, Object?>{
      'questionId': questionId,
    });
    if (!ok) await local.addWrong(questionId);
  }

  @override
  Future<void> markMastered(String questionId) =>
      local.markMastered(questionId);

  @override
  Future<void> removeWrong(
    String questionId, {
    String reason = 'user_removed',
  }) async {
    if (questionId.isEmpty) return;
    final ok = await _delete(
      '/api/v1/wrong-book/${Uri.encodeComponent(questionId)}',
    );
    if (!ok) await local.removeWrong(questionId, reason: reason);
  }

  @override
  Future<int> mergeFromServer(List<WrongItem> items) =>
      local.mergeFromServer(items);

  /// 逐页拉全错题列表；任一页失败返回 null，由调用方整体回落本地。
  Future<List<Map<String, dynamic>>?> _fetchAll() async {
    final items = <Map<String, dynamic>>[];
    for (var page = 1; page <= _maxPages; page++) {
      final decoded = await _get(
        '/api/v1/wrong-book?page=$page&page_size=$_pageSize',
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

  /// DELETE 200 为成功；404 表示本来就不在错题本，目标状态已达成，同样算成功。
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
