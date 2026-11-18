import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:routepass/core/kv_store.dart';
import 'package:routepass/core/service_locator.dart';
import 'package:routepass/core/theme.dart';
import 'package:routepass/services/auth/auth_service.dart';
import 'package:routepass/services/auth/secure_session_store.dart';
import 'package:routepass/services/content/content_service_http.dart';
import 'package:routepass/services/mock/mock_answer_record_service.dart';
import 'package:routepass/services/mock/mock_answer_session_service.dart';
import 'package:routepass/services/mock/mock_auth_service.dart';
import 'package:routepass/services/mock/mock_bank_manifest_service.dart';
import 'package:routepass/services/mock/mock_cli_service.dart';
import 'package:routepass/services/mock/mock_content_service.dart';
import 'package:routepass/services/mock/mock_daily_practice_service.dart';
import 'package:routepass/services/mock/mock_exam_service.dart';
import 'package:routepass/services/mock/mock_favorite_service.dart';
import 'package:routepass/services/mock/mock_knowledge_repository.dart';
import 'package:routepass/services/mock/mock_ping_service.dart';
import 'package:routepass/services/mock/mock_port_scan_service.dart';
import 'package:routepass/services/mock/mock_practice_service.dart';
import 'package:routepass/services/mock/mock_question_repository.dart';
import 'package:routepass/services/mock/mock_search_service.dart';
import 'package:routepass/services/mock/mock_stats_service.dart';
import 'package:routepass/services/mock/mock_sync_service.dart';
import 'package:routepass/services/mock/mock_wrong_service.dart';
import 'package:routepass/services/sync_mode_service.dart';
import 'package:routepass/services/toolbox/ip_convert_service_impl.dart';
import 'package:routepass/services/toolbox/subnet_calc_service_impl.dart';
import 'package:routepass/widgets/account_sheet.dart';

import 'support/fake_connectivity.dart';

/// F34 A10 + A13：内容清单 / 能力声明 / 探活接真实后端契约。
/// - GET /content/manifest：camelCase → §4.8 snake_case 模型；无 active
///   清单行（{"pairSeq": 0}）与请求失败都回落 Mock，不编数字；
/// - GET /meta/capabilities：features 是 bool map，只取 true 键；后端不报
///   supported_question_types → 空列表，不编造题型；
/// - GET /meta/health：ok / degraded 原样解析，失败返回 null（未知）；
/// - checkUpgrade 恒走兜底（后端无升级契约字段），不请求 /meta/version；
/// - 401 刷新一次并重放（AuthHttpClient）；
/// - 账户 sheet「内容版本」行展示真实清单值（A10 显示面）。

const String _base = 'http://example.test';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: const <String, String>{
    'content-type': 'application/json; charset=utf-8',
  },
);

/// 后端 /content/manifest 的真实形状（content.py _manifest）。
Map<String, Object?> _manifestJson({
  int pairSeq = 3,
  String bankVersion = '1.2.0',
  String knowledgeVersion = '1.1.0',
  int expectedTotal = 650,
}) => <String, Object?>{
  'pairSeq': pairSeq,
  'bankVersion': bankVersion,
  'knowledgeVersion': knowledgeVersion,
  'bankChecksum': 'sha256-bank',
  'knowledgeChecksum': 'sha256-knowledge',
  'expectedTotal': expectedTotal,
  'perSetPerModule': 5,
  'perModuleSingle': 100,
  'perModuleMultiple': 30,
};

