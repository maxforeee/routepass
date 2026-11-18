/// F25 Chunk 3：登出清除全部本地账号相关数据。
///
/// 覆盖：
/// - kv：会话（Token + 用户）/ 答题记录 / 目标 / 进行态 / 继续学习指针 /
///   每日一练抽题与作答 / 同步游标、状态、镜像；
/// - SQLite 缓存（BankLocalCache）：概览 / 题库 / 作答 / 会话 id / 待同步队列；
/// - 服务端登出失败（HTTP 500 / 断网抛错）时本地照常清空；
/// - deviceId 决策：登出保留（设备身份，服务端绑定复用），下次登录原样上送；
/// - 设备本地 UI 状态（kb.expandedIds / toolbox.recent / ui.lastTab）不清。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:routepass/core/kv_store.dart';
import 'package:routepass/core/local_db.dart';
import 'package:routepass/core/service_locator.dart';
import 'package:routepass/models/answer_record.dart';
import 'package:routepass/models/answer_session_state.dart';
import 'package:routepass/models/question.dart';
import 'package:routepass/models/stats.dart';
import 'package:routepass/services/auth/auth_service.dart';
import 'package:routepass/services/auth/secure_session_store.dart';
import 'package:routepass/services/bank/answer_record_service.dart';
import 'package:routepass/services/bank/answer_session_service.dart';
import 'package:routepass/services/bank/local_cache_service.dart';
import 'package:routepass/services/mock/mock_auth_service.dart';

const String _phone = '13800138000';
const String _deviceId = '11111111-2222-4333-8444-555555555555';

Question _question(String id) => Question(
  id: id,
  module: 'VLAN',
  type: 'single',
  stem: '登出清理测试用题干，长度超过十个字以满足契约。',
  options: const <QuestionOption>[
    QuestionOption(key: 'A', text: '选项一'),
    QuestionOption(key: 'B', text: '选项二'),
  ],
  answer: const <String>['A'],
  explanation: '',
  knowledge_point_id: 'VLAN-01-01',
  difficulty: 1,
  set_no: 1,
  row_version: 1,
);

AnswerRecord _record() => const AnswerRecord(
  id: 'rec-1-0001',
  setId: 'VLAN',
  setTitle: 'VLAN',
  mode: 'practice',
  kind: 'completion',
  targetCount: 20,
  answeredCount: 20,
  totalCount: 20,
  correctCount: 18,
  durationMs: 60000,
  createdAt: 1,
  updatedAt: 2,
);

AnswerSessionState _session(String mode, String setId) => AnswerSessionState(
  setId: setId,
  setTitle: setId,
  mode: mode,
  targetCount: 20,
  answeredCount: 15,
  correctCount: 10,
  answeredIds: const <String>['VLAN-0001'],
  answers: const <String, List<String>>{
    'VLAN-0001': <String>['A'],
  },
  startedAt: 1,
  updatedAt: 2,
);

http.Response _loginOk() => http.Response(
  jsonEncode(<String, Object?>{
    'accessToken': 'access-1',
    'refreshToken': 'refresh-1',
    'tokenType': 'Bearer',
    'expiresIn': 900,
    'user': <String, Object?>{'id': 'u1', 'nickname': '测试用户'},
  }),
  200,
  // 真实后端回 application/json; charset=utf-8。缺了 content-type 时
  // http.Response 默认按 latin1 编码 body，中文昵称会抛 FormatException，
  // 登录被误判为“响应格式错误”。与 login_test.dart 的 _jsonResponse 一致。
  headers: const <String, String>{
    'content-type': 'application/json; charset=utf-8',
  },
);

/// 只记录 rawExecute 的假数据库：验证 Sqlite 实现的清表语句，不碰 sqflite。
class _RecordingDatabase implements LocalDatabase {
  final List<String> statements = <String>[];

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async => const <Map<String, Object?>>[];

  @override
  Future<void> rawExecute(String sql, [List<Object?>? arguments]) async {
    statements.add(sql);
  }

