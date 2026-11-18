/// F35 套卷详情「知识点考察」题量必须来自本套卷接口（byModule）。
///
/// 修复前的 bug：_moduleCount 回退到 GET /bank/modules 的全库总量，
/// 100 题的 ACL 练习集里 ACL 误显 140（100 练习 + 20×2 考试卷）。
/// 修复后：题量只认本套卷概览 byModule——在映射 = 真实题量，不在 = 真 0；
/// 概览未就绪保留诚实兜底（清单 / 题量待接口），绝不用全库总量。
///
/// 覆盖：
/// - byModule={ACL:100}：ACL 显 100，其余模块显 0，全库 140 绝不出现；
/// - 考试卷 byModule 每模块 20：逐模块真实拆分；
/// - overview 为 null：五行「题量待接口」，全库总量绝不出现；
/// - overview 为 null + 重叠清单（F35 chunk 2 门禁）：考试卷五行待接口，
///   绝不借练习集题量；ACL 练习集仅 ACL 行取清单 100，其余模块待接口；
/// - 模型防御性解析：缺字段 / 非法值 → null，toJson 往返；
/// - HttpPracticeProgressOverviewSource：byModule 从 fallback 概览合并；
/// - SQLite 缓存 v3：byModule 读写往返（cache-first 命中不丢字段）。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:routepass/core/local_db.dart';
import 'package:routepass/core/theme.dart';
import 'package:routepass/models/bank_manifest.dart';
import 'package:routepass/models/stats.dart';
import 'package:routepass/pages/bank/set_detail_page.dart';
import 'package:routepass/services/bank/bank_manifest_service.dart';
import 'package:routepass/services/bank/local_cache_service.dart';
import 'package:routepass/services/bank/question_bank_source.dart';
import 'package:routepass/services/bank/set_detail_preload.dart';
import 'package:routepass/services/mock/mock_bank_manifest_service.dart';
import 'package:routepass/services/mock/mock_question_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'test_helpers.dart';

/// 全库模块总量 fixture：刻意与套卷内题量不同（ACL 全库 140，对应线上
/// 100 练习 + 20×2 考试卷），用来证明这些全库数字绝不进「知识点考察」。
const List<ModuleStat> _wholeBankModules = <ModuleStat>[
  ModuleStat(module: 'VLAN', total: 120, answered: 0, correctRate: 0.0),
  ModuleStat(module: 'OSPF', total: 130, answered: 0, correctRate: 0.0),
  ModuleStat(module: 'ACL', total: 140, answered: 0, correctRate: 0.0),
  ModuleStat(module: 'NAT', total: 90, answered: 0, correctRate: 0.0),
  ModuleStat(module: 'SUBNET', total: 110, answered: 0, correctRate: 0.0),
];

/// 2026-11-14 实测线上清单（与 set_detail_test.dart 的 _liveManifestJson
/// 同一份数据）：practiceByModule 与 kModuleOrder 重叠 VLAN / OSPF / ACL
/// 各 100 题，NAT / SUBNET 无数据。用来证明概览未就绪时清单兜底只认
/// 本页练习集，别的模块 / 考试卷绝不借用这些练习池题量。
const Map<String, dynamic> _overlapManifestJson = <String, dynamic>{
  'bankId': 'bank_default',
  'version': '1.0.0',
  'questionCount': 650,
  'exams': <Map<String, dynamic>>[
    <String, dynamic>{
      'id': 'h3cne-2026-01',
      'title': 'H3CNE 模拟卷 A',
      'questionCount': 100,
    },
    <String, dynamic>{
      'id': 'h3cne-2026-02',
      'title': 'H3CNE 模拟卷 B',
      'questionCount': 100,
    },
  ],
  'practiceByModule': <String, dynamic>{
    'ACL': 100,
    'H3CNE': 100,
    'OSPF': 100,
    'VLAN': 100,
    '基础知识': 50,
  },
};

/// 可控仓储替身：getModules 返回全库总量，getSetOverview 返回注入概览。
class _CountsRepo extends MockQuestionRepository {
  _CountsRepo({this.overview});

  final BankSetOverview? overview;

  @override
  Future<List<ModuleStat>> getModules() async => _wholeBankModules;

  @override
  Future<BankSetOverview?> getSetOverview({required String setId}) async =>
      overview;
}

