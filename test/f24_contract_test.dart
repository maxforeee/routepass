/// F24：F23 审计的三个阻断项契约回归。
///
/// - B5：`POST /practice/submit` 上传 0 基下标 `answer` + `durationSec` +
///   ≤40 字符 `opId`，返回的下标数组要转成选项 key（旧实现按 String 强转
///   直接抛异常，回落 Mock 把每次作答都记成“未判分”）；
/// - B6：会话 / 记录的 `startedAt`、`completedAt` 是 ISO 字符串；
/// - A8/B7/B14：考试真开考、逐题暂存与交卷形状、交卷后逐题判分详情。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:routepass/core/kv_store.dart';
import 'package:routepass/services/bank/cached_practice_service.dart';
import 'package:routepass/services/bank/local_cache_service.dart';
import 'package:routepass/services/bank/practice_service.dart';
import 'package:routepass/services/bank/sync_http_service.dart';
import 'package:routepass/services/mock/mock_practice_service.dart';

const String _base = 'http://example.test';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: const <String, String>{
    'content-type': 'application/json; charset=utf-8',
  },
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('F24 B5 练习提交契约', () {
    test('上传 answer 下标数组 + durationSec，不再发 chosen/durationMs', () async {
      late Map<String, dynamic> sent;
      final client = MockClient((request) async {
        expect(request.url.path, '/api/v1/practice/submit');
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return _json(<String, Object?>{
          'accepted': 1,
          'duplicated': 0,
          'rejected': 0,
          'opId': 'op-1',
          'questionId': 'VLAN-0007',
          'correct': true,
          'answer': <int>[0, 2],
        });
      });
      final service = HttpPracticeService(client: client, baseUrl: _base);

      final result = await service.submitAnswer(
        sessionId: 'sess-9',
        questionId: 'VLAN-0007',
        chosen: <String>['A', 'C'],
        durationMs: 12500,
        setId: 'VLAN',
        opId: 'op-1',
      );

      expect(sent['answer'], <int>[0, 2], reason: 'S11 answer 是 0 基下标数组');
      expect(sent['durationSec'], 12, reason: 'S11 用秒，不是毫秒');
      expect(sent.containsKey('chosen'), isFalse);
      expect(sent.containsKey('durationMs'), isFalse);
      expect(sent['opId'], 'op-1');
      expect(result.correct, isTrue);
      expect(result.correctKeys, <String>['A', 'C']);
    });

    test('返回的下标数组转成选项 key（不再 String 强转抛异常）', () async {
      final client = MockClient(
        (_) async => _json(<String, Object?>{
          'accepted': 1,
          'correct': false,
          'answer': <int>[1, 2],
          'opId': 'op-2',
        }),
      );
      final service = HttpPracticeService(client: client, baseUrl: _base);

      final result = await service.submitAnswer(
        sessionId: 'sess-9',
        questionId: 'VLAN-0007',
        chosen: <String>['A'],
        durationMs: 1000,
        opId: 'op-2',
      );

      expect(result.correct, isFalse);
      expect(result.correctKeys, <String>['B', 'C']);
      expect(result.opId, 'op-2');
    });

    test('下标数组响应不回落 Mock：判分与答案键都来自服务端', () async {
      final client = MockClient(
        (_) async => _json(<String, Object?>{
          'accepted': 1,
          'correct': true,
          'answer': <int>[1],
        }),
      );
      final service = HttpPracticeService(
        client: client,
        baseUrl: _base,
        fallback: MockPracticeService(),
      );

      final result = await service.submitAnswer(
        sessionId: 'sess-9',
        questionId: 'VLAN-0007',
        chosen: <String>['B'],
        durationMs: 1000,
        opId: 'op-3',
      );

      expect(result.correct, isTrue, reason: 'Mock 不判分，回落即说明解析炸了');
      expect(result.correctKeys, <String>['B']);
    });

    test('opId 缺省时补全，超长时截到 40 字符且保持稳定', () async {
      final bodies = <Map<String, dynamic>>[];
      final client = MockClient((request) async {
        bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        return _json(<String, Object?>{'accepted': 1, 'correct': true});
      });
      final service = HttpPracticeService(client: client, baseUrl: _base);

      Future<void> submit(String? opId) => service.submitAnswer(
        sessionId: 'pr_20261115_001',
        questionId: 'VLAN-0007',
        chosen: <String>['A'],
        durationMs: 1000,
        opId: opId,
      );

      await submit(null);
      await submit('op-${'x' * 60}');
      await submit('op-${'x' * 60}');

      expect(bodies[0]['opId'], 'pr_20261115_001-VLAN-0007');
      for (final body in bodies) {
        final opId = body['opId'] as String?;
        expect(opId, isNotNull, reason: 'opId 必填，缺了服务端直接 rejected');
        expect(opId!.length, lessThanOrEqualTo(40));
        expect(opId, isNotEmpty);
      }
      expect(bodies[1]['opId'], bodies[2]['opId'], reason: '幂等键必须稳定');
    });

    test('durationMs 为负 / 不足一秒时 durationSec 不为负', () async {
      late Map<String, dynamic> sent;
      final client = MockClient((request) async {
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return _json(<String, Object?>{'accepted': 1, 'correct': true});
      });
      final service = HttpPracticeService(client: client, baseUrl: _base);

      await service.submitAnswer(
        sessionId: 'sess-9',
        questionId: 'VLAN-0007',
        chosen: <String>['A'],
        durationMs: -5,
        opId: 'op-4',
      );
      expect(sent['durationSec'], 0);

      await service.submitAnswer(
        sessionId: 'sess-9',
        questionId: 'VLAN-0007',
        chosen: <String>['A'],
        durationMs: 999,
        opId: 'op-5',
      );
      expect(sent['durationSec'], 0);
    });
  });

  group('F24 B5 离线作答队列上传契约', () {
    test('sync/push 的 attempts.answer 是下标数组、durationSec 是秒', () async {
      final cache = InMemoryBankLocalCache();
      await cache.enqueueSync(
        LocalSyncOp(
          opId: 'answer-VLAN-q1-1700000000000',
          kind: LocalSyncOp.kindPracticeAnswer,
          createdAt: 1700000000000,
          payload: const <String, Object?>{
            'setId': 'VLAN',
            'questionId': 'q1',
            'chosen': <String>['A', 'C'],
            'durationMs': 12500,
            'mode': 'practice',
          },
        ),
      );
      late Map<String, dynamic> change;
      final client = MockClient((request) async {
        expect(request.url.path, '/api/v1/sync/push');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        change =
            (body['changes'] as List<dynamic>).first as Map<String, dynamic>;
        return _json(<String, Object?>{
          'accepted': 1,
          'duplicated': 0,
          'rejected': 0,
          'results': <Object?>[
            <String, Object?>{'opId': change['opId'], 'status': 'accepted'},
          ],
        });
      });
      final service = HttpSyncService(
        client: client,
        baseUrl: _base,
        tokenProvider: () => 'token-1',
        kvStore: InMemoryKvStore(),
        localCache: cache,
      );

      final result = await service.pushPendingOps();

      expect(result.pushedCount, 1);
      final data = change['data'] as Map<String, dynamic>;
      expect(data['answer'], <int>[0, 2], reason: '字母数组会被服务端判成错答');
      expect(data['durationSec'], 12);
      expect((change['opId'] as String).length, lessThanOrEqualTo(40));
      expect(await cache.pendingSync(), isEmpty);
    });

    test('练习作答全链路：服务端判分落本地，队列上传仍是下标数组', () async {
      final cache = InMemoryBankLocalCache();
      final practiceClient = MockClient(
        (_) async => _json(<String, Object?>{
          'accepted': 1,
          'correct': true,
          'answer': <int>[0, 2],
          'opId': 'op-chain',
        }),
      );
      final practice = CachedPracticeService(
        delegate: HttpPracticeService(client: practiceClient, baseUrl: _base),
        cache: cache,
      );

      final result = await practice.submitAnswer(
        sessionId: 'sess-9',
        questionId: 'VLAN-0007',
        chosen: <String>['A', 'C'],
        durationMs: 12500,
        setId: 'VLAN',
        opId: 'op-chain',
      );

      expect(result.correct, isTrue);
      expect(result.correctKeys, <String>['A', 'C']);
      expect(await cache.answeredQuestionIds('VLAN'), contains('VLAN-0007'));

      late Map<String, dynamic> data;
      final syncClient = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final change =
            (body['changes'] as List<dynamic>).first as Map<String, dynamic>;
        data = change['data'] as Map<String, dynamic>;
        return _json(<String, Object?>{
          'accepted': 1,
          'results': <Object?>[
            <String, Object?>{'opId': change['opId'], 'status': 'accepted'},
          ],
        });
      });
      final sync = HttpSyncService(
        client: syncClient,
        baseUrl: _base,
        tokenProvider: () => 'token-1',
        kvStore: InMemoryKvStore(),
        localCache: cache,
      );

      expect((await sync.pushPendingOps()).pushedCount, 1);
      expect(data['answer'], <int>[0, 2]);
      expect(data['durationSec'], 12);
    });
  });
}
