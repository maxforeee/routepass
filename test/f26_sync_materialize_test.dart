/// F26 chunk 4（F23 B9）：手动同步把拉取结果物化进本地 store。
///
/// 守护点：
/// - 错题 / 收藏经 GET /wrong-book、GET /favorites（带题目内容的列表接口）
///   并入本地 store，答题记录复用既有 syncFromServer 合并；
/// - last-write-wins：更旧的服务端条目不覆盖更新的本地条目；
/// - 本地无数据 + 服务端有数据仍然只拉不推（物化不触发上传）；
/// - 某一类别拉取失败必须报「未更新」，不能算成已应用；
/// - 没有可用 store 时保留旧的「拉取到镜像（应用数据待接口）」文案。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:routepass/core/kv_store.dart';
import 'package:routepass/models/practice.dart';
import 'package:routepass/models/wrong_favorite.dart';
import 'package:routepass/services/bank/answer_record_service.dart';
import 'package:routepass/services/bank/local_cache_service.dart';
import 'package:routepass/services/bank/sync_http_service.dart';
import 'package:routepass/services/mock/mock_favorite_service.dart';
import 'package:routepass/services/mock/mock_wrong_service.dart';

void main() {
  group('syncNow 物化（F26 B9）', () {
    test('拉取后错题 / 收藏 / 答题记录都进本地 store，文案按类别报告', () async {
      final kv = InMemoryKvStore();
      final wrong = MockWrongService();
      final favorites = MockFavoriteService();
      final records = KvAnswerRecordService(
        kvStore: kv,
        serverRecords: () async => <PracticeRecordSummary>[_summary()],
      );
      final service = _service(
        _client(wrongItems: _wrongItems(), favoriteItems: _favoriteItems()),
        kv: kv,
        wrong: wrong,
        favorites: favorites,
        records: records,
      );

      final result = await service.syncNow();

      expect(result.ok, isTrue);
      final wrongBook = await wrong.getWrongBook();
      final materializedWrong = wrongBook.firstWhere(
        (item) => item.question_id == 'VLAN-0001',
      );
      expect(materializedWrong.wrong_count, 3);
      expect(materializedWrong.mastered, isFalse);
      final favoriteList = await favorites.getFavorites();
      expect(
        favoriteList.map((item) => item.question_id),
        contains('VLAN-0002'),
      );
      expect(
        records.recordsFor(setId: 'VLAN', mode: 'practice').map((r) => r.id),
        contains('srv-sess-1'),
      );
      expect(result.message, contains('错题本已更新 1 条'));
      expect(result.message, contains('收藏已更新 1 条'));
      expect(result.message, contains('答题记录已更新'));
      expect(result.message, isNot(contains('应用数据待接口')));
      // 镜像保留作审计痕迹。
      expect(kv.getString(KvStore.keySyncMirror), isNotNull);
    });

    test('last-write-wins：更旧的服务端条目不覆盖更新的本地条目', () async {
      final kv = InMemoryKvStore();
      final wrong = MockWrongService();
      final favorites = MockFavoriteService();
      final localNewer = DateTime.utc(2026, 11, 15).millisecondsSinceEpoch;
      await wrong.mergeFromServer(<WrongItem>[
        WrongItem(
          question_id: 'VLAN-0001',
          wrong_count: 9,
          last_wrong_at: localNewer,
          mastered: false,
        ),
      ]);
      await favorites.mergeFromServer(<Favorite>[
        Favorite(question_id: 'VLAN-0002', created_at: localNewer),
      ]);
      final service = _service(
        // 服务端条目停留在 2026-11-14，比本地 2026-11-15 更旧。
        _client(wrongItems: _wrongItems(), favoriteItems: _favoriteItems()),
        kv: kv,
        wrong: wrong,
        favorites: favorites,
        records: KvAnswerRecordService(kvStore: kv),
      );

      final result = await service.syncNow();

      final kept = (await wrong.getWrongBook()).firstWhere(
        (item) => item.question_id == 'VLAN-0001',
      );
      expect(kept.wrong_count, 9);
      expect(kept.last_wrong_at, localNewer);
      final keptFavorite = (await favorites.getFavorites()).firstWhere(
        (item) => item.question_id == 'VLAN-0002',
      );
      expect(keptFavorite.created_at, localNewer);
      expect(result.message, contains('错题本已更新 0 条'));
      expect(result.message, contains('收藏已更新 0 条'));
    });

    test('更新的服务端条目覆盖更旧的本地条目', () async {
      final kv = InMemoryKvStore();
      final wrong = MockWrongService();
      final favorites = MockFavoriteService();
      final localOlder = DateTime.utc(2026, 11, 13).millisecondsSinceEpoch;
      await wrong.mergeFromServer(<WrongItem>[
        WrongItem(
          question_id: 'VLAN-0001',
          wrong_count: 1,
          last_wrong_at: localOlder,
          mastered: false,
        ),
      ]);
      await favorites.mergeFromServer(<Favorite>[
        Favorite(question_id: 'VLAN-0002', created_at: localOlder),
      ]);
      final service = _service(
        _client(wrongItems: _wrongItems(), favoriteItems: _favoriteItems()),
        kv: kv,
        wrong: wrong,
        favorites: favorites,
        records: KvAnswerRecordService(kvStore: kv),
      );

      final result = await service.syncNow();

      final updated = (await wrong.getWrongBook()).firstWhere(
        (item) => item.question_id == 'VLAN-0001',
      );
      expect(updated.wrong_count, 3);
      expect(
        updated.last_wrong_at,
        DateTime.parse('2026-11-14T09:04:00+08:00').millisecondsSinceEpoch,
      );
      final updatedFavorite = (await favorites.getFavorites()).firstWhere(
        (item) => item.question_id == 'VLAN-0002',
      );
      expect(
        updatedFavorite.created_at,
        DateTime.parse('2026-11-14T08:00:00+08:00').millisecondsSinceEpoch,
      );
      expect(result.message, contains('错题本已更新 1 条'));
      expect(result.message, contains('收藏已更新 1 条'));
    });

    test('本地无数据 + 服务端有数据：物化后仍然只拉不推', () async {
      final kv = InMemoryKvStore();
      final paths = <String>[];
      final wrong = MockWrongService();
      final service = _service(
        _client(
          paths: paths,
          wrongItems: _wrongItems(),
          favoriteItems: _favoriteItems(),
        ),
        kv: kv,
        wrong: wrong,
        favorites: MockFavoriteService(),
        records: KvAnswerRecordService(
          kvStore: kv,
          serverRecords: () async => <PracticeRecordSummary>[_summary()],
        ),
      );

      final result = await service.syncNow();

      expect(result.ok, isTrue);
      expect(result.uploadedCount, 0);
      expect(result.state, 'synced');
      expect(paths, isNot(contains('/api/v1/sync/push')));
      // 物化确实发生，但没有因此打开上传闸门。
      expect(
        (await wrong.getWrongBook()).map((item) => item.question_id),
        contains('VLAN-0001'),
      );
      expect(result.message, contains('本地无数据'));
    });

    test('错题本拉取失败报「未更新」，其余类别照常物化', () async {
      final kv = InMemoryKvStore();
      final wrong = MockWrongService();
      final service = _service(
        _client(
          failWrong: true,
          wrongItems: _wrongItems(),
          favoriteItems: _favoriteItems(),
        ),
        kv: kv,
        wrong: wrong,
        favorites: MockFavoriteService(),
        records: KvAnswerRecordService(
          kvStore: kv,
          serverRecords: () async => <PracticeRecordSummary>[_summary()],
        ),
      );

      final result = await service.syncNow();

      expect(result.message, contains('错题本未更新（拉取失败）'));
      expect(result.message, isNot(contains('错题本已更新')));
      expect(result.message, contains('收藏已更新 1 条'));
      expect(result.message, contains('答题记录已更新'));
      expect(
        (await wrong.getWrongBook()).map((item) => item.question_id),
        isNot(contains('VLAN-0001')),
      );
    });

    test('收藏拉取失败报「未更新」，错题照常物化', () async {
      final kv = InMemoryKvStore();
      final favorites = MockFavoriteService();
      final service = _service(
        _client(
          failFavorites: true,
          wrongItems: _wrongItems(),
          favoriteItems: _favoriteItems(),
        ),
        kv: kv,
        wrong: MockWrongService(),
        favorites: favorites,
        records: KvAnswerRecordService(kvStore: kv),
      );

      final result = await service.syncNow();

      expect(result.message, contains('收藏未更新（拉取失败）'));
      expect(result.message, isNot(contains('收藏已更新')));
      expect(result.message, contains('错题本已更新 1 条'));
      expect(
        (await favorites.getFavorites()).map((item) => item.question_id),
        isNot(contains('VLAN-0002')),
      );
    });

    test('答题记录接口失败报「未更新」，且不再触发记录合并', () async {
      final kv = InMemoryKvStore();
      var recordsFetched = false;
      final records = KvAnswerRecordService(
        kvStore: kv,
        serverRecords: () async {
          recordsFetched = true;
          return <PracticeRecordSummary>[_summary()];
        },
      );
      final service = _service(
        _client(
          failRecords: true,
          wrongItems: _wrongItems(),
          favoriteItems: _favoriteItems(),
        ),
        kv: kv,
        wrong: MockWrongService(),
        favorites: MockFavoriteService(),
        records: records,
      );

      final result = await service.syncNow();

      expect(result.message, contains('答题记录未更新（拉取失败）'));
      expect(result.message, isNot(contains('答题记录已更新')));
      expect(result.message, contains('错题本已更新 1 条'));
      expect(recordsFetched, isFalse);
      expect(records.recordsFor(setId: 'VLAN', mode: 'practice'), isEmpty);
    });

    test('本地墓碑不被更旧的服务端条目复活', () async {
      final kv = InMemoryKvStore();
      final wrong = MockWrongService();
      final tombstone = DateTime.utc(2026, 11, 14, 10).millisecondsSinceEpoch;
      await wrong.mergeFromServer(<WrongItem>[
        WrongItem(
          question_id: 'VLAN-0001',
          wrong_count: 1,
          last_wrong_at: DateTime.utc(2026, 11, 14, 9).millisecondsSinceEpoch,
          mastered: false,
          removed_at: tombstone,
        ),
      ]);
      final service = _service(
        // 服务端 lastWrongAt 09:04 早于移除时刻 10:00 → 不复活。
        _client(wrongItems: _wrongItems(), favoriteItems: _favoriteItems()),
        kv: kv,
        wrong: wrong,
        favorites: MockFavoriteService(),
        records: KvAnswerRecordService(kvStore: kv),
      );

      final result = await service.syncNow();

      expect(result.message, contains('错题本已更新 0 条'));
    });

    test('没有可用 store 时保留旧的镜像文案，不发列表请求', () async {
      final kv = InMemoryKvStore();
      final paths = <String>[];
      // 不注入 store，本文件也不注册 ServiceLocator → 三个类别都跳过。
      final service = _service(_client(paths: paths), kv: kv);

      final result = await service.syncNow();

      expect(result.ok, isTrue);
      expect(result.uploadedCount, 0);
      expect(result.message, contains('到同步镜像'));
      expect(result.message, contains('应用数据待接口'));
      expect(paths, isNot(contains('/api/v1/wrong-book')));
      expect(paths, isNot(contains('/api/v1/favorites')));
      expect(paths, isNot(contains('/api/v1/practice/records')));
    });
  });
}

