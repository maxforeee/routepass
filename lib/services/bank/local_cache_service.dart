/// 本地缓存服务（F19 cache-first / offline-first）。
///
/// 读路径优先本地 SQLite，未命中才走服务端；写路径先落本地，再进入
/// `sync_queue` 等待上传（后端 `POST /practice/records` /
/// `POST /practice/submit` 就绪后由同步层 flush）。
///
/// 两张核心表：
/// - `set_overview`：前置页已答 / 剩余 / 题型分布缓存（GET /bank/sets/{id}/overview）。
/// - `cached_questions` / `attempts`：练习抽题的本地题库与已答集合，
///   抽题时优先本地命中并排除已答（GET /practice/next 不可用或断网时兜底）。
///
/// 接口刻意保持窄小，测试用 [InMemoryBankLocalCache]（无网络、无 SQLite）。
library;

import 'dart:convert';

import '../../core/local_db.dart';
import '../../models/question.dart';
import '../../models/stats.dart';

/// 待同步操作（本地先写，联网后上传）。
class LocalSyncOp {
  const LocalSyncOp({
    required this.opId,
    required this.kind,
    required this.payload,
    required this.createdAt,
  });

  /// 练习作答：`POST /practice/submit` 的幂等键同 op_id。
  static const String kindPracticeAnswer = 'practice_answer';

