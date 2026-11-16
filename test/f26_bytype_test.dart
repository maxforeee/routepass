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

/// F26 chunk 7 题型分布测试（F23 B2）：
/// - 后端 /bank/sets/{setId}/overview 新增 byType:{single,multiple}，
///   HttpBankSetOverviewSource 原样映射（旧后端无 byType → null，不编数）；
/// - HttpPracticeProgressOverviewSource：/practice/progress 命中模块时
///   total/done/remaining 仍取 progress，byType 改从 fallback 概览取；
///   fallback 失败 / 缺字段 / 未装配 → byType null（前置页“题型待接口”）；
/// - SQLite 缓存 byType 读写往返（-1 哨兵还原 null）；
/// - cache-first：byType 随概览进缓存，断网再读仍是真实分布；
/// - 前置页渲染真实“单选 X 题 / 多选 Y 题”；byType null → “题型待接口”。

const String _base = 'http://example.test';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: const <String, String>{
    'content-type': 'application/json; charset=utf-8',
  },
);

/// 后端 set_overview 契约 fixture（F26 chunk 7 起含 byType）。
Map<String, Object?> _overviewPayload({
  String setId = 'h3cne-2026-01',
  int total = 100,
  int done = 2,
  int single = 75,
  int multiple = 25,
  bool withByType = true,
}) => <String, Object?>{
  'setId': setId,
  'title': 'H3CNE 模拟卷 A',
  'total': total,
  'done': done,
  'remaining': total - done,
  'answered': 3,
  'correct': 2,
  'accuracy': 66.7,
  if (withByType)
    'byType': <String, Object?>{'single': single, 'multiple': multiple},
};

/// 套卷概览仓储替身：返回注入的真实值（或 null）。
class _OverviewRepo extends MockQuestionRepository {
  _OverviewRepo(this.overview);

  final BankSetOverview? overview;

  @override
  Future<BankSetOverview?> getSetOverview({required String setId}) async =>
      overview;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initTestServices();

  group('HttpBankSetOverviewSource（byType 契约）', () {
    test('200 带 byType：single/multiple 原样映射，和等于 total', () async {
      final source = HttpBankSetOverviewSource(
        baseUrl: _base,
        client: MockClient((request) async => _json(_overviewPayload())),
      );

      final overview = await source.fetchOverview('h3cne-2026-01');

      expect(overview, isNotNull);
      expect(overview!.byType, isNotNull);
      expect(overview.byType!.single, 75);
      expect(overview.byType!.multiple, 25);
      expect(overview.byType!.setId, 'h3cne-2026-01');
      expect(overview.byType!.total, overview.total);
    });

    test('旧后端无 byType 字段 → null，不编数', () async {
      final source = HttpBankSetOverviewSource(
        baseUrl: _base,
        client: MockClient(
          (request) async => _json(_overviewPayload(withByType: false)),
        ),
      );

      final overview = await source.fetchOverview('h3cne-2026-01');

      expect(overview, isNotNull);
      expect(overview!.total, 100);
      expect(overview.byType, isNull);
    });

    test('byType 显式为 null → null', () async {
      final payload = _overviewPayload()..['byType'] = null;
      final source = HttpBankSetOverviewSource(
        baseUrl: _base,
        client: MockClient((request) async => _json(payload)),
      );

      final overview = await source.fetchOverview('h3cne-2026-01');

      expect(overview!.byType, isNull);
    });
  });

  group('HttpPracticeProgressOverviewSource（byType 从 fallback 概览取）', () {
    const progressBody = <Object?>[
      <String, Object?>{
        'module': 'VLAN',
        'total': 130,
        'answered': 40,
        'remaining': 90,
      },
    ];

    test('progress 命中模块：数字取 progress，byType 取 fallback 概览', () async {
      final paths = <String>[];
      final source = HttpPracticeProgressOverviewSource(
        baseUrl: _base,
        fallback: HttpBankSetOverviewSource(
          baseUrl: _base,
          client: MockClient((request) async {
            paths.add(request.url.path);
            return _json(
              _overviewPayload(setId: 'VLAN', total: 130, single: 100, multiple: 30),
            );
          }),
        ),
        client: MockClient((request) async {
          paths.add(request.url.path);
          return _json(progressBody);
        }),
      );

      final overview = await source.fetchOverview('VLAN');

      expect(paths, contains('/api/v1/practice/progress'));
      expect(paths, contains('/api/v1/bank/sets/VLAN/overview'));
      expect(overview, isNotNull);
      expect(overview!.total, 130);
      expect(overview.done, 40);
      expect(overview.remaining, 90);
      expect(overview.byType, isNotNull);
      expect(overview.byType!.single, 100);
      expect(overview.byType!.multiple, 30);
    });

    test('fallback 404：progress 数字保留，byType null', () async {
      final source = HttpPracticeProgressOverviewSource(
        baseUrl: _base,
        fallback: HttpBankSetOverviewSource(
          baseUrl: _base,
          client: MockClient((request) async => _json(<String, Object?>{}, 404)),
        ),
        client: MockClient((request) async => _json(progressBody)),
      );

      final overview = await source.fetchOverview('VLAN');

      expect(overview!.total, 130);
      expect(overview.done, 40);
      expect(overview.remaining, 90);
      expect(overview.byType, isNull);
    });

    test('fallback 断网：progress 数字保留，byType null，不抛给 UI', () async {
      final source = HttpPracticeProgressOverviewSource(
        baseUrl: _base,
        fallback: HttpBankSetOverviewSource(
          baseUrl: _base,
          client: MockClient((request) async => throw Exception('offline')),
        ),
        client: MockClient((request) async => _json(progressBody)),
      );

      final overview = await source.fetchOverview('VLAN');

      expect(overview!.done, 40);
      expect(overview.byType, isNull);
    });

    test('未装配 fallback：byType null，不编数', () async {
      final source = HttpPracticeProgressOverviewSource(
        baseUrl: _base,
        client: MockClient((request) async => _json(progressBody)),
      );

      final overview = await source.fetchOverview('VLAN');

      expect(overview!.total, 130);
      expect(overview.byType, isNull);
    });

    test('fallback 概览无 byType（旧后端）→ null', () async {
      final source = HttpPracticeProgressOverviewSource(
        baseUrl: _base,
        fallback: HttpBankSetOverviewSource(
          baseUrl: _base,
          client: MockClient(
            (request) async =>
                _json(_overviewPayload(setId: 'VLAN', withByType: false)),
          ),
        ),
        client: MockClient((request) async => _json(progressBody)),
      );

      final overview = await source.fetchOverview('VLAN');

      expect(overview!.done, 40);
      expect(overview.byType, isNull);
    });

    test('progress 未命中（考试卷 id）：整体回落 fallback，byType 随行', () async {
      final source = HttpPracticeProgressOverviewSource(
        baseUrl: _base,
        fallback: HttpBankSetOverviewSource(
          baseUrl: _base,
          client: MockClient((request) async => _json(_overviewPayload())),
        ),
        client: MockClient((request) async => _json(progressBody)),
      );

      final overview = await source.fetchOverview('h3cne-2026-01');

      expect(overview!.setId, 'h3cne-2026-01');
      expect(overview.total, 100);
      expect(overview.done, 2);
      expect(overview.byType!.single, 75);
      expect(overview.byType!.multiple, 25);
    });
  });

