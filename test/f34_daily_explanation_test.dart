import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:routepass/core/kv_store.dart';
import 'package:routepass/core/service_locator.dart';
import 'package:routepass/core/theme.dart';
import 'package:routepass/models/daily_question.dart';
import 'package:routepass/models/question.dart';
import 'package:routepass/pages/home/home_content.dart';
import 'package:routepass/services/bank/daily_practice_service_http.dart';
import 'package:routepass/services/mock/mock_answer_record_service.dart';
import 'package:routepass/services/mock/mock_answer_session_service.dart';
import 'package:routepass/services/mock/mock_auth_service.dart';
import 'package:routepass/services/mock/mock_bank_manifest_service.dart';
import 'package:routepass/services/mock/mock_cli_service.dart';
import 'package:routepass/services/mock/mock_content_service.dart';
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

import 'support/fake_connectivity.dart';

/// F34 A1：每日一练保留并展示后端 explanation。
/// - 服务层：/bank/questions 形状 JSON 经 _mapQuestion → DailyQuestion，
///   explanation 原样存活；无解析的题为 null/空，不编造；
/// - 日期锁 kv 往返（重启）不丢 explanation，同日不重复请求；
/// - 组件层：作答后卡片显示「解析：<后端原文>」；未作答不显示；
///   无解析 / 空串解析的题作答后不显示任何解析文案（无占位）。

const String _base = 'http://example.test';
const String _explanation = 'OSPF 邻居建立要求 Hello 报文的区域 ID、认证与定时器参数一致。';

/// 组件测试用：当前后端返回的 explanation（null = 该题没有解析）。
String? _widgetExplanation = _explanation;

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: const <String, String>{
    'content-type': 'application/json; charset=utf-8',
  },
);

/// 后端 /bank/questions 的单选题形状（F17：options 纯字符串、answer 0 基下标）。
Map<String, Object?> _bankQuestion({String? explanation}) => <String, Object?>{
  'id': 'Q-101',
  'type': 'single',
  'stem': 'OSPF 邻居建立失败时，首先应检查下列哪一项？',
  'options': <String>['Hello 参数是否一致', '路由表大小', '设备型号', '电源状态'],
  'answer': <int>[0],
  'explanation': ?explanation,
};

Map<String, Object?> _bankPage(Map<String, Object?> question) =>
    <String, Object?>{
      'page': 1,
      'pageSize': 20,
      'total': 1,
      'questions': <Map<String, Object?>>[question],
    };

HttpDailyPracticeService _service(http.Client client, {KvStore? kv}) {
  return HttpDailyPracticeService(
    client: client,
    baseUrl: _base,
    kvStore: kv ?? InMemoryKvStore(),
    random: Random(7),
  );
}

/// 高视口：每日一练卡（含解析与锁定提示）整卡同屏挂载。
void _useTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpHome(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: HomeContentPage(onSelectTab: (_) {}),
    ),
  );
  await tester.pumpAndSettle();
}