  @override
  Future<void> close() async {}
}

void main() {
  late InMemoryKvStore kv;
  late InMemorySecureSessionStore secure;
  late InMemoryBankLocalCache cache;

  setUp(() {
    kv = InMemoryKvStore();
    secure = InMemorySecureSessionStore();
    cache = InMemoryBankLocalCache();
    kv.setString(KvStore.keyAuthDeviceId, _deviceId);
  });

  HttpAuthService buildService(http.Client client) => HttpAuthService(
    client: client,
    kvStore: kv,
    secureStore: secure,
    baseUrl: 'http://localhost',
    deviceModelOverride: 'test-device',
    localCache: cache,
  );

  /// 登录 + 铺满全部账号相关本地数据（kv 与 SQLite 缓存）。
  Future<void> seedLoggedIn(HttpAuthService service) async {
    final result = await service.login(phone: _phone, password: 'Demo1234');
    expect(result.success, isTrue);

    kv.setString(
      KvStore.keyAnswerRecords,
      jsonEncode(<Map<String, dynamic>>[_record().toJson()]),
    );
    kv.setString(KvStore.keyAnswerTarget, '35');
    kv.setString(
      KvStore.answerSessionKey('practice', 'VLAN'),
      jsonEncode(_session('practice', 'VLAN').toJson()),
    );
    kv.setString(
      KvStore.answerSessionKey('exam', 'h3cne-2026-01'),
      jsonEncode(_session('exam', 'h3cne-2026-01').toJson()),
    );
    kv.setString(
      KvStore.keyHomeContinue,
      '{"mode":"practice","questionId":"VLAN-0001",'
      '"answeredCount":15,"totalCount":20}',
    );
    kv.setString(
      KvStore.keyDailyAnswer,
      '{"date":"2026-11-15","questionId":"VLAN-0001","selectedKey":"A"}',
    );
    kv.setString(KvStore.keyDailyDrawn, '{"date":"2026-11-15","question":{}}');
    kv.setString(KvStore.keySyncCursor, '42');
    kv.setString(KvStore.keySyncStatus, '{"state":"synced","pendingCount":0}');
    kv.setString(
      KvStore.keySyncMirror,
      '{"wrong_book|VLAN-0001":{"entity":"wrong_book","entityId":"VLAN-0001"}}',
    );
    // 知识点掌握态：用户学习进度，登出必须清除。
    kv.setString(KvStore.keyKbMasteredIds, '["VLAN-01-03"]');

    // 设备本地 UI 状态：不属于账号数据，登出后必须原样保留。
    kv.setString(KvStore.keyKbExpandedIds, '["VLAN-01-03"]');
    kv.setStringList(KvStore.keyToolboxRecent, <String>['subnet', 'ping']);
    kv.setString(KvStore.keyUiLastTab, 'knowledge');
    kv.setString('toolbox.portscanConsent', '1');

    await cache.writeOverview(
      const BankSetOverview(setId: 'VLAN', total: 100, done: 15, remaining: 85),
    );
    await cache.writeQuestions(
      setId: 'VLAN',
      questions: <Question>[_question('VLAN-0001')],
    );
    await cache.recordAttempt(
      setId: 'VLAN',
      questionId: 'VLAN-0001',
      chosen: <String>['A'],
      correct: true,
    );
    await cache.setSessionId('VLAN', 'srv-session-1');
    await cache.enqueueSync(
      const LocalSyncOp(
        opId: 'op-1',
        kind: LocalSyncOp.kindPracticeAnswer,
        payload: <String, Object?>{
          'questionId': 'VLAN-0001',
          'answer': <String>['A'],
        },
        createdAt: 1,
      ),
    );
  }

  Future<void> expectAccountDataCleared() async {
    expect(kv.getString(KvStore.keyAuthSession), isNull);
    // F31：加密存储里的双 Token 同样清空，不留孤儿 Token。
    expect(await secure.read(), isNull);
    expect(kv.getString(KvStore.keyAnswerRecords), isNull);
    expect(kv.getString(KvStore.keyAnswerTarget), isNull);
    expect(kv.getString(KvStore.answerSessionKey('practice', 'VLAN')), isNull);
    expect(
      kv.getString(KvStore.answerSessionKey('exam', 'h3cne-2026-01')),
      isNull,
    );
    expect(kv.getString(KvStore.keyHomeContinue), isNull);
    expect(kv.getString(KvStore.keyDailyAnswer), isNull);
    expect(kv.getString(KvStore.keyDailyDrawn), isNull);
    expect(kv.getString(KvStore.keyKbMasteredIds), isNull);
    expect(kv.getString(KvStore.keySyncCursor), isNull);
    expect(kv.getString(KvStore.keySyncStatus), isNull);
    expect(kv.getString(KvStore.keySyncMirror), isNull);

    expect(await cache.readOverview('VLAN'), isNull);
    expect(await cache.hasQuestions('VLAN'), isFalse);
    expect(await cache.answeredQuestionIds('VLAN'), isEmpty);
    expect(await cache.sessionId('VLAN'), isNull);
    expect(await cache.pendingSync(), isEmpty);
  }

  test('logout clears tokens, user info, records, progress, sync state '
      'and cached questions', () async {
    final logoutRequests = <http.Request>[];
    final service = buildService(
      MockClient((request) async {
        if (request.url.path.endsWith('/auth/login')) return _loginOk();
        if (request.url.path.endsWith('/auth/logout')) {
          logoutRequests.add(request);
          return http.Response('{"success":true}', 200);
        }
        return http.Response('not found', 404);
      }),
    );
    await seedLoggedIn(service);
    expect(await service.getCurrentUser(), isNotNull);
    // F31：会话在加密存储里，明文 kv 不再写入。
    expect(await secure.read(), isNotNull);
    expect(kv.getString(KvStore.keyAuthSession), isNull);

    await service.logout();

    await expectAccountDataCleared();
    expect(await service.getCurrentUser(), isNull);
    expect(service.cachedAccessToken, isNull);
    // 服务端登出调用保留：带 Bearer 发出。
    expect(logoutRequests, hasLength(1));
    expect(logoutRequests.single.headers['Authorization'], 'Bearer access-1');
    // 设备本地 UI 状态不受影响。
    expect(kv.getString(KvStore.keyKbExpandedIds), '["VLAN-01-03"]');
    expect(kv.getStringList(KvStore.keyToolboxRecent), <String>[
      'subnet',
      'ping',
    ]);
    expect(kv.getString(KvStore.keyUiLastTab), 'knowledge');
    expect(kv.getString('toolbox.portscanConsent'), '1');
  });

  test(
    'logout still clears everything when the server call fails (500)',
    () async {
      final service = buildService(
        MockClient((request) async {
          if (request.url.path.endsWith('/auth/login')) return _loginOk();
          return http.Response('server error', 500);
        }),
      );
      await seedLoggedIn(service);

      await service.logout();

      await expectAccountDataCleared();
      expect(await service.getCurrentUser(), isNull);
    },
  );

  test(
    'logout still clears everything when offline (request throws)',
    () async {
      final service = buildService(
        MockClient((request) async {
          if (request.url.path.endsWith('/auth/login')) return _loginOk();
          throw Exception('offline');
        }),
      );
      await seedLoggedIn(service);

      await service.logout();

      await expectAccountDataCleared();
      expect(await service.getCurrentUser(), isNull);
    },
  );

  test('deviceId is kept across logout and reused on the next login', () async {
    final loginBodies = <Map<String, dynamic>>[];
    final service = buildService(
      MockClient((request) async {
        if (request.url.path.endsWith('/auth/login')) {
          loginBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          return _loginOk();
        }
        return http.Response('{"success":true}', 200);
      }),
    );
    await seedLoggedIn(service);
    expect(loginBodies.single['deviceId'], _deviceId);

    await service.logout();

    // 决策：保留。设备身份而非账号数据；服务端绑定登出后仍在，
    // 重新生成会每次登录都占用一个设备名额（账号上限 3 台）。
    expect(kv.getString(KvStore.keyAuthDeviceId), _deviceId);

    final again = await service.login(phone: _phone, password: 'Demo1234');
    expect(again.success, isTrue);
    expect(loginBodies.last['deviceId'], _deviceId);
  });

  test(
    'fresh login after logout reads no stale records, sessions or progress',
    () async {
      final service = buildService(
        MockClient((request) async {
          if (request.url.path.endsWith('/auth/login')) return _loginOk();
          return http.Response('{"success":true}', 200);
        }),
      );
      await seedLoggedIn(service);
      await service.logout();
      final again = await service.login(phone: _phone, password: 'Demo1234');
      expect(again.success, isTrue);

      // 新会话通过真实读路径取数：记录 / 断点 / 进行态 / 缓存全部为空。
      final records = KvAnswerRecordService(kvStore: kv);
      expect(records.recordsFor(setId: 'VLAN', mode: 'practice'), isEmpty);
      expect(records.breakpointOf(setId: 'VLAN', mode: 'practice'), isNull);
      expect(records.pendingSync(), isEmpty);
      final sessions = KvAnswerSessionService(kvStore: kv);
      expect(sessions.load(setId: 'VLAN', mode: 'practice'), isNull);
      expect(sessions.load(setId: 'h3cne-2026-01', mode: 'exam'), isNull);
      expect(await cache.readOverview('VLAN'), isNull);
      expect(await cache.hasQuestions('VLAN'), isFalse);
      expect(kv.getString(KvStore.keyHomeContinue), isNull);
      expect(kv.getString(KvStore.keyDailyDrawn), isNull);
      expect(kv.getString(KvStore.keySyncMirror), isNull);
    },
  );

  test(
    'clearAllAccountData is the single entry and needs no network',
    () async {
      final service = buildService(
        MockClient((request) async {
          if (request.url.path.endsWith('/auth/login')) return _loginOk();
          fail('clearAllAccountData must not call the server');
        }),
      );
      await seedLoggedIn(service);

      await service.clearAllAccountData();

      await expectAccountDataCleared();
      expect(await service.getCurrentUser(), isNull);
    },
  );

  test('SqliteBankLocalCache.clearAll empties every account table', () async {
    final db = _RecordingDatabase();
    final sqliteCache = SqliteBankLocalCache(db);

    await sqliteCache.clearAll();

    for (final table in <String>[
      'set_overview',
      'cached_questions',
      'attempts',
      'sync_queue',
      'set_meta',
    ]) {
      expect(db.statements, contains('DELETE FROM $table'));
    }
  });

  test('MockAuthService.logout clears account kv as well', () async {
    final previousKv = ServiceLocator.kvStore;
    ServiceLocator.kvStore = kv;
    addTearDown(() => ServiceLocator.kvStore = previousKv);

    final service = MockAuthService();
    final result = await service.login(phone: _phone, password: 'Demo1234');
    expect(result.success, isTrue);
    kv.setString(KvStore.keyAuthSession, '{"accessToken":"mock"}');
    kv.setString(
      KvStore.keyAnswerRecords,
      jsonEncode(<Map<String, dynamic>>[_record().toJson()]),
    );
    kv.setString(
      KvStore.answerSessionKey('practice', 'VLAN'),
      jsonEncode(_session('practice', 'VLAN').toJson()),
    );
    kv.setString(KvStore.keySyncCursor, '42');

    await service.logout();

    expect(await service.getCurrentUser(), isNull);
    expect(kv.getString(KvStore.keyAuthSession), isNull);
    expect(kv.getString(KvStore.keyAnswerRecords), isNull);
    expect(kv.getString(KvStore.answerSessionKey('practice', 'VLAN')), isNull);
    expect(kv.getString(KvStore.keySyncCursor), isNull);
    expect(kv.getString(KvStore.keyAuthDeviceId), _deviceId);
  });
}
