/// F26 chunk 8（F23 A5/B13）：知识库 HTTP 仓储 + 答题页知识点 chip。
///
/// 覆盖：
/// - camelCase → snake_case 归一（contentMd/keyPoints/rowVersion），
///   commands 为 null 时给空数组（解析器不接受 null）；
/// - 章/节由真实 VLAN KP 的 code 前缀聚合（模块→章，topic→节），
///   占位 KP（contentMd null）不进浏览结构；分页全量拉取；
/// - 未登录 / 500 / 非 JSON / 404 一律回落注入的 Mock，不抛给 UI；
/// - getPointsByQuestion 只在 KP 有正式内容时返回，否则 []；
/// - 答题页判分后 chip 只随真实内容出现，点按走知识库同一命名路由。
library;

import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:routepass/core/kv_store.dart';
import 'package:routepass/core/theme.dart';
import 'package:routepass/models/knowledge_point.dart';
import 'package:routepass/models/practice.dart';
import 'package:routepass/models/question.dart';
import 'package:routepass/pages/bank/quiz_page.dart';
import 'package:routepass/router/app_router.dart';
import 'package:routepass/services/bank/answer_record_service.dart';
import 'package:routepass/services/bank/answer_session_service.dart';
import 'package:routepass/services/bank/practice_service.dart';
import 'package:routepass/services/knowledge/knowledge_repo.dart';
import 'package:routepass/services/knowledge/knowledge_repo_http.dart';
import 'package:routepass/services/mock/mock_favorite_service.dart';

const String _base = 'http://test.local';

/// 后端 `_point()` 的 camelCase 形状（knowledge.py）。
Map<String, dynamic> _backendPoint({
  String id = 'KP-VLAN-04',
  String module = 'VLAN',
  String code = '1.3',
  String topic = '端口类型',
  String title = 'Trunk 端口收发规则',
  String? contentMd = '## 概念\nTrunk 端口允许多个 VLAN 通过。',
  List<dynamic>? commands = const <dynamic>[],
  int orderNo = 4,
  int rowVersion = 3,
}) {
  return <String, dynamic>{
    'id': id,
    'module': module,
    'topic': topic,
    'code': code,
    'title': title,
    'summary': '摘要',
    'contentMd': contentMd,
    'keyPoints': <String>['要点一'],
    'commands': commands,
    'pitfalls': <String>['易错一'],
    'tags': <String>['Trunk'],
    'orderNo': orderNo,
    'status': 'active',
    'rowVersion': rowVersion,
  };
}

/// 本批真实的 12 个 VLAN KP（code 按 topic 聚合）+ 1 个 OSPF 占位。
List<Map<String, dynamic>> _vlanBank() {
  const specs = <(String, String, String, String)>[
    ('KP-VLAN-01', '1.1', 'VLAN 基础', 'VLAN 基础与广播域'),
    ('KP-VLAN-02', '1.2', '802.1Q', '802.1Q 帧格式'),
    ('KP-VLAN-03', '1.3', '端口类型', 'Access 端口收发规则'),
    ('KP-VLAN-04', '1.3', '端口类型', 'Trunk 端口收发规则'),
    ('KP-VLAN-05', '1.3', '端口类型', 'Hybrid 端口收发规则'),
    ('KP-VLAN-06', '1.4', 'VLAN 管理', 'VLAN 创建与管理'),
    ('KP-VLAN-07', '1.5', 'VLAN 划分', 'VLAN 划分方式'),
    ('KP-VLAN-08', '1.6', 'VLAN 间路由', 'VLAN 间路由'),
    ('KP-VLAN-09', '1.7', 'MAC 地址表', 'MAC 地址表与 VLAN'),
    ('KP-VLAN-10', '1.8', '端口隔离', '端口隔离'),
    ('KP-VLAN-11', '1.9', 'Voice VLAN', 'Voice VLAN'),
    ('KP-VLAN-12', '1.10', '规划与排障', 'VLAN 规划与排障'),
  ];
  return <Map<String, dynamic>>[
    for (var i = 0; i < specs.length; i++)
      _backendPoint(
        id: specs[i].$1,
        code: specs[i].$2,
        topic: specs[i].$3,
        title: specs[i].$4,
        orderNo: i + 1,
      ),
    _backendPoint(
      id: 'KP-OSPF-01',
      module: 'OSPF',
      code: '1.2',
      topic: 'OSPF 基础',
      title: 'OSPF 综合',
      contentMd: null,
      commands: null,
      orderNo: 2,
    ),
  ];
}

