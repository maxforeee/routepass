/// DailyPracticeService 的 HTTP 实现（F17：全库随机抽题，一天一题）。
///
/// 抽题优先走服务端随机端点
/// `GET {baseUrl}/api/v1/bank/practice?count=1&type=single`（F34 B10：
/// 服务端 ORDER BY random() 抽题，type 过滤只抽单选）。该端点任何失败
/// （部署前 404 / 网络错误 / 形状错误 / 空列表 / 非单选 / 脏数据）都回退
/// 旧的两步拒绝采样：公开接口 `GET {baseUrl}/api/v1/bank/questions?page=N`
/// （不带 module 过滤 = 全库）。后端实测（2026-11-13）：limit/pageSize 参数
/// 被忽略，固定 pageSize=20，page 从 1 起，响应带 `{page, pageSize, total}`
/// （total=650）。抽法：先拉第 1 页拿 total → 客户端 `dart:math` Random 抽
/// 一个全库下标 → 换算页码拉那一页 → 命中单选即返回；命中多选/脏数据就重抽
/// （拒绝采样，对全库单选题均匀）。题目内容全部来自后端，两条路径都失败才抛
/// [DailyPracticeException]，不回退 Mock、不本地编题。
///
/// 日期锁：抽中的题连同日期存本地 kv `daily.drawn`
/// （JSON `{date: "yyyy-MM-dd", question: <DailyQuestion JSON>}`）。
/// 同一天再调用直接返回存好的题（不发网络请求）；第二天才重新抽题并覆盖
/// 存储。kv 背后是 shared_preferences（见 main.dart 装配），重启不丢。
///
/// 历史：F23 审计曾预留 `GET /bank/questions/random?count=1`，实际后端复用
/// 已有的 `GET /bank/practice` 并补 `type` 过滤（F34 B10），预留路径不再建。
/// 后端部署前随机端点 404，自动走两步拒绝采样，日期锁与本地存储不变。
library;

import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../../core/config.dart';
import '../../core/kv_store.dart';
import '../../core/service_locator.dart';
import '../../models/daily_question.dart';
import '../../models/question.dart';
import 'daily_practice_service.dart';

/// 每日一练抽题失败（与 BankManifestException 同型的 typed exception）。
class DailyPracticeException implements Exception {
  const DailyPracticeException(this.message);

  final String message;

  @override
  String toString() => 'DailyPracticeException: $message';
}

class HttpDailyPracticeService implements DailyPracticeService {
  HttpDailyPracticeService({
    http.Client? client,
    String? baseUrl,
    KvStore? kvStore,
    Random? random,
  }) : _client = client ?? http.Client(),
       _baseUrl = baseUrl ?? AppConfig.baseUrl,
       _kv = kvStore ?? ServiceLocator.kvStore,
       _random = random ?? Random();

  final http.Client _client;
  final String _baseUrl;
  final KvStore _kv;
  final Random _random;

  static const Duration _timeout = Duration(seconds: 10);

  /// 拒绝采样上限：全库绝大多数是单选，连续 30 次抽不中单选只可能是
  /// 题库异常（如全是多选），此时抛错而不是无限循环。
  static const int _maxDrawAttempts = 30;

  @override
  Future<DailyQuestion> questionForDate(DateTime date) async {
    final day = _formatDate(date);
    final locked = _readDrawn(day);
    if (locked != null) return locked;

    final question = await _drawFromBank();
    _kv.setString(
      KvStore.keyDailyDrawn,
      jsonEncode(<String, Object?>{'date': day, 'question': question.toJson()}),
    );
    return question;
  }