Widget _host(
  BankSetOverview? overview, {
  String mode = 'practice',
  BankManifestService? manifestService,
}) => MaterialApp(
  theme: AppTheme.light,
  home: SetDetailPage(
    args: <String, Object?>{
      'mode': mode,
      'drawCount': 100,
      'setId': mode == 'exam' ? 'h3cne-2026-01' : 'ACL',
    },
    questionRepository: _CountsRepo(overview: overview),
    manifestService: manifestService,
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initTestServices();

  setUp(() {
    SetDetailPreload.debugClear();
  });

  group('SetDetailPage 知识点考察题量（byModule）', () {
    testWidgets('练习集 byModule={ACL:100}：ACL 显 100，其余模块显 0，全库 140 不出现', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const BankSetOverview(
            setId: 'ACL',
            total: 100,
            done: 0,
            remaining: 100,
            byModule: <String, int>{'ACL': 100},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // ACL 行题量 = 本套卷真实 100（不是全库 140）。
      expect(find.text('100 题 · 进度待接口'), findsOneWidget);
      final aclRow = find
          .ancestor(of: find.text('ACL'), matching: find.byType(Row))
          .first;
      expect(
        find.descendant(of: aclRow, matching: find.text('100 题 · 进度待接口')),
        findsOneWidget,
      );
      // 其余 4 个模块不在 byModule 里 → 真 0（服务端数过本套卷的 id）。
      expect(find.text('0 题 · 进度待接口'), findsNWidgets(4));
      // 全库总量绝不出现（ACL 140，以及其余模块的全库数）。
      expect(find.textContaining('140'), findsNothing);
      expect(find.text('120 题 · 进度待接口'), findsNothing);
      expect(find.text('130 题 · 进度待接口'), findsNothing);
      expect(find.text('90 题 · 进度待接口'), findsNothing);
      expect(find.text('110 题 · 进度待接口'), findsNothing);
      // 无每模块已答数据 → 进度待接口，进度条不填充，不虚构 0%。
      expect(find.textContaining('%'), findsNothing);
      final bars = find.descendant(
        of: find.byType(SetDetailPage),
        matching: find.byType(FractionallySizedBox),
      );
      expect(bars, findsNWidgets(5));
      for (final element in bars.evaluate()) {
        expect((element.widget as FractionallySizedBox).widthFactor, 0.0);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('考试卷 byModule 每模块 20：逐模块真实拆分', (tester) async {
      await tester.pumpWidget(
        _host(
          const BankSetOverview(
            setId: 'h3cne-2026-01',
            total: 100,
            done: 0,
            remaining: 100,
            byModule: <String, int>{
              'VLAN': 20,
              'OSPF': 20,
              'ACL': 20,
              'NAT': 20,
              'SUBNET': 20,
            },
          ),
          mode: 'exam',
        ),
      );
      await tester.pumpAndSettle();

      // 5 个模块各 20（本套卷拆分），不是全库总量。
      expect(find.text('20 题 · 进度待接口'), findsNWidgets(5));
      expect(find.textContaining('140'), findsNothing);
      expect(find.text('120 题 · 进度待接口'), findsNothing);
      expect(find.text('130 题 · 进度待接口'), findsNothing);
      expect(find.text('90 题 · 进度待接口'), findsNothing);
      expect(find.text('110 题 · 进度待接口'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('overview 为 null：五行题量待接口，全库总量绝不出现', (tester) async {
      await tester.pumpWidget(_host(null));
      await tester.pumpAndSettle();

      // 默认清单仅 H3CNE，与本地五模块无重叠 → 五行全待接口，不编数。
      expect(find.text('题量待接口 · 进度待接口'), findsNWidgets(5));
      expect(find.textContaining('140'), findsNothing);
      expect(find.text('120 题 · 进度待接口'), findsNothing);
      expect(find.text('130 题 · 进度待接口'), findsNothing);
      expect(find.text('90 题 · 进度待接口'), findsNothing);
      expect(find.text('110 题 · 进度待接口'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('考试卷 overview 为 null：清单兜底不适用，五行题量待接口', (tester) async {
      await tester.pumpWidget(
        _host(
          null,
          mode: 'exam',
          manifestService: MockBankManifestService(
            manifest: BankManifest.fromJson(_overlapManifestJson),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 清单里 VLAN / OSPF / ACL 练习池各 100，但本页是考试卷
      // h3cne-2026-01，不是任何模块的练习集 → 绝不借用，五行全待接口。
      expect(find.text('题量待接口 · 进度待接口'), findsNWidgets(5));
      expect(find.text('100 题 · 进度待接口'), findsNothing);
      expect(find.textContaining('140'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('练习集 ACL overview 为 null：仅 ACL 行取清单 100，其余模块待接口', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          null,
          manifestService: MockBankManifestService(
            manifest: BankManifest.fromJson(_overlapManifestJson),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 本页就是 ACL 练习集（练习 setId 即模块代码）→ ACL 行取清单真实 100。
      expect(find.text('100 题 · 进度待接口'), findsOneWidget);
      final aclRow = find
          .ancestor(of: find.text('ACL'), matching: find.byType(Row))
          .first;
      expect(
        find.descendant(of: aclRow, matching: find.text('100 题 · 进度待接口')),
        findsOneWidget,
      );
      // OSPF / VLAN 在清单里虽各 100，但那是别的练习集 → 待接口；
      // NAT / SUBNET 清单无数据 → 同样待接口。全库总量绝不出现。
      expect(find.text('题量待接口 · 进度待接口'), findsNWidgets(4));
      expect(find.textContaining('140'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('BankSetOverview.byModule 防御性解析', () {
    test('真实映射原样解析', () {
      final overview = BankSetOverview.fromJson(<String, dynamic>{
        'setId': 'ACL',
        'total': 100,
        'done': 0,
        'remaining': 100,
        'byModule': <String, dynamic>{'ACL': 100},
      });
      expect(overview.byModule, <String, int>{'ACL': 100});
    });

    test('缺字段 → null（不编映射）', () {
      final overview = BankSetOverview.fromJson(<String, dynamic>{
        'setId': 'ACL',
        'total': 100,
        'done': 0,
        'remaining': 100,
      });
      expect(overview.byModule, isNull);
    });

    test('非法值 / 非 Map → 整体 null，不造半真映射', () {
      final badValue = BankSetOverview.fromJson(<String, dynamic>{
        'setId': 'ACL',
        'total': 100,
        'byModule': <String, dynamic>{'ACL': 'x', 'VLAN': 20},
      });
      expect(badValue.byModule, isNull);
      final notMap = BankSetOverview.fromJson(<String, dynamic>{
        'setId': 'ACL',
        'total': 100,
        'byModule': <Object?>[1, 2],
      });
      expect(notMap.byModule, isNull);
    });

    test('toJson 往返保持 byModule；null 保持 null', () {
      const withMap = BankSetOverview(
        setId: 'ACL',
        total: 100,
        done: 0,
        remaining: 100,
        byModule: <String, int>{'ACL': 100},
      );
      expect(BankSetOverview.fromJson(withMap.toJson()).byModule, <String, int>{
        'ACL': 100,
      });
      const withoutMap = BankSetOverview(
        setId: 'ACL',
        total: 100,
        done: 0,
        remaining: 100,
      );
      expect(withoutMap.toJson()['byModule'], isNull);
      expect(BankSetOverview.fromJson(withoutMap.toJson()).byModule, isNull);
    });
  });

  group('HttpPracticeProgressOverviewSource：byModule 从 fallback 概览合并', () {
    const base = 'http://example.test';
    http.Response json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: const <String, String>{
        'content-type': 'application/json; charset=utf-8',
      },
    );
    const progressBody = <Object?>[
      <String, Object?>{
        'module': 'ACL',
        'total': 100,
        'answered': 0,
        'remaining': 100,
      },
    ];

    test('progress 命中模块：数字取 progress，byModule 取 fallback 概览', () async {
      final source = HttpPracticeProgressOverviewSource(
        baseUrl: base,
        fallback: HttpBankSetOverviewSource(
          baseUrl: base,
          client: MockClient(
            (request) async => json(<String, Object?>{
              'setId': 'ACL',
              'total': 100,
              'done': 0,
              'remaining': 100,
              'byModule': <String, Object?>{'ACL': 100},
            }),
          ),
        ),
        client: MockClient((request) async => json(progressBody)),
      );

      final overview = await source.fetchOverview('ACL');

      expect(overview!.total, 100);
      expect(overview.done, 0);
      expect(overview.byModule, <String, int>{'ACL': 100});
    });

    test('fallback 404：progress 数字保留，byModule null，不编映射', () async {
      final source = HttpPracticeProgressOverviewSource(
        baseUrl: base,
        fallback: HttpBankSetOverviewSource(
          baseUrl: base,
          client: MockClient((request) async => json(<String, Object?>{}, 404)),
        ),
        client: MockClient((request) async => json(progressBody)),
      );

      final overview = await source.fetchOverview('ACL');

      expect(overview!.total, 100);
      expect(overview.byModule, isNull);
    });
  });

  group('SQLite 缓存 v3：byModule 往返（cache-first 命中不丢字段）', () {
    setUpAll(sqfliteFfiInit);

    test('带 byModule 的 overview 读写后一致', () async {
      final db = SqfliteLocalDatabase(
        dbPath: inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      );
      addTearDown(db.close);
      final cache = SqliteBankLocalCache(db);

      await cache.writeOverview(
        const BankSetOverview(
          setId: 'ACL',
          total: 100,
          done: 0,
          remaining: 100,
          byModule: <String, int>{'ACL': 100},
        ),
      );
      final value = await cache.readOverview('ACL');
      expect(value!.byModule, <String, int>{'ACL': 100});
    });

    test('无 byModule 的 overview 读回仍为 null（不编映射）', () async {
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
          done: 0,
          remaining: 100,
        ),
      );
      final value = await cache.readOverview('VLAN');
      expect(value!.byModule, isNull);
    });
  });
}