http.Response _json(Object body, [int status = 200]) {
  return http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    status,
    headers: <String, String>{'content-type': 'application/json'},
  );
}

/// 按路径分发的 MockClient；请求计数供「未登录不发请求」断言。
class _Router {
  _Router({
    this.points = const <Map<String, dynamic>>[],
    this.question,
    this.questionStatus = 200,
    this.details = const <String, Map<String, dynamic>>{},
    this.pointsStatus = 200,
    this.pointsBody,
    this.forcePageSize,
  });

  final List<Map<String, dynamic>> points;
  final Map<String, dynamic>? question;
  final int questionStatus;
  final Map<String, Map<String, dynamic>> details;
  final int pointsStatus;
  final String? pointsBody;
  final int? forcePageSize;
  int requests = 0;

  MockClient get client => MockClient((request) async {
    requests++;
    final path = request.url.path;
    if (path == '/api/v1/knowledge/points') {
      if (pointsStatus != 200) return http.Response('', pointsStatus);
      if (pointsBody != null) {
        return http.Response.bytes(
          utf8.encode(pointsBody!),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      }
      final page = int.parse(request.url.queryParameters['page'] ?? '1');
      final size =
          forcePageSize ??
          int.parse(request.url.queryParameters['page_size'] ?? '20');
      final start = (page - 1) * size;
      final slice = start >= points.length
          ? <Map<String, dynamic>>[]
          : points.sublist(start, min(start + size, points.length));
      return _json(<String, dynamic>{
        'points': slice,
        'page': page,
        'pageSize': size,
        'total': points.length,
      });
    }
    if (path.startsWith('/api/v1/knowledge/points/')) {
      final id = Uri.decodeComponent(path.split('/').last);
      final detail = details[id];
      if (detail == null) return _json(<String, dynamic>{}, 404);
      return _json(detail);
    }
    if (path.startsWith('/api/v1/bank/questions/')) {
      if (questionStatus != 200 || question == null) {
        return http.Response('', questionStatus);
      }
      return _json(question!);
    }
    return http.Response('', 404);
  });
}

class _FallbackRepo implements KnowledgeRepository {
  int chaptersCalls = 0;
  int byQuestionCalls = 0;

  @override
  Future<List<Chapter>> getChapters() async {
    chaptersCalls++;
    return const <Chapter>[
      Chapter(id: 'MOCK-01', module: 'VLAN', title: '样例章', order: 1),
    ];
  }

  @override
  Future<List<Section>> getSections(String chapterId) async {
    return const <Section>[
      Section(id: 'MOCK-01-01', chapterId: 'MOCK-01', title: '样例节', order: 1),
    ];
  }

  @override
  Future<List<KnowledgePoint>> getPointsBySection(String sectionId) async {
    return const <KnowledgePoint>[];
  }

  @override
  Future<KnowledgePoint?> getPointDetail(String id) async => null;

  @override
  Future<List<KnowledgePoint>> getPointsByQuestion(String questionId) async {
    byQuestionCalls++;
    return const <KnowledgePoint>[];
  }

  @override
  Future<KnowledgePoint?> getDailyPoint() async => null;
}

HttpKnowledgeRepository _repo(_Router router, _FallbackRepo fallback) {
  return HttpKnowledgeRepository(
    fallback: fallback,
    client: router.client,
    baseUrl: _base,
    tokenProvider: () => 'test-token',
  );
}

// ---- 答题页 widget 测试的注入件（沿用 quiz_page_test.dart 的 Fake 形状） ----

Question _question(int index) {
  return Question(
    id: 'VLAN-${index.toString().padLeft(4, '0')}',
    module: 'VLAN',
    type: 'single',
    stem: '题干 $index',
    options: const <QuestionOption>[
      QuestionOption(key: 'A', text: 'A 选项'),
      QuestionOption(key: 'B', text: 'B 选项'),
      QuestionOption(key: 'C', text: 'C 选项'),
      QuestionOption(key: 'D', text: 'D 选项'),
    ],
    answer: const <String>['A'],
    explanation: '解析内容',
    knowledge_point_id: 'KP-VLAN-04',
    difficulty: 1,
    set_no: 1,
    row_version: 1,
  );
}

class _FakePracticeService implements PracticeService {
  _FakePracticeService(this.questions);