HttpSyncService _service(
  http.Client client, {
  required InMemoryKvStore kv,
  MockWrongService? wrong,
  MockFavoriteService? favorites,
  AnswerRecordService? records,
}) {
  return HttpSyncService(
    client: client,
    baseUrl: 'http://test',
    tokenProvider: () => 'token-1',
    kvStore: kv,
    localCache: InMemoryBankLocalCache(),
    wrongService: wrong,
    favoriteService: favorites,
    answerRecordService: records,
  );
}

MockClient _client({
  List<String>? paths,
  bool failWrong = false,
  bool failFavorites = false,
  bool failRecords = false,
  List<Map<String, Object?>> wrongItems = const <Map<String, Object?>>[],
  List<Map<String, Object?>> favoriteItems = const <Map<String, Object?>>[],
}) {
  return MockClient((request) async {
    paths?.add(request.url.path);
    switch (request.url.path) {
      case '/api/v1/sync/baseline':
        return _json(200, _baselineJson());
      case '/api/v1/sync/pull':
        return _json(200, _pullJson());
      case '/api/v1/wrong-book':
        return failWrong
            ? _json(500, <String, Object?>{})
            : _json(200, _listJson(wrongItems));
      case '/api/v1/favorites':
        return failFavorites
            ? _json(500, <String, Object?>{})
            : _json(200, _listJson(favoriteItems));
      case '/api/v1/practice/records':
        return failRecords
            ? _json(404, <String, Object?>{})
            : _json(200, _listJson(<Map<String, Object?>>[_recordJson()]));
      case '/api/v1/sync/push':
        return _json(200, <String, Object?>{'results': <Object?>[]});
      default:
        return _json(404, <String, Object?>{});
    }
  });
}