/// 后端 /meta/capabilities 的真实形状（meta.py：features 为 bool map）。
Map<String, Object?> _capabilitiesJson() => <String, Object?>{
  'version': '1.1.0',
  'groups': <String>['meta', 'auth', 'bank', 'practice', 'exam', 'content'],
  'features': <String, Object?>{
    'examPapers': true,
    'practiceDraw': true,
    'sync': true,
    'ocr': false,
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 账户 sheet 组件测试用：contentService 走真实 HTTP 路径（MockClient
  // 模拟 /content/manifest），其余服务与 initTestServices 一致。
  final syncService = MockSyncService();
  final connectivity = FakeConnectivityService();
  ServiceLocator.init(
    questionRepository: MockQuestionRepository(),
    bankManifestService: MockBankManifestService(),
    answerRecordService: MockAnswerRecordService(),
    answerSessionService: MockAnswerSessionService(),
    practiceService: MockPracticeService(),
    examService: MockExamService(),
    dailyPracticeService: MockDailyPracticeService(),
    wrongService: MockWrongService(),
    favoriteService: MockFavoriteService(),
    statsService: MockStatsService(),
    knowledgeRepository: MockKnowledgeRepository(),
    searchService: MockSearchService(),
    subnetCalcService: LocalSubnetCalcService(),
    ipConvertService: LocalIpConvertService(),
    pingService: MockPingService(),
    portScanService: MockPortScanService(),
    cliService: MockCliService(),
    authService: MockAuthService(),
    syncService: syncService,
    contentService: HttpContentService(
      client: MockClient((request) async {
        if (request.url.path == '/api/v1/content/manifest') {
          return _json(_manifestJson());
        }
        return _json(<String, Object?>{}, 404);
      }),
      baseUrl: _base,
      fallback: MockContentService(),
    ),
    syncModeService: SyncModeService(
      connectivity: connectivity,
      syncService: syncService,
      isLoggedIn: () async =>
          (await ServiceLocator.authService.getCurrentUser()) != null,
    ),
  );

  group('A10 内容清单（GET /content/manifest）', () {
    test('camelCase 清单映射到契约模型；知识点计数后端不提供记 0', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/v1/content/manifest');
        return _json(_manifestJson());
      });
      final service = HttpContentService(client: client, baseUrl: _base);

      final v = await service.getContentVersion();
      expect(v.pair_seq, 3);
      expect(v.bank_version, '1.2.0');
      expect(v.knowledge_version, '1.1.0');
      expect(v.bank_count, 650);
      expect(v.knowledge_count, 0);
      expect(v.status, 'active');
    });

    test('无 active 清单行（{"pairSeq": 0}）→ 按未就绪回落 Mock', () async {
      final client = MockClient((request) async {
        return _json(<String, Object?>{'pairSeq': 0});
      });
      final service = HttpContentService(
        client: client,
        baseUrl: _base,
        fallback: MockContentService(),
      );

      final v = await service.getContentVersion();
      expect(v.pair_seq, 0);
      expect(v.bank_version, '1.0.0');
      expect(v.knowledge_version, '1.0.0');
    });

    test('404 / 500 / 离线 / 非 JSON → 回落 Mock，不抛给 UI', () async {
      final clients = <MockClient>[
        MockClient((request) async => _json(<String, Object?>{}, 404)),
        MockClient((request) async => _json(<String, Object?>{}, 500)),
        MockClient((request) async => throw Exception('offline')),
        MockClient((request) async => http.Response('<html>gw</html>', 200)),
      ];
      for (final client in clients) {
        final service = HttpContentService(
          client: client,
          baseUrl: _base,
          fallback: MockContentService(),
        );
        final v = await service.getContentVersion();
        expect(v.bank_version, '1.0.0');
        expect(v.pair_seq, 0);
      }
    });

    test('登录态带 Bearer 头；未登录（token null）不带 Authorization', () async {
      final headers = <Map<String, String>>[];
      final client = MockClient((request) async {
        headers.add(request.headers);
        return _json(_manifestJson());
      });

      final loggedIn = HttpContentService(
        client: client,
        baseUrl: _base,
        tokenProvider: () => 'tok-123',
      );
      await loggedIn.getContentVersion();
      expect(headers.last['Authorization'], 'Bearer tok-123');

      final loggedOut = HttpContentService(
        client: client,
        baseUrl: _base,
        tokenProvider: () => null,
      );
      await loggedOut.getContentVersion();
      expect(headers.last.containsKey('Authorization'), isFalse);
    });

    test('无兜底时 getContentVersion 抛 typed exception', () async {
      final client = MockClient((request) async {
        return _json(<String, Object?>{}, 500);
      });
      final service = HttpContentService(client: client, baseUrl: _base);

      await expectLater(
        service.getContentVersion(),
        throwsA(isA<ContentServiceException>()),
      );
    });
  });

  group('A13 能力声明（GET /meta/capabilities）', () {
    test('features 只取值为 true 的键；groups 不混入；不编造题型', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/v1/meta/capabilities');
        return _json(_capabilitiesJson());
      });
      final service = HttpContentService(client: client, baseUrl: _base);

      final cap = await service.getCapabilities();
      expect(
        cap.features,
        unorderedEquals(<String>['examPapers', 'practiceDraw', 'sync']),
      );
      expect(cap.features, isNot(contains('ocr')));
      expect(cap.features, isNot(contains('bank')));
      // 后端不报 supported_question_types → 空列表（不拿 Mock 常量冒充）。
      expect(cap.supported_question_types, isEmpty);
    });

    test('失败 → 回落 Mock（features 空、题型 single/multiple）', () async {
      final client = MockClient((request) async {
        return _json(<String, Object?>{'detail': '未登录'}, 401);
      });
      final service = HttpContentService(
        client: client,
        baseUrl: _base,
        fallback: MockContentService(),
      );

      final cap = await service.getCapabilities();
      expect(cap.features, isEmpty);
      expect(cap.supported_question_types, <String>['single', 'multiple']);
    });

    test('无兜底时返回空能力（不抛给 UI）', () async {
      final client = MockClient((request) async {
        throw Exception('offline');
      });
      final service = HttpContentService(client: client, baseUrl: _base);

      final cap = await service.getCapabilities();
      expect(cap.features, isEmpty);
      expect(cap.supported_question_types, isEmpty);
    });
  });

  group('A13 探活（GET /meta/health，暂无 UI 消费方）', () {
    test('ok / ready 原样解析（含后端版本号）', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/v1/meta/health');
        return _json(<String, Object?>{
          'status': 'ok',
          'db': 'ok',
          'content': 'ready',
          'version': '1.1.0',
        });
      });
      final service = HttpContentService(client: client, baseUrl: _base);

      final health = await service.getHealth();
      expect(health, isNotNull);
      expect(health!.status, 'ok');
      expect(health.db, 'ok');
      expect(health.content, 'ready');
      expect(health.version, '1.1.0');
      expect(health.detail, isNull);
    });

    test('degraded 原样解析：db down + 异常类名，content 缺省为 null', () async {
      final client = MockClient((request) async {
        return _json(<String, Object?>{
          'status': 'degraded',
          'db': 'down',
          'detail': 'UndefinedTable',
          'version': '1.1.0',
        });
      });
      final service = HttpContentService(client: client, baseUrl: _base);

      final health = await service.getHealth();
      expect(health!.status, 'degraded');
      expect(health.db, 'down');
      expect(health.content, isNull);
      expect(health.detail, 'UndefinedTable');
    });

    test('请求失败 → null（未知），绝不把不可达编造成 ok', () async {
      final client = MockClient((request) async {
        throw Exception('offline');
      });
      final service = HttpContentService(client: client, baseUrl: _base);

      expect(await service.getHealth(), isNull);
    });
  });

  group('升级检查保持 Mock（后端无 min_supported/compatibility 契约）', () {
    test('checkUpgrade 恒走兜底 ok，且不请求 /meta/version', () async {
      final paths = <String>[];
      final client = MockClient((request) async {
        paths.add(request.url.path);
        return _json(_manifestJson());
      });
      final service = HttpContentService(
        client: client,
        baseUrl: _base,
        fallback: MockContentService(),
      );

      final check = await service.checkUpgrade();
      expect(check.compatibility, 'ok');
      expect(check.force, isFalse);
      expect(paths, isEmpty);
    });

    test('无兜底时仍返回 ok（永不触发升级）', () async {
      final service = HttpContentService(
        client: MockClient((request) async => throw Exception('offline')),
        baseUrl: _base,
      );

      final check = await service.checkUpgrade();
      expect(check.compatibility, 'ok');
      expect(check.force, isFalse);
    });
  });

  group('401 刷新一次并重放（AuthHttpClient + HttpContentService）', () {
    test('manifest 首次 401 → 刷新 token 重放成功，拿到真实清单', () async {
      final kv = InMemoryKvStore();
      final authorization = <String?>[];
      final client = MockClient((request) async {
        final path = request.url.path;
        if (path == '/api/v1/auth/login') {
          return _json(<String, Object?>{
            'accessToken': 'access-1',
            'refreshToken': 'refresh-1',
            'tokenType': 'Bearer',
            'expiresIn': 900,
            'user': <String, Object?>{
              'id': 7,
              'nickname': 'Max',
              'avatarUrl': null,
            },
          });
        }
        if (path == '/api/v1/auth/refresh') {
          return _json(<String, Object?>{
            'accessToken': 'access-2',
            'refreshToken': 'refresh-2',
            'tokenType': 'Bearer',
            'expiresIn': 900,
          });
        }
        if (path == '/api/v1/content/manifest') {
          final header = request.headers['authorization'];
          authorization.add(header);
          if (header == 'Bearer access-1') {
            return _json(<String, Object?>{'detail': '登录会话已失效'}, 401);
          }
          return _json(_manifestJson());
        }
        return _json(<String, Object?>{}, 404);
      });
      final auth = HttpAuthService(
        client: client,
        kvStore: kv,
        secureStore: InMemorySecureSessionStore(),
        baseUrl: _base,
      );
      await auth.login(phone: '13800138000', password: 'secret123');
      final authed = AuthHttpClient(auth: auth, inner: client);
      final service = HttpContentService(
        client: authed,
        baseUrl: _base,
        fallback: MockContentService(),
        tokenProvider: () => auth.cachedAccessToken,
      );

      final v = await service.getContentVersion();
      expect(v.pair_seq, 3);
      expect(v.bank_version, '1.2.0');
      expect(v.bank_count, 650);
      expect(authorization, <String>['Bearer access-1', 'Bearer access-2']);
      expect(auth.cachedAccessToken, 'access-2');
    });
  });

  group('A10 显示面：账户 sheet「内容版本」行', () {
    testWidgets('展示真实清单的题库/知识库版本、题目总数与版本对', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: AccountSheet()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('内容版本'), findsOneWidget);
      expect(find.textContaining('题库 1.2.0'), findsOneWidget);
      expect(find.textContaining('知识库 1.1.0'), findsOneWidget);
      expect(find.textContaining('共 650 题'), findsOneWidget);
      expect(find.textContaining('版本对 3'), findsOneWidget);
    });
  });
}