  final List<Question> questions;

  @override
  Future<PracticeRecordDetail?> getRecordDetail(String sessionId) async => null;

  @override
  Future<bool> deleteRecord(String sessionId) async => false;

  @override
  Future<PracticeRecordPaper?> getRecordPaper(String sessionId) async => null;

  @override
  Future<PracticeNext?> drawNextQuestion({
    required String setId,
    String? module,
    required Set<String> excludedIds,
    String? sessionId,
  }) async {
    for (final q in questions) {
      if (!excludedIds.contains(q.id)) {
        return PracticeNext(
          question: q,
          sessionId: sessionId ?? 'S-1',
          doneCount: excludedIds.length,
        );
      }
    }
    return null;
  }

  @override
  Future<AnswerResult> submitAnswer({
    required String sessionId,
    required String questionId,
    required List<String> chosen,
    required int durationMs,
    String? setId,
    String? opId,
    String? mode,
  }) async {
    final q = questions.firstWhere((q) => q.id == questionId);
    final correct =
        chosen.length == q.answer.length &&
        chosen.toSet().containsAll(q.answer);
    return AnswerResult(
      correct: correct,
      explanation: '解析内容',
      correctKeys: q.answer,
      opId: opId,
    );
  }

  @override
  Future<PracticeSession> startSession({
    required List<Question> questions,
    required String mode,
  }) async {
    return PracticeSession(
      id: 'S-1',
      questions: questions,
      mode: mode,
      total: questions.length,
    );
  }

  @override
  Future<ContinueSession?> resumeSession({required String setId}) async => null;

  @override
  Future<ContinueSession?> getContinueSession() async => null;

  @override
  Future<PracticeSessionInfo?> startPracticeSession({String? module}) async =>
      null;

  @override
  Future<PracticeSessionInfo?> fetchPracticeSession(String sessionId) async =>
      null;

  @override
  Future<PracticeSessionInfo?> endPracticeSession(String sessionId) async =>
      null;

  @override
  Future<List<PracticeRecordSummary>> fetchPracticeRecords({
    int page = 1,
    int pageSize = 20,
  }) async => const <PracticeRecordSummary>[];

