import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:routepass/core/kv_store.dart';
import 'package:routepass/services/bank/daily_practice_service_http.dart';
import 'package:routepass/services/mock/mock_content_service.dart';
import 'package:routepass/services/mock/mock_exam_service.dart';
import 'package:routepass/services/mock/mock_ping_service.dart';
import 'package:routepass/services/mock/mock_question_repository.dart';
import 'package:routepass/services/mock/mock_stats_service.dart';
import 'package:routepass/services/toolbox/ip_convert_service_impl.dart';
import 'package:routepass/services/toolbox/subnet_calc_service_impl.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Mock 样例题：3 道、answer 为 []、explanation 为空、题干以开头', () async {
    final repo = MockQuestionRepository();
    final questions = await repo.drawQuestions(mode: 'quick', drawCount: 10);
    expect(questions.length, 3);
    for (final q in questions) {
      expect(q.answer, isEmpty);
      expect(q.explanation, isEmpty);
      expect(q.stem.startsWith(''), isTrue);
    }
    final modules = await repo.getModules();
    expect(modules.length, 5);
    expect(modules.every((m) => m.total == 0), isTrue);
  });

  test('Mock 统计全 0', () async {
    final stats = MockStatsService();
    final overview = await stats.getOverview();
    expect(overview.answeredTotal, 0);
    expect(overview.todayAnswered, 0);
  });

  test('子网计算 192.168.1.0/24', () async {
    final svc = LocalSubnetCalcService();
    final r = await svc.calculate(ip: '192.168.1.0', prefix: 24);
    expect(r.network, '192.168.1.0');
    expect(r.broadcast, '192.168.1.255');
    expect(r.firstHost, '192.168.1.1');
    expect(r.lastHost, '192.168.1.254');
    expect(r.hostCount, 254);
    expect(r.netmask, '255.255.255.0');
    expect(r.wildcard, '0.0.0.255');
    final vlsm = await svc.planVlsm(
      network: '192.168.1.0/24',
      hostCounts: [50, 20],
    );
    expect(vlsm, isNotNull);
  });

  test('IP/进制转换', () async {
    final svc = LocalIpConvertService();
    final a = await svc.convert('192.168.1.1');
    expect(a.decimal, '3232235777');
    expect(a.hex, '0xC0A80101');
    final b = await svc.convert('/24');
    expect(b.cidr, '/24');
    expect(b.netmask, '255.255.255.0');
    final c = await svc.convert('255.255.255.0');
    expect(c.cidr, '/24');
  });

  test('Mock 考试不计分：score 为 null', () async {
    final svc = MockExamService();
    final session = await svc.startExam(drawCount: 100);
    expect(session.total, 3);
    final result = await svc.submitExam(
      examId: session.id,
      answers: {},
      durationMs: 0,
    );
    expect(result?.score, isNull);
  });

  test('Mock Ping 返回待接本地服务占位', () async {
    final svc = MockPingService();
    final r = await svc.ping(host: '192.168.1.1', port: 80);
    expect(r.state, 'not_connected');
    expect(r.message, '待接本地服务');
    expect(r.latencyMs, isNull);
  });

  test('Mock 内容版本与升级检查永不触发升级', () async {
    final svc = MockContentService();
    final v = await svc.getContentVersion();
    expect(v.bank_version, '1.0.0');
    final check = await svc.checkUpgrade();
    expect(check.compatibility, 'ok');
    expect(check.force, isFalse);
  });

  group('VLSM planVlsm（T6a 真实算法）', () {
    test('192.168.1.0/24 拆 50/20/10 台主机', () async {
      final plan = await LocalSubnetCalcService().planVlsm(
        network: '192.168.1.0/24',
        hostCounts: [50, 20, 10],
      );
      expect(plan, isNotNull);
      expect(plan!.network, '192.168.1.0/24');
      expect(plan.subnets.length, 3);
      expect(plan.subnets[0]['network'], '192.168.1.0');
      expect(plan.subnets[0]['prefix'], 26);
      expect(plan.subnets[0]['hosts'], 62);
      expect(plan.subnets[1]['network'], '192.168.1.64');
      expect(plan.subnets[1]['prefix'], 27);
      expect(plan.subnets[1]['hosts'], 30);
      expect(plan.subnets[2]['network'], '192.168.1.96');
      expect(plan.subnets[2]['prefix'], 28);
      expect(plan.subnets[2]['hosts'], 14);
    });

    test('需求超出母网容量时抛 FormatException', () async {
      expect(
        () => LocalSubnetCalcService().planVlsm(
          network: '192.168.1.0/30',
          hostCounts: [10],
        ),
        throwsFormatException,
      );
    });

    test('母网无前缀时抛 FormatException', () async {
      expect(
        () => LocalSubnetCalcService().planVlsm(
          network: '192.168.1.0',
          hostCounts: [10],
        ),
        throwsFormatException,
      );
    });
  });

  group('F17 HttpDailyPracticeService 全库抽题 + 日期锁', () {
    // 假题库：4 题（3 单选 + 1 多选），pageSize=2 → 2 页。
    // page1 = [Q-1, Q-2]，page2 = [Q-3, Q-M(多选)]。
    Map<int, List<Map<String, dynamic>>> pages() =>
        <int, List<Map<String, dynamic>>>{
          1: [
            _bankQuestion('Q-1'),
            _bankQuestion('Q-2', stem: 'HTTP 服务的默认端口号是', answer: [0]),
          ],
          2: [
            _bankQuestion('Q-3', stem: 'DNS 服务的默认端口号是', answer: [2]),
            _bankQuestion('Q-M', type: 'multiple', answer: [0, 1]),
          ],
        };

    test('(a) 首次抽题：题目来自后端，连同日期存入 daily.drawn', () async {
      final kv = InMemoryKvStore();
      final log = <Uri>[];
      final service = HttpDailyPracticeService(
        client: _fakeBankClient(pages(), total: 4, pageSize: 2, log: log),
        kvStore: kv,
        random: _ScriptedRandom([0]),
      );

      final question = await service.questionForDate(
        DateTime(2026, 11, 13, 9, 30),
      );

      expect(question.id, 'Q-1');
      expect(question.stem, 'SSH 服务的默认端口号是');
      expect(log, isNotEmpty);
      final stored = jsonDecode(
        kv.getString(KvStore.keyDailyDrawn)!,
      ) as Map<String, dynamic>;
      expect(stored['date'], '2026-11-13');
      expect(stored['question'], question.toJson());
    });

    test('(b) 同日再调用：返回存好的题，不发新的 HTTP 请求', () async {
      final kv = InMemoryKvStore();
      final log = <Uri>[];
      final service = HttpDailyPracticeService(
        client: _fakeBankClient(pages(), total: 4, pageSize: 2, log: log),
        kvStore: kv,
        random: _ScriptedRandom([0]),
      );

      final first = await service.questionForDate(DateTime(2026, 11, 13));
      final requestsAfterDraw = log.length;

      final again = await service.questionForDate(
        DateTime(2026, 11, 13, 23, 59),
      );
      expect(again.id, first.id);
      expect(log.length, requestsAfterDraw);
    });

    test('(c) 次日调用：重新抽题并更新存储日期', () async {
      final kv = InMemoryKvStore();
      final log = <Uri>[];
      final service = HttpDailyPracticeService(
        client: _fakeBankClient(pages(), total: 4, pageSize: 2, log: log),
        kvStore: kv,
        random: _ScriptedRandom([0, 2]),
      );

      final first = await service.questionForDate(DateTime(2026, 11, 13));
      expect(first.id, 'Q-1');
      final requestsDay1 = log.length;

      final next = await service.questionForDate(DateTime(2026, 11, 14));
      expect(next.id, 'Q-3');
      expect(next.id, isNot(first.id));
      expect(log.length, greaterThan(requestsDay1));
      final stored = jsonDecode(
        kv.getString(KvStore.keyDailyDrawn)!,
      ) as Map<String, dynamic>;
      expect(stored['date'], '2026-11-14');
      expect(stored['question'], next.toJson());
    });

    test('(d) 映射：options → A–D key，answer[0] → correctKey；多选被排除', () async {
      // 下标 1 → Q-2：answer [0] → correctKey A。
      final mapper = HttpDailyPracticeService(
        client: _fakeBankClient(pages(), total: 4, pageSize: 2),
        kvStore: InMemoryKvStore(),
        random: _ScriptedRandom([1]),
      );
      final q = await mapper.questionForDate(DateTime(2026, 11, 13));
      expect(q.id, 'Q-2');
      expect(q.options.map((o) => o.key).toList(), ['A', 'B', 'C', 'D']);
      expect(q.options.map((o) => o.text).toList(), ['21', '22', '23', '80']);
      expect(q.correctKey, 'A');

      // 下标 3 → Q-M（多选）被拒 → 重抽下标 2 → Q-3：answer [2] → C。
      final filter = HttpDailyPracticeService(
        client: _fakeBankClient(pages(), total: 4, pageSize: 2),
        kvStore: InMemoryKvStore(),
        random: _ScriptedRandom([3, 2]),
      );
      final q2 = await filter.questionForDate(DateTime(2026, 11, 13));
      expect(q2.id, 'Q-3');
      expect(q2.correctKey, 'C');
    });

    test('抽题失败：抛 DailyPracticeException，不回退、不落存储', () async {
      final kv = InMemoryKvStore();
      final service = HttpDailyPracticeService(
        client: MockClient((request) async => http.Response('boom', 500)),
        kvStore: kv,
        random: _ScriptedRandom([0]),
      );
      await expectLater(
        service.questionForDate(DateTime(2026, 11, 13)),
        throwsA(isA<DailyPracticeException>()),
      );
      expect(kv.getString(KvStore.keyDailyDrawn), isNull);
    });

    test('网络异常：同样抛 DailyPracticeException', () async {
      final service = HttpDailyPracticeService(
        client: MockClient(
          (request) async => throw http.ClientException('offline'),
        ),
        kvStore: InMemoryKvStore(),
        random: _ScriptedRandom([0]),
      );
      await expectLater(
        service.questionForDate(DateTime(2026, 11, 13)),
        throwsA(isA<DailyPracticeException>()),
      );
    });

    test('daily.drawn 损坏视为未抽，重新抽题', () async {
      final kv = InMemoryKvStore();
      kv.setString(KvStore.keyDailyDrawn, 'not-json');
      final service = HttpDailyPracticeService(
        client: _fakeBankClient(pages(), total: 4, pageSize: 2),
        kvStore: kv,
        random: _ScriptedRandom([0]),
      );
      final q = await service.questionForDate(DateTime(2026, 11, 13));
      expect(q.id, 'Q-1');
      final stored = jsonDecode(
        kv.getString(KvStore.keyDailyDrawn)!,
      ) as Map<String, dynamic>;
      expect(stored['date'], '2026-11-13');
    });

    test('作答状态：daily.answer 行为不变（当天可读、跨天隔离）', () async {
      final service = HttpDailyPracticeService(
        client: _fakeBankClient(pages(), total: 4, pageSize: 2),
        kvStore: InMemoryKvStore(),
        random: _ScriptedRandom([0]),
      );
      final today = DateTime(2026, 11, 13);
      expect(await service.answerForDate(today), isNull);
      await service.saveAnswer(
        date: today,
        questionId: 'Q-1',
        selectedKey: 'B',
      );
      expect(await service.answerForDate(today), 'B');
      expect(await service.answerForDate(DateTime(2026, 11, 14)), isNull);
    });
  });

  group('F17 SharedPreferencesKvStore 持久 kv', () {
    test('读写删与 KvStore 接口一致，重开实例数据仍在', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = await SharedPreferencesKvStore.create();
      expect(store.getString(KvStore.keyDailyDrawn), isNull);

      store.setString(KvStore.keyDailyDrawn, '{"date":"2026-11-13"}');
      expect(store.getString(KvStore.keyDailyDrawn), '{"date":"2026-11-13"}');
      store.setStringList(KvStore.keyKbExpandedIds, ['VLAN-01-03']);
      expect(store.getStringList(KvStore.keyKbExpandedIds), ['VLAN-01-03']);

      // 模拟重启：重新建实例读同一平台存储，数据仍在。
      final reopened = await SharedPreferencesKvStore.create();
      expect(
        reopened.getString(KvStore.keyDailyDrawn),
        '{"date":"2026-11-13"}',
      );
      reopened.remove(KvStore.keyDailyDrawn);
      expect(reopened.getString(KvStore.keyDailyDrawn), isNull);
    });
  });
}

