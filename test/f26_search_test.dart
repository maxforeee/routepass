import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:routepass/core/kv_store.dart';
import 'package:routepass/core/theme.dart';
import 'package:routepass/models/knowledge_point.dart';
import 'package:routepass/models/question.dart';
import 'package:routepass/models/search.dart';
import 'package:routepass/pages/bank/module_list_page.dart';
import 'package:routepass/services/auth/auth_service.dart';
import 'package:routepass/services/bank/question_bank_source.dart';
import 'package:routepass/services/knowledge/search_service.dart';
import 'package:routepass/services/knowledge/search_service_http.dart';
import 'package:routepass/services/mock/mock_bank_manifest_service.dart';

import 'test_helpers.dart';

/// F26 chunk 5 真实搜索测试（F23 B11）：
/// - HttpSearchService 走 GET /knowledge/search + /bank/questions/search，
///   后端 camelCase 行按契约映射（题目复用 mapBankQuestionJson，知识点
///   contentMd=null → 空串，不编正文）；
/// - 空关键词 / 未登录不发请求；失败按区回落注入的 Mock，不抛给 UI；
/// - 后端诚实返回空列表就是空结果，不拿样例冒充真实命中；
/// - 401 刷新一次并重放（AuthHttpClient）；
/// - 题库页搜索渲染服务端结果（防抖 300ms），不再是本地 3 道样题过滤。

const String _base = 'http://example.test';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: const <String, String>{
    'content-type': 'application/json; charset=utf-8',
  },
);

/// 后端 `_question()` 契约 fixture（camelCase、options 纯字符串、answer
/// 0 基下标）。数值为测试数据，断言只关心「按契约映射、不编字段」。
Map<String, Object?> _backendQuestion({
  String id = 'VLAN-9001',
  String stem = '在交换机上查看 VLAN 摘要信息，应使用哪条命令？',
}) => <String, Object?>{
  'id': id,
  'module': 'VLAN',
  'type': 'single',
  'difficulty': 2,
  'stem': stem,
  'options': <String>[
    'display vlan',
    'display ip routing-table',
    'display acl all',
    'display nat session',
  ],
  'answer': <int>[0],
  'explanation': 'display vlan 用于查看 VLAN 摘要信息。',
  'knowledgePointId': 'KP-VLAN-01-01',
  'relatedKnowledgeIds': <String>[],
  'rowVersion': 3,
};

/// 后端 `_point()` 契约 fixture：占位 KP 的 contentMd / keyPoints /
/// commands 均可为 null（线上仅 6 占位 KP，B13 另补内容）。
Map<String, Object?> _backendPoint() => <String, Object?>{
  'id': 'KP-VLAN-01-01',
  'module': 'VLAN',
  'topic': 'VLAN 基础',
  'code': '1.1',
  'title': 'VLAN 概述',
  'summary': 'VLAN 用于隔离广播域。',
  'contentMd': null,
  'keyPoints': null,
  'commands': null,
  'pitfalls': null,
  'tags': null,
  'orderNo': 1,
  'status': 'active',
  'rowVersion': 2,
};

Map<String, Object?> _questionsPayload(List<Object?> rows) => <String, Object?>{
  'questions': rows,
  'page': 1,
  'pageSize': 20,
  'total': rows.length,
};

Map<String, Object?> _pointsPayload(List<Object?> rows) => <String, Object?>{
  'points': rows,
  'page': 1,
  'pageSize': 20,
  'total': rows.length,
};

/// 兜底替身：记录调用并返回带 MOCK 标记的哨兵结果，证明回落走的是
/// 注入的 fallback（生产为 MockSearchService），且失败不抛给 UI。
class _FakeSearch implements SearchService {
  _FakeSearch({this.result, this.error});

  final List<String> calls = <String>[];
  SearchResult? result;
  Object? error;

  static const Question mockQuestion = Question(
    id: 'MOCK-Q',
    module: 'VLAN',
    type: 'single',
    stem: 'MOCK 样题题干',
    options: <QuestionOption>[QuestionOption(key: 'A', text: 'a')],
    answer: <String>[],
    explanation: '',
    knowledge_point_id: '',
    difficulty: 1,
    set_no: 0,
    row_version: 0,
  );

  static const KnowledgePoint mockPoint = KnowledgePoint(
    id: 'MOCK-KP',
    module: 'VLAN',
    topic: 'VLAN 基础',
    code: '1.1',
    title: 'MOCK 知识点',
    summary: '样例摘要',
    content_md: '',
    row_version: 0,
  );

