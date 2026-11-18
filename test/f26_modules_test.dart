import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:routepass/core/kv_store.dart';
import 'package:routepass/core/theme.dart';
import 'package:routepass/models/question.dart';
import 'package:routepass/models/stats.dart';
import 'package:routepass/pages/bank/set_detail_page.dart';
import 'package:routepass/services/auth/auth_service.dart';
import 'package:routepass/services/auth/secure_session_store.dart';
import 'package:routepass/services/bank/question_repo.dart';
import 'package:routepass/services/bank/question_repo_http.dart';
import 'package:routepass/services/mock/mock_question_repository.dart';

import 'test_helpers.dart';

/// F26 模块列表真实契约测试（F23 A6，GET /api/v1/bank/modules）：
/// - 7 个后端模块行 → ModuleStat（模块名原样、total = questionCount）；
/// - 后端不给已答数 / 正确率 → answered / correctRate 恒 0（未知），不虚构；
/// - 失败 / 404 / 401 / 离线 / 非 JSON / 未登录一律回落 Mock（5 模块全 0）；
/// - 抽题 / 单题 / 套卷统计 / 概览路径原样委托，行为不变；
/// - 401 刷新一次并重放（AuthHttpClient）；
/// - 前置页渲染真实模块名与题量（含本地五模块之外的 H3CNE / 基础知识 / 子网）。

const String _base = 'http://example.test';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: const <String, String>{
    'content-type': 'application/json; charset=utf-8',
  },
);

/// 后端契约 fixture：SELECT module, count(*) ... WHERE status='active'
/// GROUP BY module ORDER BY module（ASCII 在前、中文按码位在后）。
/// 数值为测试数据，不代表线上题量；断言只关心「原样映射、不编数字」。
const List<Map<String, Object?>> _backendRows = <Map<String, Object?>>[
  <String, Object?>{'module': 'ACL', 'questionCount': 100},
  <String, Object?>{'module': 'H3CNE', 'questionCount': 100},
  <String, Object?>{'module': 'NAT', 'questionCount': 80},
  <String, Object?>{'module': 'OSPF', 'questionCount': 100},
  <String, Object?>{'module': 'VLAN', 'questionCount': 100},
  <String, Object?>{'module': '基础知识', 'questionCount': 50},
  <String, Object?>{'module': '子网', 'questionCount': 120},
];

Map<String, Object?> _modulesPayload([List<Object?> rows = _backendRows]) =>
    <String, Object?>{'modules': rows};

/// 记录委托调用的替身：证明 getModules 之外的路径原样透传。
class _RecordingRepository implements QuestionRepository {
  final List<String> calls = <String>[];
  String? drawMode;
  int? drawCount;
  String? drawModule;
  String? drawKnowledgePointId;
  String? questionId;
  String? statsSetId;
  String? overviewSetId;

  @override
  Future<List<ModuleStat>> getModules() async {
    calls.add('getModules');
    return const <ModuleStat>[
      ModuleStat(module: 'DELEGATE', total: 7, answered: 1, correctRate: 0.5),
    ];
  }

  @override
  Future<List<Question>> drawQuestions({
    required String mode,
    required int drawCount,
    String? module,
    String? knowledgePointId,
  }) async {
    calls.add('drawQuestions');
    drawMode = mode;
    this.drawCount = drawCount;
    drawModule = module;
    drawKnowledgePointId = knowledgePointId;
    return const <Question>[];
  }

  @override
  Future<Question?> getQuestionById(String id) async {
    calls.add('getQuestionById');
    questionId = id;
    return null;
  }

  @override
  Future<List<ModuleStat>> getSetModuleStats({required String setId}) async {
    calls.add('getSetModuleStats');
    statsSetId = setId;
    return const <ModuleStat>[];
  }

  @override
  Future<BankSetOverview?> getSetOverview({required String setId}) async {
    calls.add('getSetOverview');
    overviewSetId = setId;
    return null;
  }
}