http.Response _json(int statusCode, Object body) {
  return http.Response(
    jsonEncode(body),
    statusCode,
    headers: <String, String>{
      'content-type': 'application/json; charset=utf-8',
    },
  );
}

Map<String, Object?> _listJson(List<Map<String, Object?>> items) {
  return <String, Object?>{
    'items': items,
    'page': 1,
    'pageSize': 100,
    'total': items.length,
  };
}

List<Map<String, Object?>> _wrongItems() {
  return <Map<String, Object?>>[
    <String, Object?>{
      'questionId': 'VLAN-0001',
      'wrongCount': 3,
      'lastWrongAt': '2026-11-14T09:04:00+08:00',
      'mastered': false,
      'question': <String, Object?>{
        'id': 'VLAN-0001',
        'module': 'VLAN',
        'stem': '示例题干',
      },
    },
  ];
}

List<Map<String, Object?>> _favoriteItems() {
  return <Map<String, Object?>>[
    <String, Object?>{
      'questionId': 'VLAN-0002',
      'createdAt': '2026-11-14T08:00:00+08:00',
      'question': <String, Object?>{
        'id': 'VLAN-0002',
        'module': 'VLAN',
        'stem': '示例题干',
      },
    },
  ];
}

Map<String, Object?> _recordJson() {
  return <String, Object?>{
    'id': 'sess-1',
    'module': 'VLAN',
    'status': 'completed',
    'answeredCount': 20,
    'correctCount': 18,
    'startedAt': '2026-11-14T09:00:00+08:00',
    'completedAt': '2026-11-14T09:30:00+08:00',
  };
}