Future<DailyQuestion> _answerFirstOption(WidgetTester tester) async {
  final question = await ServiceLocator.dailyPracticeService.questionForDate(
    DateTime.now(),
  );
  await tester.tap(
    find.byKey(ValueKey('daily-option-${question.options.first.key}')),
  );
  await tester.pump();
  await tester.pumpAndSettle();
  return question;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 组件测试走真实 HTTP 抽题路径（MockClient 模拟 /bank/questions），
  // 其余服务与 initTestServices 一致。ServiceLocator.init 幂等，每文件装配一次。
  final syncService = MockSyncService();
  final connectivity = FakeConnectivityService();
  ServiceLocator.init(
    questionRepository: MockQuestionRepository(),
    bankManifestService: MockBankManifestService(),
    answerRecordService: MockAnswerRecordService(),
    answerSessionService: MockAnswerSessionService(),
    practiceService: MockPracticeService(),
    examService: MockExamService(),
    dailyPracticeService: HttpDailyPracticeService(
      client: MockClient((request) async {
        expect(request.url.path, '/api/v1/bank/questions');
        return _json(_bankPage(_bankQuestion(explanation: _widgetExplanation)));
      }),
      baseUrl: _base,
      random: Random(7),
    ),
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
    contentService: MockContentService(),
    syncModeService: SyncModeService(
      connectivity: connectivity,
      syncService: syncService,
      isLoggedIn: () async =>
          (await ServiceLocator.authService.getCurrentUser()) != null,
    ),
  );

  setUp(() {
    // kv 是进程级静态实例：清掉日期锁与作答状态，避免测试间串扰。
    ServiceLocator.kvStore.remove(KvStore.keyDailyDrawn);
    ServiceLocator.kvStore.remove(KvStore.keyDailyAnswer);
    _widgetExplanation = _explanation;
  });

  group('A1 服务层：explanation 经 _mapQuestion 存活到模型', () {
    test('/bank/questions 带 explanation → 原样保留，判分映射不受影响', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/v1/bank/questions');
        return _json(_bankPage(_bankQuestion(explanation: _explanation)));
      });

      final q = await _service(client).questionForDate(DateTime(2026, 11, 18));
      expect(q.id, 'Q-101');
      expect(q.correctKey, 'A');
      expect(q.options.length, 4);
      expect(q.explanation, _explanation);
    });

    test('无 explanation 字段 / 空串 → null 或空，不编造解析文案', () async {
      for (final payload in <Map<String, Object?>>[
        _bankQuestion(),
        _bankQuestion(explanation: ''),
      ]) {
        final client = MockClient((request) async => _json(_bankPage(payload)));
        final q = await _service(client)
            .questionForDate(DateTime(2026, 11, 18));
        expect(q.explanation == null || q.explanation!.isEmpty, isTrue);
      }
    });

    test('日期锁 kv 往返（模拟重启）不丢 explanation，同日不重复请求', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return _json(_bankPage(_bankQuestion(explanation: _explanation)));
      });
      final kv = InMemoryKvStore();
      final date = DateTime(2026, 11, 18);

      final first = await _service(client, kv: kv).questionForDate(date);
      expect(first.explanation, _explanation);
      expect(calls, 1);

      // 新实例读同一份 kv（重启路径）：命中日期锁，不发网络请求。
      final restarted = _service(client, kv: kv);
      final again = await restarted.questionForDate(date);
      expect(again.explanation, _explanation);
      expect(calls, 1);
    });

    test('DailyQuestion.toJson/fromJson 保留 explanation（含 null 与旧存储）', () {
      final q = DailyQuestion(
        id: 'DAILY-001',
        stem: '题干',
        options: const <QuestionOption>[QuestionOption(key: 'A', text: '选项')],
        correctKey: 'A',
        explanation: _explanation,
      );
      final back = DailyQuestion.fromJson(
        jsonDecode(jsonEncode(q.toJson())) as Map<String, dynamic>,
      );
      expect(back.explanation, _explanation);

      const none = DailyQuestion(
        id: 'DAILY-002',
        stem: '题干',
        options: <QuestionOption>[],
        correctKey: 'A',
      );
      final back2 = DailyQuestion.fromJson(
        jsonDecode(jsonEncode(none.toJson())) as Map<String, dynamic>,
      );
      expect(back2.explanation, isNull);

      // F34 之前存的 daily.drawn 没有 explanation 键 → 读回 null，不炸。
      final legacy = DailyQuestion.fromJson(<String, dynamic>{
        'id': 'DAILY-003',
        'stem': '题干',
        'options': <dynamic>[],
        'correctKey': 'A',
      });
      expect(legacy.explanation, isNull);
    });
  });

  group('A1 组件层：每日一练卡作答后显示后端解析', () {
    testWidgets('作答前不显示解析；作答后显示「解析：<后端原文>」', (tester) async {
      _useTallViewport(tester);
      await _pumpHome(tester);

      expect(find.byKey(const ValueKey('daily-practice-card')), findsOneWidget);
      expect(find.byKey(const ValueKey('daily-explanation')), findsNothing);

      await _answerFirstOption(tester);

      final explanation = find.byKey(const ValueKey('daily-explanation'));
      expect(explanation, findsOneWidget);
      expect(tester.widget<Text>(explanation).data, '解析：$_explanation');
      expect(find.text('已锁定，明天刷新'), findsOneWidget);
    });

    testWidgets('后端没有解析的题：作答后不显示任何解析文案（无占位）', (tester) async {
      _widgetExplanation = null;
      _useTallViewport(tester);
      await _pumpHome(tester);

      await _answerFirstOption(tester);

      expect(find.byKey(const ValueKey('daily-explanation')), findsNothing);
      expect(find.textContaining('解析'), findsNothing);
      expect(find.text('已锁定，明天刷新'), findsOneWidget);
    });

    testWidgets('空串解析同样不显示（不编造、不放「解析待接口」）', (tester) async {
      _widgetExplanation = '';
      _useTallViewport(tester);
      await _pumpHome(tester);

      await _answerFirstOption(tester);

      expect(find.byKey(const ValueKey('daily-explanation')), findsNothing);
      expect(find.textContaining('解析待接口'), findsNothing);
      expect(find.text('已锁定，明天刷新'), findsOneWidget);
    });
  });
}