/// Mock 兜底断言：5 个同序模块、题量 / 已答 / 正确率全 0（不编数字）。
Future<void> _expectMockFallback(QuestionRepository repo) async {
  final modules = await repo.getModules();
  expect(modules.map((m) => m.module).toList(), <String>[
    'VLAN',
    'OSPF',
    'ACL',
    'NAT',
    'SUBNET',
  ]);
  expect(
    modules.every(
      (m) => m.total == 0 && m.answered == 0 && m.correctRate == 0.0,
    ),
    isTrue,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initTestServices();

  group('HttpQuestionRepository.getModules（真实契约解析）', () {
    test('7 个后端模块行原样映射：模块名不改、total = questionCount', () async {
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/v1/bank/modules');
        return _json(_modulesPayload());
      });
      final repo = HttpQuestionRepository(
        delegate: MockQuestionRepository(),
        client: client,
        baseUrl: _base,
        tokenProvider: () => 'tok-123',
      );

      final modules = await repo.getModules();
      expect(modules.length, 7);
      expect(modules.map((m) => m.module).toList(), <String>[
        'ACL',
        'H3CNE',
        'NAT',
        'OSPF',
        'VLAN',
        '基础知识',
        '子网',
      ]);
      expect(modules.map((m) => m.total).toList(), <int>[
        100,
        100,
        80,
        100,
        100,
        50,
        120,
      ]);
      // 后端不提供已答数 / 正确率：恒 0（未知），绝不拿题量冒充进度。
      expect(
        modules.every((m) => m.answered == 0 && m.correctRate == 0.0),
        isTrue,
      );
    });

    test('登录态带 Bearer 头；后端返回顺序原样保留（不重新排序）', () async {
      final headers = <Map<String, String>>[];
      final shuffled = <Map<String, Object?>>[
        _backendRows[6],
        _backendRows[0],
        _backendRows[5],
        _backendRows[3],
        _backendRows[1],
        _backendRows[4],
        _backendRows[2],
      ];
      final client = MockClient((request) async {
        headers.add(request.headers);
        return _json(_modulesPayload(shuffled));
      });
      final repo = HttpQuestionRepository(
        delegate: MockQuestionRepository(),
        client: client,
        baseUrl: _base,
        tokenProvider: () => 'tok-123',
      );

      final modules = await repo.getModules();
      expect(headers.single['Authorization'], 'Bearer tok-123');
      expect(
        modules.map((m) => m.module).toList(),
        shuffled.map((r) => r['module']).toList(),
      );
    });

    test('行内多余字段（answered / correctRate / total）一律忽略，不虚构', () async {
      final client = MockClient((request) async {
        return _json(
          _modulesPayload(<Object?>[
            <String, Object?>{
              'module': 'VLAN',
              'questionCount': 100,
              'answered': 999,
              'correctRate': 0.9,
              'total': 1,
            },
          ]),
        );
      });
      final repo = HttpQuestionRepository(
        delegate: MockQuestionRepository(),
        client: client,
        baseUrl: _base,
        tokenProvider: () => 'tok-123',
      );

      final stat = (await repo.getModules()).single;
      expect(stat.module, 'VLAN');
      expect(stat.total, 100);
      expect(stat.answered, 0);
      expect(stat.correctRate, 0.0);
    });

    test('缺字段防御：module 缺失记空串、questionCount 缺失记 0', () async {
      final client = MockClient((request) async {
        return _json(
          _modulesPayload(<Object?>[
            <String, Object?>{'questionCount': 5},
            <String, Object?>{'module': 'NAT'},
          ]),
        );
      });
      final repo = HttpQuestionRepository(
        delegate: MockQuestionRepository(),
        client: client,
        baseUrl: _base,
        tokenProvider: () => 'tok-123',
      );

      final modules = await repo.getModules();
      expect(modules.length, 2);
      expect(modules[0].module, '');
      expect(modules[0].total, 5);
      expect(modules[1].module, 'NAT');
      expect(modules[1].total, 0);
    });

    test('questionCount 为小数按 int 取整；非对象行跳过', () async {
      final client = MockClient((request) async {
        return _json(
          _modulesPayload(<Object?>[
            <String, Object?>{'module': 'VLAN', 'questionCount': 12.0},
            'garbage',
            42,
            null,
          ]),
        );
      });
      final repo = HttpQuestionRepository(
        delegate: MockQuestionRepository(),
        client: client,
        baseUrl: _base,
        tokenProvider: () => 'tok-123',
      );

      final modules = await repo.getModules();
      expect(modules.single.module, 'VLAN');
      expect(modules.single.total, 12);
    });

    test('后端诚实返回空 modules → 空列表（不是 Mock 的 5 模块）', () async {
      final client = MockClient((request) async {
        return _json(_modulesPayload(const <Object?>[]));
      });
      final repo = HttpQuestionRepository(
        delegate: MockQuestionRepository(),
        client: client,
        baseUrl: _base,
        tokenProvider: () => 'tok-123',
      );

      expect(await repo.getModules(), isEmpty);
    });
  });

  group('失败 / 未登录 → 回落 Mock（5 模块全 0，不抛给 UI）', () {
    test('404（接口未上线）回落 Mock', () async {
      final client = MockClient((request) async {
        return _json(<String, Object?>{}, 404);
      });
      final repo = HttpQuestionRepository(
        delegate: MockQuestionRepository(),
        client: client,
        baseUrl: _base,
        tokenProvider: () => 'tok-123',
      );

      await _expectMockFallback(repo);
    });

    test('500（服务端错误）回落 Mock', () async {
      final client = MockClient((request) async {
        return _json(<String, Object?>{'detail': 'boom'}, 500);
      });
      final repo = HttpQuestionRepository(
        delegate: MockQuestionRepository(),
        client: client,
        baseUrl: _base,
        tokenProvider: () => 'tok-123',
      );

      await _expectMockFallback(repo);
    });

    test('401（会话失效，无刷新客户端）回落 Mock', () async {
      final client = MockClient((request) async {
        return _json(<String, Object?>{'detail': '未登录'}, 401);
      });
      final repo = HttpQuestionRepository(
        delegate: MockQuestionRepository(),
        client: client,
        baseUrl: _base,
        tokenProvider: () => 'tok-123',
      );

      await _expectMockFallback(repo);
    });

    test('网络异常（离线）回落 Mock，不抛给 UI', () async {
      final client = MockClient((request) async {
        throw Exception('offline');
      });
      final repo = HttpQuestionRepository(
        delegate: MockQuestionRepository(),
        client: client,
        baseUrl: _base,
        tokenProvider: () => 'tok-123',
      );

      await _expectMockFallback(repo);
    });

    test('200 但非 JSON 响应 → 按未就绪回落 Mock', () async {
      final client = MockClient((request) async {
        return http.Response('<html>gateway</html>', 200);
      });
      final repo = HttpQuestionRepository(
        delegate: MockQuestionRepository(),
        client: client,
        baseUrl: _base,
        tokenProvider: () => 'tok-123',
      );

      await _expectMockFallback(repo);
    });

    test('200 但 modules 缺失 / 不是数组 / 根不是对象 → 回落 Mock', () async {
      final payloads = <Object?>[
        <String, Object?>{},
        <String, Object?>{'modules': 'VLAN'},
        <String, Object?>{
          'modules': <String, Object?>{'VLAN': 100},
        },
        <Object?>[_backendRows.first],
      ];
      for (final payload in payloads) {
        final client = MockClient((request) async {
          return _json(payload!);
        });
        final repo = HttpQuestionRepository(
          delegate: MockQuestionRepository(),
          client: client,
          baseUrl: _base,
          tokenProvider: () => 'tok-123',
        );

        await _expectMockFallback(repo);
      }
    });

    test('未登录（token null / 空串 / 未注入）→ 直接走兜底，不发请求', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return _json(_modulesPayload());
      });

      final nullToken = HttpQuestionRepository(
        delegate: MockQuestionRepository(),
        client: client,
        baseUrl: _base,
        tokenProvider: () => null,
      );
      await _expectMockFallback(nullToken);

      final emptyToken = HttpQuestionRepository(
        delegate: MockQuestionRepository(),
        client: client,
        baseUrl: _base,
        tokenProvider: () => '',
      );
      await _expectMockFallback(emptyToken);

      final noProvider = HttpQuestionRepository(
        delegate: MockQuestionRepository(),
        client: client,
        baseUrl: _base,
      );
      await _expectMockFallback(noProvider);

      expect(calls, 0);
    });

    test('失败时兜底走注入的 delegate（生产为 Mock）', () async {
      final delegate = _RecordingRepository();
      final client = MockClient((request) async {
        return _json(<String, Object?>{}, 500);
      });
      final repo = HttpQuestionRepository(
        delegate: delegate,
        client: client,
        baseUrl: _base,
        tokenProvider: () => 'tok-123',
      );

      final modules = await repo.getModules();
      expect(delegate.calls, <String>['getModules']);
      expect(modules.single.module, 'DELEGATE');
    });
  });

  group('其余路径原样委托（抽题 / 单题 / 套卷统计 / 概览不变）', () {
    test('drawQuestions 参数原样透传（后端模块名作抽题过滤不改名）', () async {
      final delegate = _RecordingRepository();
      final repo = HttpQuestionRepository(
        delegate: delegate,
        client: MockClient((request) async {
          throw StateError('抽题不应发 HTTP 请求');
        }),
        baseUrl: _base,
        tokenProvider: () => 'tok-123',
      );

      await repo.drawQuestions(
        mode: 'practice',
        drawCount: 50,
        module: '子网',
        knowledgePointId: 'kp-1',
      );
      expect(delegate.calls, <String>['drawQuestions']);
      expect(delegate.drawMode, 'practice');
      expect(delegate.drawCount, 50);
      expect(delegate.drawModule, '子网');
      expect(delegate.drawKnowledgePointId, 'kp-1');
    });

    test('getQuestionById / getSetModuleStats / getSetOverview 原样委托', () async {
      final delegate = _RecordingRepository();
      final repo = HttpQuestionRepository(
        delegate: delegate,
        client: MockClient((request) async {
          throw StateError('这些路径不应发 HTTP 请求');
        }),
        baseUrl: _base,
        tokenProvider: () => 'tok-123',
      );

      expect(await repo.getQuestionById('q-9'), isNull);
      expect(delegate.questionId, 'q-9');
      expect(await repo.getSetModuleStats(setId: 'VLAN'), isEmpty);
      expect(delegate.statsSetId, 'VLAN');
      expect(await repo.getSetOverview(setId: 'h3cne-2026-01'), isNull);
      expect(delegate.overviewSetId, 'h3cne-2026-01');
      expect(delegate.calls, <String>[
        'getQuestionById',
        'getSetModuleStats',
        'getSetOverview',
      ]);
    });

    test('getModules 成功后抽题仍走 delegate，HTTP 只打模块接口', () async {
      final paths = <String>[];
      final client = MockClient((request) async {
        paths.add(request.url.path);
        return _json(_modulesPayload());
      });
      final delegate = _RecordingRepository();
      final repo = HttpQuestionRepository(
        delegate: delegate,
        client: client,
        baseUrl: _base,
        tokenProvider: () => 'tok-123',
      );

      expect((await repo.getModules()).length, 7);
      await repo.drawQuestions(mode: 'exam', drawCount: 100);
      expect(paths, <String>['/api/v1/bank/modules']);
      expect(delegate.calls, <String>['drawQuestions']);
    });
  });

  group('401 刷新一次并重放（AuthHttpClient + HttpQuestionRepository）', () {
    test('modules 首次 401 → 刷新 token 重放成功，拿到真实模块', () async {
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
        if (path == '/api/v1/bank/modules') {
          final header = request.headers['authorization'];
          authorization.add(header);
          if (header == 'Bearer access-1') {
            return _json(<String, Object?>{'detail': '登录会话已失效'}, 401);
          }
          return _json(_modulesPayload());
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
      final repo = HttpQuestionRepository(
        delegate: MockQuestionRepository(),
        client: authed,
        baseUrl: _base,
        tokenProvider: () => auth.cachedAccessToken,
      );

      final modules = await repo.getModules();
      expect(modules.length, 7);
      expect(modules.first.module, 'ACL');
      expect(modules.first.total, 100);
      expect(authorization, <String>['Bearer access-1', 'Bearer access-2']);
      expect(auth.cachedAccessToken, 'access-2');
    });
  });

  group('SetDetailPage 渲染（真实模块名 + 真实题量，不虚构进度）', () {
    testWidgets('7 个后端模块原样渲染：题量真实、进度待接口、0% 不出现', (tester) async {
      final client = MockClient((request) async {
        return _json(_modulesPayload());
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: SetDetailPage(
            args: <String, Object?>{
              'mode': 'exam',
              'drawCount': 100,
              'setId': 'h3cne-2026-01',
            },
            questionRepository: HttpQuestionRepository(
              delegate: MockQuestionRepository(),
              client: client,
              baseUrl: _base,
              tokenProvider: () => 'tok-123',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 本地五模块之外的 H3CNE / 基础知识 / 子网 按后端名字原样展示，
      // 不映射成 SUBNET 之类的代码，也不丢弃。
      for (final name in <String>[
        'ACL',
        'H3CNE',
        'NAT',
        'OSPF',
        'VLAN',
        '基础知识',
        '子网',
      ]) {
        expect(find.text(name), findsOneWidget, reason: '模块 $name 应原样展示');
      }
      expect(find.text('子网划分'), findsNothing);
      expect(find.text('SUBNET'), findsNothing);

      // 题量来自 questionCount；answered 恒 0 = 未知 → 进度待接口，不是 0%。
      expect(find.text('100 题 · 进度待接口'), findsNWidgets(4));
      expect(find.text('80 题 · 进度待接口'), findsOneWidget);
      expect(find.text('50 题 · 进度待接口'), findsOneWidget);
      expect(find.text('120 题 · 进度待接口'), findsOneWidget);
      expect(find.textContaining('题量待接口'), findsNothing);
      expect(find.textContaining('%'), findsNothing);

      final progressBars = find.descendant(
        of: find.byType(SetDetailPage),
        matching: find.byType(FractionallySizedBox),
      );
      expect(progressBars, findsNWidgets(7));
      for (final element in progressBars.evaluate()) {
        expect((element.widget as FractionallySizedBox).widthFactor, 0.0);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('离线回落 Mock：5 个本地模块全待接口，不崩溃', (tester) async {
      final client = MockClient((request) async {
        throw Exception('offline');
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: SetDetailPage(
            args: <String, Object?>{
              'mode': 'exam',
              'drawCount': 100,
              'setId': 'h3cne-2026-01',
            },
            questionRepository: HttpQuestionRepository(
              delegate: MockQuestionRepository(),
              client: client,
              baseUrl: _base,
              tokenProvider: () => 'tok-123',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (final name in <String>['VLAN', 'OSPF', 'ACL', 'NAT', '子网划分']) {
        expect(find.text(name), findsOneWidget, reason: '兜底模块 $name 应展示');
      }
      expect(find.text('题量待接口 · 进度待接口'), findsNWidgets(5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('未登录回落 Mock：不发请求，5 个本地模块全待接口', (tester) async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return _json(_modulesPayload());
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: SetDetailPage(
            args: <String, Object?>{
              'mode': 'exam',
              'drawCount': 100,
              'setId': 'h3cne-2026-01',
            },
            questionRepository: HttpQuestionRepository(
              delegate: MockQuestionRepository(),
              client: client,
              baseUrl: _base,
              tokenProvider: () => null,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(calls, 0);
      expect(find.text('题量待接口 · 进度待接口'), findsNWidgets(5));
      expect(tester.takeException(), isNull);
    });
  });
}