  @override
  Future<SearchResult> search(String keyword) async {
    calls.add(keyword);
    if (error != null) throw error!;
    return result ??
        const SearchResult(
          knowledgePoints: <KnowledgePoint>[mockPoint],
          questions: <Question>[mockQuestion],
        );
  }
}

HttpSearchService _service({
  required http.Client client,
  required SearchService fallback,
  String? Function()? tokenProvider = _token,
}) => HttpSearchService(
  fallback: fallback,
  client: client,
  baseUrl: _base,
  tokenProvider: tokenProvider,
);

String? _token() => 'tok-123';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initTestServices();

  group('HttpSearchService（真实契约解析）', () {
    test('两端点真实结果：题目 + 知识点按契约映射，带 Bearer 与分页参数', () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/api/v1/knowledge/search') {
          return _json(_pointsPayload(<Object?>[_backendPoint()]));
        }
        if (request.url.path == '/api/v1/bank/questions/search') {
          return _json(_questionsPayload(<Object?>[_backendQuestion()]));
        }
        return _json(<String, Object?>{}, 404);
      });
      final service = _service(client: client, fallback: _FakeSearch());

      final result = await service.search('VLAN');
      expect(requests.length, 2);
      for (final request in requests) {
        expect(request.method, 'GET');
        expect(request.headers['Authorization'], 'Bearer tok-123');
        expect(request.url.queryParameters['q'], 'VLAN');
        expect(request.url.queryParameters['page'], '1');
        expect(request.url.queryParameters['page_size'], '20');
      }

      final question = result.questions.single;
      expect(question.id, 'VLAN-9001');
      expect(question.stem, '在交换机上查看 VLAN 摘要信息，应使用哪条命令？');
      expect(question.options.length, 4);
      expect(question.options.first.key, 'A');
      expect(question.options.first.text, 'display vlan');
      // 后端 0 基下标 answer → 客户端字母 key。
      expect(question.answer, <String>['A']);
      expect(question.knowledge_point_id, 'KP-VLAN-01-01');
      expect(question.row_version, 3);

      final point = result.knowledgePoints.single;
      expect(point.id, 'KP-VLAN-01-01');
      expect(point.title, 'VLAN 概述');
      expect(point.summary, 'VLAN 用于隔离广播域。');
      expect(point.code, '1.1');
      // 占位 KP contentMd=null → 空串（诚实为空，不编正文）。
      expect(point.content_md, '');
      expect(point.row_version, 2);
    });

    test('空关键词 / 纯空白：不发请求，返回空结果', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return _json(_questionsPayload(const <Object?>[]));
      });
      final fallback = _FakeSearch();
      final service = _service(client: client, fallback: fallback);

      for (final keyword in <String>['', '   ', '\t\n']) {
        final result = await service.search(keyword);
        expect(result.knowledgePoints, isEmpty);
        expect(result.questions, isEmpty);
      }
      expect(calls, 0);
      expect(fallback.calls, isEmpty);
    });

    test('关键词 trim 后 URL 编码传输', () async {
      final queries = <String>[];
      final client = MockClient((request) async {
        queries.add(request.url.queryParameters['q'] ?? '');
        return _json(_pointsPayload(const <Object?>[]));
      });
      final service = _service(client: client, fallback: _FakeSearch());

      await service.search('  VLAN 配置  ');
      expect(queries, <String>['VLAN 配置', 'VLAN 配置']);
    });

    test('未登录（token null / 空串 / 未注入）→ 直接走兜底，不发请求', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return _json(_questionsPayload(const <Object?>[]));
      });

      for (final provider in <String? Function()?>[
        () => null,
        () => '',
        null,
      ]) {
        final fallback = _FakeSearch();
        final service = _service(
          client: client,
          fallback: fallback,
          tokenProvider: provider,
        );
        final result = await service.search('VLAN');
        expect(fallback.calls, <String>['VLAN']);
        expect(result.questions.single.id, 'MOCK-Q');
        expect(result.knowledgePoints.single.id, 'MOCK-KP');
      }
      expect(calls, 0);
    });
  });

  group('失败按区回落 Mock（不抛给 UI，不拿样例冒充真实命中）', () {
    test('两端点 404（接口未上线）→ 整体回落注入的 fallback', () async {
      final client = MockClient((request) async {
        return _json(<String, Object?>{}, 404);
      });
      final fallback = _FakeSearch();
      final result = await _service(
        client: client,
        fallback: fallback,
      ).search('VLAN');

      expect(fallback.calls, <String>['VLAN']);
      expect(result.questions.single.id, 'MOCK-Q');
      expect(result.knowledgePoints.single.id, 'MOCK-KP');
    });

    test('知识点 500、题目 200 → 题目保留真实结果，仅知识点区回落', () async {
      final client = MockClient((request) async {
        if (request.url.path == '/api/v1/knowledge/search') {
          return _json(<String, Object?>{'detail': 'boom'}, 500);
        }
        return _json(_questionsPayload(<Object?>[_backendQuestion()]));
      });
      final fallback = _FakeSearch();
      final result = await _service(
        client: client,
        fallback: fallback,
      ).search('VLAN');

      expect(result.questions.single.id, 'VLAN-9001');
      expect(result.knowledgePoints.single.id, 'MOCK-KP');
      expect(fallback.calls, <String>['VLAN']);
    });

    test('题目端网络异常、知识点 200 → 知识点真实，仅题目区回落', () async {
      final client = MockClient((request) async {
        if (request.url.path == '/api/v1/bank/questions/search') {
          throw Exception('offline');
        }
        return _json(_pointsPayload(<Object?>[_backendPoint()]));
      });
      final fallback = _FakeSearch();
      final result = await _service(
        client: client,
        fallback: fallback,
      ).search('VLAN');

      expect(result.knowledgePoints.single.id, 'KP-VLAN-01-01');
      expect(result.questions.single.id, 'MOCK-Q');
    });

    test('401（无刷新客户端）/ 200 非 JSON → 回落，不抛给 UI', () async {
      final unauthorized = MockClient((request) async {
        return _json(<String, Object?>{'detail': '未登录'}, 401);
      });
      final fallback1 = _FakeSearch();
      final r1 = await _service(
        client: unauthorized,
        fallback: fallback1,
      ).search('VLAN');
      expect(r1.questions.single.id, 'MOCK-Q');
      expect(fallback1.calls, <String>['VLAN']);

      final notJson = MockClient((request) async {
        return http.Response('<html>gateway</html>', 200);
      });
      final fallback2 = _FakeSearch();
      final r2 = await _service(
        client: notJson,
        fallback: fallback2,
      ).search('VLAN');
      expect(r2.knowledgePoints.single.id, 'MOCK-KP');
      expect(r2.questions.single.id, 'MOCK-Q');
    });

    test('200 但 points / questions 缺失或不是数组 → 该区回落', () async {
      final client = MockClient((request) async {
        if (request.url.path == '/api/v1/knowledge/search') {
          return _json(<String, Object?>{'points': 'VLAN'});
        }
        return _json(<String, Object?>{'total': 0});
      });
      final fallback = _FakeSearch();
      final result = await _service(
        client: client,
        fallback: fallback,
      ).search('VLAN');

      expect(result.knowledgePoints.single.id, 'MOCK-KP');
      expect(result.questions.single.id, 'MOCK-Q');
    });

    test('后端诚实返回空列表 → 空结果，绝不回落样例数据', () async {
      final client = MockClient((request) async {
        if (request.url.path == '/api/v1/knowledge/search') {
          return _json(_pointsPayload(const <Object?>[]));
        }
        return _json(_questionsPayload(const <Object?>[]));
      });
      final fallback = _FakeSearch();
      final result = await _service(
        client: client,
        fallback: fallback,
      ).search('不存在的关键词');

      expect(result.knowledgePoints, isEmpty);
      expect(result.questions, isEmpty);
      expect(fallback.calls, isEmpty);
    });
  });

  group('401 刷新一次并重放（AuthHttpClient + HttpSearchService）', () {
    test('搜索首次 401 → 刷新 token 重放成功，拿到真实结果', () async {
      final kv = InMemoryKvStore();
      final knowledgeAuth = <String?>[];
      final bankAuth = <String?>[];
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
        if (path == '/api/v1/knowledge/search') {
          final header = request.headers['authorization'];
          knowledgeAuth.add(header);
          if (header == 'Bearer access-1') {
            return _json(<String, Object?>{'detail': '登录会话已失效'}, 401);
          }
          return _json(_pointsPayload(<Object?>[_backendPoint()]));
        }
        if (path == '/api/v1/bank/questions/search') {
          final header = request.headers['authorization'];
          bankAuth.add(header);
          if (header == 'Bearer access-1') {
            return _json(<String, Object?>{'detail': '登录会话已失效'}, 401);
          }
          return _json(_questionsPayload(<Object?>[_backendQuestion()]));
        }
        return _json(<String, Object?>{}, 404);
      });
      final auth = HttpAuthService(client: client, kvStore: kv, baseUrl: _base);
      await auth.login(phone: '13800138000', password: 'secret123');
      final authed = AuthHttpClient(auth: auth, inner: client);
      final fallback = _FakeSearch();
      final service = HttpSearchService(
        fallback: fallback,
        client: authed,
        baseUrl: _base,
        tokenProvider: () => auth.cachedAccessToken,
      );

      final result = await service.search('VLAN');
      expect(result.knowledgePoints.single.id, 'KP-VLAN-01-01');
      expect(result.questions.single.id, 'VLAN-9001');
      expect(knowledgeAuth, <String>['Bearer access-1', 'Bearer access-2']);
      expect(bankAuth.last, 'Bearer access-2');
      expect(auth.cachedAccessToken, 'access-2');
      expect(fallback.calls, isEmpty);
    });
  });

  group('BankModuleListPage 真实搜索（防抖 300ms，不本地过滤样题）', () {
    /// 服务端结果：用后端契约 fixture 经既有映射生成，题干与本地样题无关。
    final serverQuestion = mapBankQuestionJson(
      _backendQuestion(id: 'OSPF-9001', stem: '服务端真实题干：OSPF 邻居无法建立时应先检查什么？'),
    )!;

    Widget host(_FakeSearch search) => MaterialApp(
      theme: AppTheme.light,
      home: BankModuleListPage(
        manifestService: MockBankManifestService(),
        searchService: search,
      ),
    );

    final Finder searchField = find.descendant(
      of: find.byType(BankModuleListPage),
      matching: find.byType(TextField),
    );

    testWidgets('默认展示套卷列表，不发搜索请求', (tester) async {
      final search = _FakeSearch();
      await tester.pumpWidget(host(search));
      await tester.pumpAndSettle();

      expect(search.calls, isEmpty);
      expect(find.text('练习'), findsOneWidget);
      expect(find.text('考试'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('输入关键词 → 渲染服务端结果，不是本地样题', (tester) async {
      final search = _FakeSearch(
        result: SearchResult(
          knowledgePoints: const <KnowledgePoint>[],
          questions: <Question>[serverQuestion],
        ),
      );
      await tester.pumpWidget(host(search));
      await tester.pumpAndSettle();

      await tester.enterText(searchField, 'OSPF');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(search.calls, <String>['OSPF']);
      expect(find.text(serverQuestion.stem), findsOneWidget);
      expect(find.text('MOCK 样题题干'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('防抖：300ms 内连续输入只查最后一个关键词', (tester) async {
      final search = _FakeSearch(
        result: SearchResult(
          knowledgePoints: const <KnowledgePoint>[],
          questions: <Question>[serverQuestion],
        ),
      );
      await tester.pumpWidget(host(search));
      await tester.pumpAndSettle();

      await tester.enterText(searchField, 'O');
      await tester.pump(const Duration(milliseconds: 100));
      expect(search.calls, isEmpty);

      await tester.enterText(searchField, 'OSPF');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(search.calls, <String>['OSPF']);
      expect(find.text(serverQuestion.stem), findsOneWidget);
    });

    testWidgets('无匹配 → 诚实空态「没有找到相关题目」', (tester) async {
      final search = _FakeSearch(
        result: const SearchResult(
          knowledgePoints: <KnowledgePoint>[],
          questions: <Question>[],
        ),
      );
      await tester.pumpWidget(host(search));
      await tester.pumpAndSettle();

      await tester.enterText(searchField, '不存在的关键词');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('没有找到相关题目'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('清空关键词 → 恢复套卷列表，不发新请求', (tester) async {
      final search = _FakeSearch(
        result: SearchResult(
          knowledgePoints: const <KnowledgePoint>[],
          questions: <Question>[serverQuestion],
        ),
      );
      await tester.pumpWidget(host(search));
      await tester.pumpAndSettle();

      await tester.enterText(searchField, 'OSPF');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(search.calls, <String>['OSPF']);

      await tester.enterText(searchField, '');
      await tester.pump();
      await tester.pumpAndSettle();

      expect(search.calls, <String>['OSPF']);
      expect(find.text('练习'), findsOneWidget);
      expect(find.text(serverQuestion.stem), findsNothing);
    });

    testWidgets('搜索服务抛错 → 诚实空态，不崩溃', (tester) async {
      final search = _FakeSearch(error: Exception('search exploded'));
      await tester.pumpWidget(host(search));
      await tester.pumpAndSettle();

      await tester.enterText(searchField, 'OSPF');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('没有找到相关题目'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