PracticeRecordSummary _summary() {
  return PracticeRecordSummary(
    id: 'sess-1',
    module: 'VLAN',
    status: 'completed',
    answeredCount: 20,
    correctCount: 18,
    startedAt: DateTime.parse(
      '2026-11-14T09:00:00+08:00',
    ).millisecondsSinceEpoch,
    completedAt: DateTime.parse(
      '2026-11-14T09:30:00+08:00',
    ).millisecondsSinceEpoch,
  );
}

Map<String, Object?> _pullJson() {
  return <String, Object?>{
    'changes': <Object?>[
      <String, Object?>{
        'txid': 101,
        'entity': 'wrong_book',
        'entityId': 'q1',
        'op': 'upsert',
        'data': <String, Object?>{
          'questionId': 'q1',
          'wrongCount': 2,
          'mastered': false,
          'clientAt': '2026-11-14T09:04:00+08:00',
        },
        'clientAt': '2026-11-14T09:04:00+08:00',
      },
    ],
    'nextCursor': 101,
    'watermark': 101,
    'hasMore': false,
    'serverTime': '2026-11-14T09:05:00+08:00',
    'baselineRequired': false,
  };
}

Map<String, Object?> _baselineJson() {
  return <String, Object?>{
    'source': 'live',
    'txidWatermark': 101,
    'generatedAt': '2026-11-14T09:05:00+08:00',
    'wrongBook': <Object?>[
      <String, Object?>{
        'questionId': 'q1',
        'wrongCount': 2,
        'lastWrongAt': '2026-11-14T09:04:00+08:00',
        'mastered': false,
      },
    ],
    'favorites': <Object?>[
      <String, Object?>{
        'questionId': 'f1',
        'createdAt': '2026-11-13T09:04:00+08:00',
      },
    ],
    'userKv': <Object?>[],
    'dailyStats': <Object?>[],
  };
}