  group('SQLite 缓存：byType 往返', () {
    setUpAll(sqfliteFfiInit);

    test('带题型分布的 overview 读写后一致', () async {
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
          byType: QuestionTypeStat(
            setId: 'h3cne-2026-01',
            single: 75,
            multiple: 25,
          ),
        ),
      );
      final value = await cache.readOverview('h3cne-2026-01');

      expect(value!.byType, isNotNull);
      expect(value.byType!.single, 75);
      expect(value.byType!.multiple, 25);
    });

    test('无题型分布的 overview 读回仍为 null（-1 哨兵不写成 0）', () async {
      final db = SqfliteLocalDatabase(
        dbPath: inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      );
      addTearDown(db.close);
      final cache = SqliteBankLocalCache(db);

      await cache.writeOverview(
        const BankSetOverview(setId: 'VLAN', total: 130, done: 40, remaining: 90),
      );
      final value = await cache.readOverview('VLAN');

      expect(value!.done, 40);
      expect(value.byType, isNull);
    });
  });

  group('cache-first：byType 随概览进缓存', () {
    test('断网再读命中缓存，题型分布仍是真实值', () async {
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
      expect(first!.byType!.single, 75);
      expect(first.byType!.multiple, 25);
      expect(requests, 1);

      offline = true;
      final second = await repo.getSetOverview(setId: 'h3cne-2026-01');
      expect(second!.byType!.single, 75);
      expect(second.byType!.multiple, 25);
      expect(requests, 1, reason: '缓存命中不应再发请求');
    });
  });

  group('SetDetailPage 渲染（真实题型分布，不编数）', () {
    testWidgets('考试前置页：单选 75 题 / 多选 25 题，不再显示题型待接口', (tester) async {
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
                byType: QuestionTypeStat(
                  setId: 'h3cne-2026-01',
                  single: 75,
                  multiple: 25,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('单选 75 题'), findsOneWidget);
      expect(find.text('多选 25 题'), findsOneWidget);
      expect(find.text('题型待接口'), findsNothing);
    });

    testWidgets('练习前置页：模块真实分布 单选 100 题 / 多选 30 题', (tester) async {
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
                total: 130,
                done: 40,
                remaining: 90,
                byType: QuestionTypeStat(
                  setId: 'VLAN',
                  single: 100,
                  multiple: 30,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('单选 100 题'), findsOneWidget);
      expect(find.text('多选 30 题'), findsOneWidget);
      expect(find.text('题型待接口'), findsNothing);
    });

    testWidgets('overview 就绪但 byType null：保留题型待接口 pill', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: SetDetailPage(
            args: <String, Object?>{
              'mode': 'exam',
              'drawCount': 100,
              'setId': 'h3cne-2026-01',
            },
            questionRepository: _OverviewRepo(
              const BankSetOverview(
                setId: 'h3cne-2026-01',
                total: 100,
                done: 2,
                remaining: 98,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('题型待接口'), findsOneWidget);
      expect(find.textContaining('单选'), findsNothing);
      expect(find.textContaining('多选'), findsNothing);
      // 完成情况仍走真实值，不受题型缺失影响。
      expect(find.text('已完成 2 题 · 剩余 98 题'), findsOneWidget);
    });

    testWidgets('overview 为 null（断网/未登录）：题型待接口，不写假数', (tester) async {
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

      expect(find.text('题型待接口'), findsOneWidget);
      expect(find.textContaining('单选'), findsNothing);
      expect(find.textContaining('多选'), findsNothing);
    });
  });
}