  @override
  Future<List<PracticeModuleProgress>> fetchPracticeProgress() async =>
      const <PracticeModuleProgress>[];
}

Widget _host(Widget quiz, {void Function(RouteSettings)? onRoute}) {
  return MaterialApp(
    theme: AppTheme.light,
    onGenerateRoute: (settings) {
      onRoute?.call(settings);
      if (settings.name == '/quiz') {
        return MaterialPageRoute<void>(
          builder: (_) => quiz,
          settings: settings,
        );
      }
      return MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Center(child: Text('知识详情页'))),
        settings: settings,
      );
    },
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).pushNamed('/quiz'),
            child: const Text('launch'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _launch(WidgetTester tester, Widget quiz) async {
  await tester.pumpWidget(_host(quiz));
  await tester.tap(find.text('launch'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HttpKnowledgeRepository 映射', () {
    test('camelCase → snake_case，commands null → 空数组', () async {
      final router = _Router(
        points: <Map<String, dynamic>>[
          _backendPoint(commands: null, rowVersion: 7),
        ],
      );
      final repo = _repo(router, _FallbackRepo());

      final chapters = await repo.getChapters();
      expect(chapters.single.id, 'VLAN-01');
      final points = await repo.getPointsBySection('VLAN-01-03');
      final point = points.single;
      expect(point.id, 'KP-VLAN-04');
      expect(point.content_md, '## 概念\nTrunk 端口允许多个 VLAN 通过。');
      expect(point.commands, isNotNull);
      expect(point.commands, isEmpty);
      expect(point.key_points, <String>['要点一']);
      expect(point.pitfalls, <String>['易错一']);
      expect(point.tags, <String>['Trunk']);
      expect(point.row_version, 7);
      expect(point.status, 'active');
    });

    test('commands 有值时解析 {cmd, desc}', () async {
      final router = _Router(
        points: <Map<String, dynamic>>[
          _backendPoint(
            commands: <Map<String, String>>[
              <String, String>{'cmd': 'display vlan', 'desc': '查看 VLAN'},
            ],
          ),
        ],
      );
      final repo = _repo(router, _FallbackRepo());
      await repo.getChapters();
      final point = (await repo.getPointsBySection('VLAN-01-03')).single;
      expect(point.commands!.single.cmd, 'display vlan');
      expect(point.commands!.single.desc, '查看 VLAN');
    });

    test('章/节由真实 VLAN KP 的 code 前缀聚合，占位 KP 不进浏览结构', () async {
      final router = _Router(points: _vlanBank());
      final repo = _repo(router, _FallbackRepo());

      final chapters = await repo.getChapters();
      expect(chapters.length, 1);
      expect(chapters.single.id, 'VLAN-01');
      expect(chapters.single.module, 'VLAN');
      expect(chapters.single.title, 'VLAN 技术');

      final sections = await repo.getSections('VLAN-01');
      expect(sections.length, 10);
      expect(sections[2].id, 'VLAN-01-03');
      expect(sections[2].title, '端口类型');
      expect(sections.last.id, 'VLAN-01-10');

      final portPoints = await repo.getPointsBySection('VLAN-01-03');
      expect(portPoints.map((p) => p.id).toList(), <String>[
        'KP-VLAN-03',
        'KP-VLAN-04',
        'KP-VLAN-05',
      ]);
      final vlanBasic = await repo.getPointsBySection('VLAN-01-01');
      expect(vlanBasic.single.id, 'KP-VLAN-01');
    });

    test('分页拉取：后端小页时逐页取完', () async {
      final router = _Router(
        points: <Map<String, dynamic>>[
          _backendPoint(id: 'KP-VLAN-01', code: '1.1', topic: 'VLAN 基础'),
          _backendPoint(id: 'KP-VLAN-02', code: '1.2', topic: '802.1Q'),
          _backendPoint(id: 'KP-VLAN-06', code: '1.4', topic: 'VLAN 管理'),
        ],
        forcePageSize: 1,
      );
      final repo = _repo(router, _FallbackRepo());
      final sections = await repo.getSections('VLAN-01');
      expect(sections.length, 3);
      expect(router.requests, 3);
    });

    test('未登录 → Mock，不发请求', () async {
      final router = _Router(points: _vlanBank());
      final fallback = _FallbackRepo();
      final repo = HttpKnowledgeRepository(
        fallback: fallback,
        client: router.client,
        baseUrl: _base,
        tokenProvider: () => null,
      );
      final chapters = await repo.getChapters();
      expect(chapters.single.id, 'MOCK-01');
      expect(await repo.getPointsByQuestion('VLAN-0001'), isEmpty);
      expect(fallback.byQuestionCalls, 1);
      expect(router.requests, 0);
    });

    test('500 / 非 JSON → Mock，不抛给 UI', () async {
      final fallback = _FallbackRepo();
      final repo500 = _repo(_Router(pointsStatus: 500), fallback);
      expect((await repo500.getChapters()).single.id, 'MOCK-01');

      final repoBad = _repo(_Router(pointsBody: 'not json'), fallback);
      expect((await repoBad.getChapters()).single.id, 'MOCK-01');
      expect(fallback.chaptersCalls, 2);
    });

    test('getPointDetail：200 映射，404 回落 Mock', () async {
      final router = _Router(
        details: <String, Map<String, dynamic>>{'KP-VLAN-04': _backendPoint()},
      );
      final repo = _repo(router, _FallbackRepo());
      final point = await repo.getPointDetail('KP-VLAN-04');
      expect(point, isNotNull);
      expect(point!.content_md, isNotEmpty);
      expect(await repo.getPointDetail('KP-NOPE'), isNull);
    });

    test('getDailyPoint：返回首个真实 KP', () async {
      final repo = _repo(_Router(points: _vlanBank()), _FallbackRepo());
      final point = await repo.getDailyPoint();
      expect(point!.id, 'KP-VLAN-01');
    });
  });

  group('getPointsByQuestion 真实内容门槛', () {
    test('题目 → knowledgePointId → 有正文的 KP', () async {
      final router = _Router(
        question: <String, dynamic>{
          'id': 'VLAN-0001',
          'knowledgePointId': 'KP-VLAN-04',
        },
        details: <String, Map<String, dynamic>>{'KP-VLAN-04': _backendPoint()},
      );
      final repo = _repo(router, _FallbackRepo());
      final points = await repo.getPointsByQuestion('VLAN-0001');
      expect(points.single.id, 'KP-VLAN-04');
      expect(points.single.content_md, isNotEmpty);
    });

    test('contentMd null / 空串 → []，不拿空内容冒充真实', () async {
      for (final content in <String?>[null, '', '   ']) {
        final router = _Router(
          question: <String, dynamic>{'knowledgePointId': 'KP-OSPF-01'},
          details: <String, Map<String, dynamic>>{
            'KP-OSPF-01': _backendPoint(
              id: 'KP-OSPF-01',
              module: 'OSPF',
              contentMd: content,
            ),
          },
        );
        final repo = _repo(router, _FallbackRepo());
        expect(await repo.getPointsByQuestion('OSPF-0001'), isEmpty);
      }
    });

    test('题目 404 → 回落 Mock；缺 knowledgePointId → []', () async {
      final fallback = _FallbackRepo();
      final repo404 = _repo(_Router(questionStatus: 404), fallback);
      expect(await repo404.getPointsByQuestion('VLAN-9999'), isEmpty);
      expect(fallback.byQuestionCalls, 1);

      final repoNoKp = _repo(
        _Router(question: <String, dynamic>{'id': 'VLAN-0001'}),
        fallback,
      );
      expect(await repoNoKp.getPointsByQuestion('VLAN-0001'), isEmpty);
    });
  });

  group('QuizPage 知识点 chip', () {
    late KvStore kv;
    late KvAnswerRecordService records;
    late KvAnswerSessionService sessions;

    setUp(() {
      kv = InMemoryKvStore();
      records = KvAnswerRecordService(kvStore: kv);
      sessions = KvAnswerSessionService(kvStore: kv);
    });

    Widget page(_Router router) {
      return QuizPage(
        args: <String, Object?>{
          'mode': 'practice',
          'setId': 'VLAN',
          'setTitle': 'VLAN',
          'drawCount': 100,
          'target': 20,
        },
        practiceService: _FakePracticeService(<Question>[_question(1)]),
        recordService: records,
        sessionService: sessions,
        favoriteService: MockFavoriteService(),
        knowledgeRepository: _repo(router, _FallbackRepo()),
      );
    }

    _Router chipRouter({String? contentMd = '## 概念\nTrunk 正文'}) {
      return _Router(
        question: <String, dynamic>{
          'id': 'VLAN-0001',
          'knowledgePointId': 'KP-VLAN-04',
        },
        details: <String, Map<String, dynamic>>{
          'KP-VLAN-04': _backendPoint(contentMd: contentMd),
        },
      );
    }

    testWidgets('判分后显示 KP chip；判分前不显示', (tester) async {
      await _launch(tester, page(chipRouter()));
      expect(find.textContaining('知识点：'), findsNothing);

      await tester.tap(find.text('A 选项'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('知识点：Trunk 端口收发规则'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('知识点：Trunk 端口收发规则'), findsOneWidget);
    });

    testWidgets('占位 KP（contentMd null）判分后也不显示 chip', (tester) async {
      await _launch(tester, page(chipRouter(contentMd: null)));

      await tester.tap(find.text('A 选项'));
      await tester.pumpAndSettle();
      // 解析卡与 chip 同区：先滚到解析，确认该区域已构建，再断言无 chip。
      await tester.scrollUntilVisible(
        find.text('解析内容'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('解析内容'), findsOneWidget);
      expect(find.textContaining('知识点：'), findsNothing);
    });

    testWidgets('点按 chip 走知识库同一命名路由，returnTo=quiz', (tester) async {
      final routes = <RouteSettings>[];
      await tester.pumpWidget(_host(page(chipRouter()), onRoute: routes.add));
      await tester.tap(find.text('launch'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('A 选项'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('知识点：Trunk 端口收发规则'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('知识点：Trunk 端口收发规则'));
      await tester.pumpAndSettle();

      expect(find.text('知识详情页'), findsOneWidget);
      final detail = routes.last;
      expect(detail.name, AppRoutes.knowledgePoint);
      final args = detail.arguments! as Map<String, Object?>;
      expect(args['kpId'], 'KP-VLAN-04');
      expect(args['sectionId'], 'VLAN-01-03');
      expect(args['returnTo'], 'quiz');
    });
  });
}