  @override
  Future<String?> answerForDate(DateTime date) async {
    final raw = _kv.getString(KvStore.keyDailyAnswer);
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      if (json['date'] != _formatDate(date)) return null;
      return json['selectedKey'] as String?;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveAnswer({
    required DateTime date,
    required String questionId,
    required String selectedKey,
  }) async {
    final json = <String, Object?>{
      'date': _formatDate(date),
      'questionId': questionId,
      'selectedKey': selectedKey,
    };
    _kv.setString(KvStore.keyDailyAnswer, jsonEncode(json));
  }

  /// 读当天已抽中的题；日期不符或存储损坏都视为未抽（返回 null）。
  DailyQuestion? _readDrawn(String day) {
    final raw = _kv.getString(KvStore.keyDailyDrawn);
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      if (json['date'] != day) return null;
      return DailyQuestion.fromJson(json['question'] as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// 全库随机抽 1 道单选题：优先服务端随机端点（F34 B10），任何失败回退
  /// 两步拒绝采样（见文件头）。两条路径都失败才抛异常，不回退 Mock、不本地编题。
  Future<DailyQuestion> _drawFromBank() async {
    final fromRandom = await _drawFromRandomEndpoint();
    if (fromRandom != null) return fromRandom;
    return _drawBySampling();
  }

  /// 服务端随机抽题：`GET /bank/practice?count=1&type=single`（公开端点，
  /// 与 [_fetchPage] 同一 client/超时）。任何失败（部署前 404 / 网络错误 /
  /// 非 200 / 形状错误 / 空列表 / 非单选 / 脏数据）返回 null，由调用方回退
  /// 拒绝采样——不抛异常。
  Future<DailyQuestion?> _drawFromRandomEndpoint() async {
    final uri = Uri.parse('$_baseUrl/api/v1/bank/practice?count=1&type=single');
    final http.Response response;
    try {
      response = await _client.get(uri).timeout(_timeout);
    } catch (_) {
      return null;
    }
    if (response.statusCode != 200) return null;

    final dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      return null;
    }
    if (decoded is! Map<String, dynamic> || decoded['questions'] is! List) {
      return null;
    }
    for (final item in decoded['questions'] as List<dynamic>) {
      if (item is! Map<String, dynamic> || item['type'] != 'single') continue;
      try {
        final mapped = _mapQuestion(item);
        if (mapped != null) return mapped;
      } catch (_) {
        // 单条脏数据跳过；全部不可用则回退拒绝采样。
        continue;
      }
    }
    return null;
  }

  /// 两步拒绝采样（旧抽法，随机端点不可用时的兜底）：随机下标 → 页码 →
  /// 命中单选即返回。失败抛异常，不回退 Mock、不本地编题。
  Future<DailyQuestion> _drawBySampling() async {
    final first = await _fetchPage(1);
    final total = first.total;
    final pageSize = first.pageSize;
    if (total <= 0 || pageSize <= 0) {
      throw const DailyPracticeException('题库为空');
    }

    for (var attempt = 0; attempt < _maxDrawAttempts; attempt++) {
      final index = _random.nextInt(total);
      final page = index ~/ pageSize + 1;
      final data = page == 1 ? first : await _fetchPage(page);
      final offset = index % pageSize;
      if (offset >= data.questions.length) continue;
      final item = data.questions[offset];
      if (item is! Map<String, dynamic> || item['type'] != 'single') continue;
      try {
        final mapped = _mapQuestion(item);
        if (mapped != null) return mapped;
      } catch (_) {
        // 单条脏数据跳过，重抽下一题。
        continue;
      }
    }
    throw const DailyPracticeException('题库中没有可用的单选题');
  }

  /// 拉全库的第 [page] 页（1 基，固定 pageSize=20），带 total/pageSize 元信息。
  Future<({int total, int pageSize, List<dynamic> questions})> _fetchPage(
    int page,
  ) async {
    final uri = Uri.parse('$_baseUrl/api/v1/bank/questions?page=$page');
    final http.Response response;
    try {
      response = await _client.get(uri).timeout(_timeout);
    } catch (e) {
      throw DailyPracticeException('每日一练抽题请求失败：$e');
    }
    if (response.statusCode != 200) {
      throw DailyPracticeException('每日一练抽题请求失败（HTTP ${response.statusCode}）');
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (e) {
      throw DailyPracticeException('每日一练题目解析失败：$e');
    }
    if (decoded is! Map<String, dynamic> || decoded['questions'] is! List) {
      throw const DailyPracticeException('每日一练题目格式错误');
    }
    return (
      total: (decoded['total'] as num?)?.toInt() ?? 0,
      pageSize: (decoded['pageSize'] as num?)?.toInt() ?? 0,
      questions: decoded['questions'] as List<dynamic>,
    );
  }

  /// 后端题 → [DailyQuestion]：options 纯字符串 → A/B/C/D… key，
  /// answer[0]（0 基下标）→ correctKey。缺选项/答案或下标越界返回 null。
  /// explanation 原样保留（可空，F34 A1）；没有解析的题为 null，不编造。
  DailyQuestion? _mapQuestion(Map<String, dynamic> json) {
    final options = (json['options'] as List<dynamic>).cast<String>();
    final answer = json['answer'] as List<dynamic>;
    if (options.isEmpty || answer.isEmpty) return null;
    final index = (answer.first as num).toInt();
    if (index < 0 || index >= options.length) return null;
    return DailyQuestion(
      id: json['id'] as String,
      stem: json['stem'] as String,
      options: <QuestionOption>[
        for (var i = 0; i < options.length; i++)
          QuestionOption(key: _letter(i), text: options[i]),
      ],
      correctKey: _letter(index),
      explanation: json['explanation'] as String?,
    );
  }

  static String _letter(int index) =>
      String.fromCharCode('A'.codeUnitAt(0) + index);

  /// 本地日期 → `yyyy-MM-dd`（kv 里按日比较，不存时间）。
  static String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}