  final String opId;
  final String kind;
  final Map<String, Object?> payload;
  final int createdAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'opId': opId,
    'kind': kind,
    'payload': payload,
    'createdAt': createdAt,
  };

  factory LocalSyncOp.fromJson(Map<String, dynamic> json) {
    return LocalSyncOp(
      opId: json['opId'] as String,
      kind: json['kind'] as String,
      payload: (json['payload'] as Map<String, dynamic>?) ?? const {},
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 本地缓存抽象：生产为 SQLite，测试为内存实现。
abstract class BankLocalCache {
  Future<BankSetOverview?> readOverview(String setId);

  Future<void> writeOverview(BankSetOverview overview);

  /// 本地题库里取一道未答过的题；取不到返回 null（由调用方回退服务端）。
  Future<Question?> nextQuestion({
    required String setId,
    String? module,
    required Set<String> excludedIds,
  });

  Future<void> writeQuestions({
    required String setId,
    required List<Question> questions,
  });

  Future<bool> hasQuestions(String setId);

  Future<Set<String>> answeredQuestionIds(String setId);

  Future<void> recordAttempt({
    required String setId,
    required String questionId,
    required List<String> chosen,
    bool? correct,
  });

  Future<String?> sessionId(String setId);

  Future<void> setSessionId(String setId, String sessionId);

  Future<void> enqueueSync(LocalSyncOp op);

  Future<List<LocalSyncOp>> pendingSync({int limit = 50});

  Future<void> markSyncOpSynced(String opId);
}

/// 内存实现：测试 / 无 SQLite 平台的降级实现。
class InMemoryBankLocalCache implements BankLocalCache {
  final Map<String, BankSetOverview> _overviews = <String, BankSetOverview>{};
  final Map<String, Map<String, Question>> _questions =
      <String, Map<String, Question>>{};
  final Map<String, Set<String>> _answered = <String, Set<String>>{};
  final Map<String, _Attempt> _attempts = <String, _Attempt>{};
  final Map<String, String> _sessions = <String, String>{};
  final Map<String, LocalSyncOp> _queue = <String, LocalSyncOp>{};

  @override
  Future<BankSetOverview?> readOverview(String setId) async =>
      _overviews[setId];

  @override
  Future<void> writeOverview(BankSetOverview overview) async {
    _overviews[overview.setId] = overview;
  }

  @override
  Future<Question?> nextQuestion({
    required String setId,
    String? module,
    required Set<String> excludedIds,
  }) async {
    final questions = _questions[setId];
    if (questions == null) return null;
    for (final question in questions.values) {
      if (excludedIds.contains(question.id)) continue;
      if (module != null && question.module != module) continue;
      return question;
    }
    return null;
  }

  @override
  Future<void> writeQuestions({
    required String setId,
    required List<Question> questions,
  }) async {
    final bucket = _questions.putIfAbsent(setId, () => <String, Question>{});
    for (final question in questions) {
      bucket.putIfAbsent(question.id, () => question);
    }
  }

  @override
  Future<bool> hasQuestions(String setId) async =>
      (_questions[setId]?.isNotEmpty ?? false);

  @override
  Future<Set<String>> answeredQuestionIds(String setId) async =>
      Set<String>.unmodifiable(_answered[setId] ?? const <String>{});

  @override
  Future<void> recordAttempt({
    required String setId,
    required String questionId,
    required List<String> chosen,
    bool? correct,
  }) async {
    _answered.putIfAbsent(setId, () => <String>{}).add(questionId);
    _attempts['$setId::$questionId'] = _Attempt(
      chosen: List<String>.of(chosen),
      correct: correct,
    );
  }

  @override
  Future<String?> sessionId(String setId) async => _sessions[setId];

  @override
  Future<void> setSessionId(String setId, String sessionId) async {
    _sessions[setId] = sessionId;
  }

  /// 测试辅助：读取内存里的作答（chosen / correct），未作答返回 null。
  ({List<String> chosen, bool? correct})? attemptFor(
    String setId,
    String questionId,
  ) {
    final attempt = _attempts['$setId::$questionId'];
    if (attempt == null) return null;
    return (
      chosen: List<String>.unmodifiable(attempt.chosen),
      correct: attempt.correct,
    );
  }

  @override
  Future<void> enqueueSync(LocalSyncOp op) async {
    _queue.putIfAbsent(op.opId, () => op);
  }

  @override
  Future<List<LocalSyncOp>> pendingSync({int limit = 50}) async {
    return _queue.values.take(limit).toList();
  }

  @override
  Future<void> markSyncOpSynced(String opId) async {
    _queue.remove(opId);
  }
}

class _Attempt {
  _Attempt({required this.chosen, required this.correct});

  final List<String> chosen;
  final bool? correct;
}

/// SQLite 实现：所有字段以 JSON / 标量落本地，读路径一次查询。
class SqliteBankLocalCache implements BankLocalCache {
  SqliteBankLocalCache(this._db);

  final LocalDatabase _db;

  @override
  Future<BankSetOverview?> readOverview(String setId) async {
    final rows = await _db.rawQuery(
      'SELECT total, done, remaining, single_count, multiple_count '
      'FROM set_overview WHERE set_id = ?',
      <Object?>[setId],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    final single = (row['single_count'] as num?)?.toInt();
    final multiple = (row['multiple_count'] as num?)?.toInt();
    // -1 表示“服务端未提供题型分布”（S11 /practice/progress 没有该字段），
    // 读回 null，前置页显示“题型待接口”；0/0 才是真实的空分布。
    final hasByType =
        single != null && multiple != null && single >= 0 && multiple >= 0;
    return BankSetOverview(
      setId: setId,
      total: (row['total'] as num?)?.toInt() ?? 0,
      done: (row['done'] as num?)?.toInt() ?? 0,
      remaining: (row['remaining'] as num?)?.toInt() ?? 0,
      byType: hasByType
          ? QuestionTypeStat(setId: setId, single: single, multiple: multiple)
          : null,
    );
  }

  @override
  Future<void> writeOverview(BankSetOverview overview) async {
    await _db.rawExecute(
      'INSERT OR REPLACE INTO set_overview '
      '(set_id, total, done, remaining, single_count, multiple_count, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?)',
      <Object?>[
        overview.setId,
        overview.total,
        overview.done,
        overview.remaining,
        // 题型分布未知时写 -1（列是 NOT NULL，且计数不会为负）。
        overview.byType?.single ?? -1,
        overview.byType?.multiple ?? -1,
        DateTime.now().millisecondsSinceEpoch,
      ],
    );
  }

  @override
  Future<Question?> nextQuestion({
    required String setId,
    String? module,
    required Set<String> excludedIds,
  }) async {
    final where = <String>['set_id = ?'];
    final args = <Object?>[setId];
    if (module != null) {
      where.add('module = ?');
      args.add(module);
    }
    if (excludedIds.isNotEmpty) {
      final placeholders = List<String>.filled(
        excludedIds.length,
        '?',
      ).join(', ');
      where.add('question_id NOT IN ($placeholders)');
      args.addAll(excludedIds);
    }
    final rows = await _db.rawQuery(
      'SELECT payload FROM cached_questions WHERE ${where.join(' AND ')} '
      'ORDER BY rowid ASC LIMIT 1',
      args,
    );
    if (rows.isEmpty) return null;
    return _decodeQuestion(rows.first['payload'] as String?);
  }

  @override
  Future<void> writeQuestions({
    required String setId,
    required List<Question> questions,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final question in questions) {
      await _db.rawExecute(
        'INSERT OR REPLACE INTO cached_questions '
        '(set_id, question_id, module, payload, updated_at) '
        'VALUES (?, ?, ?, ?, ?)',
        <Object?>[
          setId,
          question.id,
          question.module,
          jsonEncode(question.toJson()),
          now,
        ],
      );
    }
  }

  @override
  Future<bool> hasQuestions(String setId) async {
    final rows = await _db.rawQuery(
      'SELECT 1 FROM cached_questions WHERE set_id = ? LIMIT 1',
      <Object?>[setId],
    );
    return rows.isNotEmpty;
  }

  @override
  Future<Set<String>> answeredQuestionIds(String setId) async {
    final rows = await _db.rawQuery(
      'SELECT question_id FROM attempts WHERE set_id = ?',
      <Object?>[setId],
    );
    return rows
        .map((row) => row['question_id'] as String?)
        .whereType<String>()
        .toSet();
  }

  @override
  Future<void> recordAttempt({
    required String setId,
    required String questionId,
    required List<String> chosen,
    bool? correct,
  }) async {
    await _db.rawExecute(
      'INSERT OR REPLACE INTO attempts '
      '(set_id, question_id, chosen, correct, updated_at) '
      'VALUES (?, ?, ?, ?, ?)',
      <Object?>[
        setId,
        questionId,
        jsonEncode(chosen),
        correct == null ? null : (correct ? 1 : 0),
        DateTime.now().millisecondsSinceEpoch,
      ],
    );
  }

  @override
  Future<String?> sessionId(String setId) async {
    final rows = await _db.rawQuery(
      'SELECT session_id FROM set_meta WHERE set_id = ?',
      <Object?>[setId],
    );
    if (rows.isEmpty) return null;
    final value = rows.first['session_id'] as String?;
    return value == null || value.isEmpty ? null : value;
  }

  @override
  Future<void> setSessionId(String setId, String sessionId) async {
    await _db.rawExecute(
      'INSERT INTO set_meta (set_id, session_id) VALUES (?, ?) '
      'ON CONFLICT(set_id) DO UPDATE SET session_id = excluded.session_id',
      <Object?>[setId, sessionId],
    );
  }

  @override
  Future<void> enqueueSync(LocalSyncOp op) async {
    await _db.rawExecute(
      'INSERT OR IGNORE INTO sync_queue '
      '(op_id, kind, payload, created_at, synced) VALUES (?, ?, ?, ?, 0)',
      <Object?>[op.opId, op.kind, jsonEncode(op.payload), op.createdAt],
    );
  }

  @override
  Future<List<LocalSyncOp>> pendingSync({int limit = 50}) async {
    final rows = await _db.rawQuery(
      'SELECT op_id, kind, payload, created_at FROM sync_queue '
      'WHERE synced = 0 ORDER BY created_at ASC LIMIT ?',
      <Object?>[limit],
    );
    final ops = <LocalSyncOp>[];
    for (final row in rows) {
      final payload = _decodeMap(row['payload'] as String?);
      if (payload == null) continue;
      ops.add(
        LocalSyncOp(
          opId: row['op_id'] as String,
          kind: row['kind'] as String,
          payload: payload,
          createdAt: (row['created_at'] as num?)?.toInt() ?? 0,
        ),
      );
    }
    return ops;
  }

  @override
  Future<void> markSyncOpSynced(String opId) async {
    await _db.rawExecute(
      'UPDATE sync_queue SET synced = 1, synced_at = ? WHERE op_id = ?',
      <Object?>[DateTime.now().millisecondsSinceEpoch, opId],
    );
  }

  Question? _decodeQuestion(String? payload) {
    final map = _decodeMap(payload);
    if (map == null) return null;
    try {
      return Question.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? _decodeMap(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return decoded;
    } catch (_) {
      return null;
    }
  }
}
