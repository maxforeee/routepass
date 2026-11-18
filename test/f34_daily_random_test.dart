import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:routepass/core/kv_store.dart';
import 'package:routepass/services/bank/daily_practice_service_http.dart';

/// F34 B10：每日一练抽题优先走服务端随机端点
/// `GET /bank/practice?count=1&type=single`，任何失败回退旧的两步拒绝采样
/// （/bank/questions 整库翻页）。
/// - 成功路径：返回单选题、日期锁落 kv、同日不重复请求；
/// - 404/500/网络错误/空列表/形状错误/非单选/脏数据 → 回退（断言兜底请求真的发生）；
/// - 两条路径都失败 → DailyPracticeException（不回退 Mock、不本地编题）；
/// - 旧拒绝采样的脏数据跳过行为不变。

const String _base = 'http://example.test';
const String _randomPath = '/api/v1/bank/practice';
const String _pagePath = '/api/v1/bank/questions';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: const <String, String>{
    'content-type': 'application/json; charset=utf-8',
  },
);

/// 后端 /bank/practice 的单选题形状（与 /bank/questions 完全一致）。
Map<String, Object?> _single({
  String id = 'Q-RANDOM',
  String? explanation = '后端解析原文',
  List<int> answer = const <int>[0],
}) => <String, Object?>{
  'id': id,
  'type': 'single',
  'stem': 'OSPF 邻居建立失败时，首先应检查下列哪一项？',
  'options': <String>['Hello 参数是否一致', '路由表大小', '设备型号', '电源状态'],
  'answer': answer,
  'explanation': ?explanation,
};

Map<String, Object?> _multiple() => <String, Object?>{
  'id': 'Q-MULTI',
  'type': 'multiple',
  'stem': '以下哪些端口号是正确的？（多选）',
  'options': <String>['HTTP 80', 'HTTPS 443', 'DNS 53', 'FTP 21'],
  'answer': <int>[0, 1],
  'explanation': null,
};

Map<String, Object?> _page(
  List<Map<String, Object?>> questions, {
  int total = 1,
}) => <String, Object?>{
  'page': 1,
  'pageSize': 20,
  'total': total,
  'questions': questions,
};

HttpDailyPracticeService _service(http.Client client, {KvStore? kv}) {
  return HttpDailyPracticeService(
    client: client,
    baseUrl: _base,
    kvStore: kv ?? InMemoryKvStore(),
    random: Random(7),
  );
}

/// 按路径路由：随机端点返回 [randomResponse]，翻页兜底返回含
/// [fallbackQuestion] 的第 1 页（total=1 → 随机下标恒为 0，确定性命中）。
/// [paths] 记录真实请求顺序，用于断言「先随机端点、失败后才翻页」。
http.Client _routingClient({
  required http.Response Function() randomResponse,
  Map<String, Object?>? fallbackQuestion,
  required List<String> paths,
}) {
  return MockClient((request) async {
    paths.add(request.url.path);
    if (request.url.path == _randomPath) return randomResponse();
    if (request.url.path == _pagePath) {
      return _json(
        _page(<Map<String, Object?>>[
          fallbackQuestion ?? _single(id: 'Q-FALLBACK'),
        ]),
      );
    }
    throw StateError('unexpected request: ${request.url}');
  });
}