/// F17：假后端题（形状与 /api/v1/bank/questions 实测一致）。
Map<String, dynamic> _bankQuestion(
  String id, {
  String type = 'single',
  String stem = 'SSH 服务的默认端口号是',
  List<String> options = const ['21', '22', '23', '80'],
  List<int> answer = const [1],
}) {
  return <String, dynamic>{
    'id': id,
    'module': 'H3CNE',
    'type': type,
    'difficulty': 2,
    'stem': stem,
    'options': options,
    'answer': answer,
    'explanation': '',
    'knowledgePointId': 'KP-TEST',
    'relatedKnowledgeIds': <String>[],
    'rowVersion': 1,
  };
}

/// F17：分页假 http.Client（固定 pageSize，与真实后端一致），记录请求。
http.Client _fakeBankClient(
  Map<int, List<Map<String, dynamic>>> pages, {
  required int total,
  int pageSize = 20,
  List<Uri>? log,
}) {
  return MockClient((request) async {
    log?.add(request.url);
    final page = int.parse(request.url.queryParameters['page'] ?? '1');
    return http.Response(
      jsonEncode(<String, dynamic>{
        'page': page,
        'pageSize': pageSize,
        'total': total,
        'questions': pages[page] ?? <Map<String, dynamic>>[],
      }),
      200,
      headers: <String, String>{'content-type': 'application/json'},
    );
  });
}

/// F17：脚本化 Random，nextInt 按序返回值，让抽题结果可复现。
class _ScriptedRandom implements Random {
  _ScriptedRandom(List<int> values) : _values = values;

  final List<int> _values;
  int _index = 0;

  @override
  int nextInt(int max) {
    final value = _values[_index++];
    if (value < 0 || value >= max) {
      throw StateError('scripted $value out of range [0, $max)');
    }
    return value;
  }

  @override
  double nextDouble() => throw UnimplementedError();

  @override
  bool nextBool() => throw UnimplementedError();
}
