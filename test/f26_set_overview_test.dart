import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:routepass/core/local_db.dart';
import 'package:routepass/core/theme.dart';
import 'package:routepass/models/stats.dart';
import 'package:routepass/pages/bank/set_detail_page.dart';
import 'package:routepass/services/bank/cached_question_repository.dart';
import 'package:routepass/services/bank/local_cache_service.dart';
import 'package:routepass/services/bank/question_bank_source.dart';
import 'package:routepass/services/mock/mock_question_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'test_helpers.dart';

/// F26 chunk 6 套卷概览测试（F23 B1）：
/// - HttpBankSetOverviewSource 走真实 GET /bank/sets/{setId}/overview，
///   Bearer 附加，只解析后端真实返回的字段（缺字段不崩、多字段忽略）；
/// - 任何失败（404/401/500/断网/非 JSON）→ null，不抛给 UI；
/// - accuracy 0–100 → 模型 0–1；null（尚无作答）保持 null，不编 0%；
/// - SQLite 缓存 v2：accuracy 读写往返，未知仍是 null；
/// - cache-first：源成功后写缓存，断网再读仍返回真实值（含正确率）；
/// - 前置页渲染真实已完成/剩余/正确率；overview 为 null 或仓储抛错时
///   保留“完成情况待接口”，不写假数。

const String _base = 'http://example.test';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: const <String, String>{
    'content-type': 'application/json; charset=utf-8',
  },
);

/// 后端 set_overview 契约 fixture（F26 chunk 6）：done 按去重题数，
/// answered/correct 按 attempts 次数，accuracy 0–100 一位小数，
/// 尚无作答时 accuracy 为 null。byType 不在本 chunk（B2 另修）。
Map<String, Object?> _overviewPayload({
  String setId = 'h3cne-2026-01',
  int total = 100,
  int done = 2,
  int answered = 3,
  int correct = 2,
  Object? accuracy = 66.7,
}) => <String, Object?>{
  'setId': setId,
  'title': 'H3CNE 模拟卷 A',
  'total': total,
  'done': done,
  'remaining': total - done,
  'answered': answered,
  'correct': correct,
  'accuracy': accuracy,
};

/// 套卷概览仓储替身：返回注入的真实值（或 null）。
class _OverviewRepo extends MockQuestionRepository {
  _OverviewRepo(this.overview);

  final BankSetOverview? overview;

  @override
  Future<BankSetOverview?> getSetOverview({required String setId}) async =>
      overview;
}