void main() {
  group('B10 随机端点成功路径', () {
    test('count=1&type=single 命中 → 返回单选题并写日期锁，不走翻页', () async {
      final paths = <String>[];
      final client = MockClient((request) async {
        paths.add(request.url.path);
        expect(request.url.queryParameters['count'], '1');
        expect(request.url.queryParameters['type'], 'single');
        return _json(<String, Object?>{
          'questions': <Map<String, Object?>>[_single()],
          'count': 1,
        });
      });
      final kv = InMemoryKvStore();
      final q = await _service(
        client,
        kv: kv,
      ).questionForDate(DateTime(2026, 11, 18));

      expect(q.id, 'Q-RANDOM');
      expect(q.correctKey, 'A');
      expect(q.options.length, 4);
      expect(q.explanation, '后端解析原文');
      expect(paths, <String>[_randomPath]);

      final locked = jsonDecode(
        kv.getString(KvStore.keyDailyDrawn)!,
      ) as Map<String, dynamic>;
      expect(locked['date'], '2026-11-18');
      expect((locked['question'] as Map<String, dynamic>)['id'], 'Q-RANDOM');
    });

    test('同日第二次调用命中日期锁，不发任何请求', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return _json(<String, Object?>{
          'questions': <Map<String, Object?>>[_single()],
          'count': 1,
        });
      });
      final kv = InMemoryKvStore();
      final date = DateTime(2026, 11, 18);

      await _service(client, kv: kv).questionForDate(date);
      final again = await _service(client, kv: kv).questionForDate(date);
      expect(again.id, 'Q-RANDOM');
      expect(calls, 1);
    });
  });

  group('B10 随机端点失败 → 两步拒绝采样兜底', () {
    test('404（后端部署前）→ 回退翻页抽题', () async {
      final paths = <String>[];
      final client = _routingClient(
        randomResponse: () => _json(<String, Object?>{}, 404),
        paths: paths,
      );
      final q = await _service(client).questionForDate(DateTime(2026, 11, 18));
      expect(q.id, 'Q-FALLBACK');
      expect(paths, <String>[_randomPath, _pagePath]);
    });

    test('500 → 回退翻页抽题', () async {
      final paths = <String>[];
      final client = _routingClient(
        randomResponse: () => _json(<String, Object?>{}, 500),
        paths: paths,
      );
      final q = await _service(client).questionForDate(DateTime(2026, 11, 18));
      expect(q.id, 'Q-FALLBACK');
      expect(paths, <String>[_randomPath, _pagePath]);
    });

    test('网络异常 → 回退翻页抽题', () async {
      final paths = <String>[];
      final client = _routingClient(
        randomResponse: () => throw http.ClientException('boom'),
        paths: paths,
      );
      final q = await _service(client).questionForDate(DateTime(2026, 11, 18));
      expect(q.id, 'Q-FALLBACK');
      expect(paths, <String>[_randomPath, _pagePath]);
    });

    test('空列表 → 回退翻页抽题', () async {
      final paths = <String>[];
      final client = _routingClient(
        randomResponse: () => _json(<String, Object?>{
          'questions': <Map<String, Object?>>[],
          'count': 0,
        }),
        paths: paths,
      );
      final q = await _service(client).questionForDate(DateTime(2026, 11, 18));
      expect(q.id, 'Q-FALLBACK');
      expect(paths, <String>[_randomPath, _pagePath]);
    });

    test('形状错误（questions 非列表 / 顶层非对象 / 非 JSON）→ 回退', () async {
      final badResponses = <http.Response Function()>[
        () => _json(<String, Object?>{'questions': 'oops'}),
        () => _json(<int>[1, 2, 3]),
        () => http.Response('not json', 200),
      ];
      for (final bad in badResponses) {
        final paths = <String>[];
        final client = _routingClient(randomResponse: bad, paths: paths);
        final q = await _service(client)
            .questionForDate(DateTime(2026, 11, 18));
        expect(q.id, 'Q-FALLBACK');
        expect(paths, <String>[_randomPath, _pagePath]);
      }
    });

    test('非单选题行 → 回退翻页抽题', () async {
      final paths = <String>[];
      final client = _routingClient(
        randomResponse: () => _json(<String, Object?>{
          'questions': <Map<String, Object?>>[_multiple()],
          'count': 1,
        }),
        paths: paths,
      );
      final q = await _service(client).questionForDate(DateTime(2026, 11, 18));
      expect(q.id, 'Q-FALLBACK');
      expect(paths, <String>[_randomPath, _pagePath]);
    });

    test('脏单选行（answer 下标越界）→ 回退翻页抽题', () async {
      final paths = <String>[];
      final client = _routingClient(
        randomResponse: () => _json(<String, Object?>{
          'questions': <Map<String, Object?>>[
            _single(answer: <int>[99]),
          ],
          'count': 1,
        }),
        paths: paths,
      );
      final q = await _service(client).questionForDate(DateTime(2026, 11, 18));
      expect(q.id, 'Q-FALLBACK');
      expect(paths, <String>[_randomPath, _pagePath]);
    });

    test('兜底路径同样写日期锁（重启不丢）', () async {
      final paths = <String>[];
      final client = _routingClient(
        randomResponse: () => _json(<String, Object?>{}, 404),
        paths: paths,
      );
      final kv = InMemoryKvStore();
      final date = DateTime(2026, 11, 18);
      final q = await _service(client, kv: kv).questionForDate(date);
      expect(q.id, 'Q-FALLBACK');

      final locked = jsonDecode(
        kv.getString(KvStore.keyDailyDrawn)!,
      ) as Map<String, dynamic>;
      expect(locked['date'], '2026-11-18');
      expect((locked['question'] as Map<String, dynamic>)['id'], 'Q-FALLBACK');

      // 新实例读同一份 kv：命中日期锁，不再发请求。
      final again = await _service(client, kv: kv).questionForDate(date);
      expect(again.id, 'Q-FALLBACK');
      expect(paths, <String>[_randomPath, _pagePath]);
    });
  });

  group('B10 两条路径都失败 / 旧采样行为不变', () {
    test('随机端点 404 且翻页 500 → DailyPracticeException，不本地编题', () async {
      final client = MockClient((request) async {
        if (request.url.path == _randomPath) {
          return _json(<String, Object?>{}, 404);
        }
        return _json(<String, Object?>{}, 500);
      });
      await expectLater(
        _service(client).questionForDate(DateTime(2026, 11, 18)),
        throwsA(isA<DailyPracticeException>()),
      );
    });

    test('翻页里的脏行被跳过重抽（旧拒绝采样行为不变）', () async {
      final client = MockClient((request) async {
        if (request.url.path == _randomPath) {
          return _json(<String, Object?>{}, 404);
        }
        // total=2：下标 0 是脏单选（answer 越界），下标 1 是干净单选。
        // Random(7) 在 30 次尝试内必然命中下标 1。
        return _json(
          _page(<Map<String, Object?>>[
            _single(id: 'Q-DIRTY', answer: <int>[99]),
            _single(id: 'Q-CLEAN'),
          ], total: 2),
        );
      });
      final q = await _service(client).questionForDate(DateTime(2026, 11, 18));
      expect(q.id, 'Q-CLEAN');
    });
  });
}