/// 断网替身：getSetOverview 直接抛错，验证前置页不崩、保留待接口文案。
class _ThrowingRepo extends MockQuestionRepository {
  @override
  Future<BankSetOverview?> getSetOverview({required String setId}) async {
    throw Exception('offline');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initTestServices();

  group('HttpBankSetOverviewSource（真实端点契约）', () {
    test('200 真实契约：解析 total/done/remaining/正确率，带 Bearer 请求', () async {
      http.Request? seen;
      final source = HttpBankSetOverviewSource(
        baseUrl: _base,
        tokenProvider: () => 'tok-1',
        client: MockClient((request) async {
          seen = request;
          return _json(_overviewPayload());
        }),
      );

      final overview = await source.fetchOverview('h3cne-2026-01');

      expect(seen, isNotNull);
      expect(
        seen!.url.toString(),
        '$_base/api/v1/bank/sets/h3cne-2026-01/overview',
      );
      expect(seen!.headers['Authorization'], 'Bearer tok-1');
      expect(overview, isNotNull);
      expect(overview!.setId, 'h3cne-2026-01');
      expect(overview.total, 100);
      expect(overview.done, 2);
      expect(overview.remaining, 98);
      // 后端 0–100 → 模型 0–1 小数。
      expect(overview.accuracy, closeTo(0.667, 1e-9));
      // B2 不在本 chunk：后端不返回 byType，模型保持 null。
      expect(overview.byType, isNull);
    });

    test('setId 为中文模块名时 URL 编码', () async {
      http.Request? seen;
      final source = HttpBankSetOverviewSource(
        baseUrl: _base,
        client: MockClient((request) async {
          seen = request;
          return _json(_overviewPayload(setId: '基础知识', accuracy: null));
        }),
      );

      final overview = await source.fetchOverview('基础知识');

      expect(
        seen!.url.path,
        '/api/v1/bank/sets/${Uri.encodeComponent('基础知识')}/overview',
      );
      expect(overview!.setId, '基础知识');
    });

    test('缺字段不崩：只有 total/done/remaining → 正确率/题型 null', () async {
      final source = HttpBankSetOverviewSource(
        baseUrl: _base,
        client: MockClient(
          (request) async => _json(<String, Object?>{
            'setId': 'VLAN',
            'total': 100,
            'done': 0,
            'remaining': 100,
          }),
        ),
      );

      final overview = await source.fetchOverview('VLAN');

      expect(overview, isNotNull);
      expect(overview!.total, 100);
      expect(overview.done, 0);
      expect(overview.remaining, 100);
      expect(overview.accuracy, isNull, reason: '未知正确率不能编成 0');
      expect(overview.byType, isNull);
    });

    test('accuracy 为 null（尚无作答）保持 null，不编 0%', () async {
      final source = HttpBankSetOverviewSource(
        baseUrl: _base,
        client: MockClient(
          (request) async => _json(
            _overviewPayload(done: 0, answered: 0, correct: 0, accuracy: null),
          ),
        ),
      );

      final overview = await source.fetchOverview('h3cne-2026-01');

      expect(overview!.done, 0);
      expect(overview.accuracy, isNull);
    });

    test('多余字段忽略，不崩', () async {
      final payload = _overviewPayload()..['futureField'] = 'x';
      final source = HttpBankSetOverviewSource(
        baseUrl: _base,
        client: MockClient((request) async => _json(payload)),
      );

      final overview = await source.fetchOverview('h3cne-2026-01');

      expect(overview!.done, 2);
      expect(overview.accuracy, closeTo(0.667, 1e-9));
    });

    test('404（未知套卷）→ null', () async {
      final source = HttpBankSetOverviewSource(
        baseUrl: _base,
        client: MockClient(
          (request) async => _json(<String, Object?>{
            'error': <String, Object?>{'code': 'NOT_FOUND', 'message': '套卷不存在'},
          }, 404),
        ),
      );

      expect(await source.fetchOverview('不存在的套卷'), isNull);
    });

    test('401（未登录）→ null', () async {
      final source = HttpBankSetOverviewSource(
        baseUrl: _base,
        client: MockClient((request) async => _json(<String, Object?>{}, 401)),
      );

      expect(await source.fetchOverview('h3cne-2026-01'), isNull);
    });

    test('500 → null', () async {
      final source = HttpBankSetOverviewSource(
        baseUrl: _base,
        client: MockClient((request) async => _json(<String, Object?>{}, 500)),
      );

      expect(await source.fetchOverview('h3cne-2026-01'), isNull);
    });

    test('非 JSON 响应 → null', () async {
      final source = HttpBankSetOverviewSource(
        baseUrl: _base,
        client: MockClient(
          (request) async => http.Response('<html>502</html>', 200),
        ),
      );

      expect(await source.fetchOverview('h3cne-2026-01'), isNull);
    });

    test('JSON 数组（形状不认识）→ null', () async {
      final source = HttpBankSetOverviewSource(
        baseUrl: _base,
        client: MockClient((request) async => _json(<Object?>[1, 2])),
      );

      expect(await source.fetchOverview('h3cne-2026-01'), isNull);
    });

    test('网络异常 → null，不抛给 UI', () async {
      final source = HttpBankSetOverviewSource(
        baseUrl: _base,
        client: MockClient((request) async => throw Exception('offline')),
      );

      expect(await source.fetchOverview('h3cne-2026-01'), isNull);
    });

    test('未登录（无 token）不带 Authorization 头', () async {
      http.Request? seen;
      final source = HttpBankSetOverviewSource(
        baseUrl: _base,
        client: MockClient((request) async {
          seen = request;
          return _json(_overviewPayload(), 401);
        }),
      );

      expect(await source.fetchOverview('h3cne-2026-01'), isNull);
      expect(seen!.headers.containsKey('Authorization'), isFalse);
    });
  });

  group('SQLite 缓存 v2：accuracy 往返', () {
    setUpAll(sqfliteFfiInit);

    test('带正确率的 overview 读写后一致', () async {
      final db = SqfliteLocalDatabase(
        dbPath: inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      );
      addTearDown(db.close);
      final cache = SqliteBankLocalCache(db);

      await cache.writeOverview(
        const BankSetOverview(
          setId: 'h3cne-2026-01',
          total: 100,
          done: 2,
          remaining: 98,
          accuracy: 0.667,
        ),
      );
      final value = await cache.readOverview('h3cne-2026-01');

      expect(value!.done, 2);
      expect(value.remaining, 98);
      expect(value.accuracy, closeTo(0.667, 1e-9));
    });

    test('无正确率的 overview 读回仍为 null（未知不写 0）', () async {
      final db = SqfliteLocalDatabase(
        dbPath: inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      );
      addTearDown(db.close);
      final cache = SqliteBankLocalCache(db);

      await cache.writeOverview(
        const BankSetOverview(
          setId: 'VLAN',
          total: 100,
          done: 12,
          remaining: 88,
        ),
      );
      final value = await cache.readOverview('VLAN');

      expect(value!.done, 12);
      expect(value.accuracy, isNull);
    });
  });

  group('cache-first：源成功写缓存，断网再读仍是真实值', () {
    test('第二次读命中缓存（含正确率），不再发请求', () async {
      var offline = false;
      var requests = 0;
      final source = HttpBankSetOverviewSource(
        baseUrl: _base,
        client: MockClient((request) async {
          requests++;
          if (offline) throw Exception('offline');
          return _json(_overviewPayload());
        }),
      );
      final repo = CachedQuestionRepository(
        delegate: MockQuestionRepository(),
        cache: InMemoryBankLocalCache(),
        overviewSource: source,
        backgroundRefresh: false,
      );

      final first = await repo.getSetOverview(setId: 'h3cne-2026-01');
      expect(first!.done, 2);
      expect(first.accuracy, closeTo(0.667, 1e-9));
      expect(requests, 1);

      offline = true;
      final second = await repo.getSetOverview(setId: 'h3cne-2026-01');
      expect(second!.done, 2);
      expect(second.remaining, 98);
      expect(second.accuracy, closeTo(0.667, 1e-9));
      expect(requests, 1, reason: '缓存命中不应再发请求');
    });
  });

  group('SetDetailPage 渲染（真实概览，不编数）', () {
    testWidgets('考试前置页：真实已完成/剩余 + 真实正确率', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: SetDetailPage(
            args: <String, Object?>{
              'mode': 'exam',
              'drawCount': 100,
              'setId': 'h3cne-2026-01',
              'setTitle': 'A卷',
            },
            questionRepository: _OverviewRepo(
              const BankSetOverview(
                setId: 'h3cne-2026-01',
                total: 100,
                done: 2,
                remaining: 98,
                accuracy: 0.667,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('已完成 2 题 · 剩余 98 题'), findsOneWidget);
      expect(find.text('正确率 66.7%'), findsOneWidget);
      expect(find.text('完成情况待接口'), findsNothing);
      expect(find.text('正确率待接口'), findsNothing);
    });

    testWidgets('练习前置页：已答题数真实值；无正确率数据显示待接口', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: SetDetailPage(
            args: <String, Object?>{
              'mode': 'practice',
              'drawCount': 100,
              'setId': 'VLAN',
              'setTitle': 'VLAN',
            },
            questionRepository: _OverviewRepo(
              const BankSetOverview(
                setId: 'VLAN',
                total: 650,
                done: 120,
                remaining: 530,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('已答题数：120'), findsOneWidget);
      expect(find.text('正确率待接口'), findsOneWidget);
      expect(find.textContaining('正确率 0'), findsNothing);
    });

    testWidgets('overview 为 null：保留完成情况待接口，不写假数', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: SetDetailPage(
            args: <String, Object?>{
              'mode': 'exam',
              'drawCount': 100,
              'setId': 'h3cne-2026-01',
            },
            questionRepository: _OverviewRepo(null),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('完成情况待接口'), findsOneWidget);
      expect(find.textContaining('正确率'), findsNothing);
      expect(find.textContaining('已完成 0'), findsNothing);
    });

    testWidgets('仓储抛错（断网）：页面不崩，保留待接口文案', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: SetDetailPage(
            args: <String, Object?>{
              'mode': 'exam',
              'drawCount': 100,
              'setId': 'h3cne-2026-01',
            },
            questionRepository: _ThrowingRepo(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SetDetailPage), findsOneWidget);
      expect(find.text('完成情况待接口'), findsOneWidget);
      expect(find.text('开始答题'), findsOneWidget);
    });
  });
}
