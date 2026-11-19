/// F37 练习前置页正确率必须来自真实接口（accuracy 从 fallback 概览合并）。
///
/// 修复前的 bug：HttpPracticeProgressOverviewSource.fetchOverview 在
/// /practice/progress 命中模块时，只合并了 fallback 概览的 byType /
/// byModule，漏掉 accuracy —— 后端明明下发了真实正确率，练习前置页
/// 仍显示“正确率待接口”。
/// 修复后：accuracy 与 byType / byModule 同路合并；fallback 无作答
/// 记录（accuracy null）/ 缺字段 / 404 / 未装配时保持 null（前置页
/// “正确率待接口”），绝不编 0% 或按 done/total 推算。
///
/// 覆盖（MockClient 模式同 f35_set_detail_counts_test / f26_bytype_test）：
/// - progress 命中 + fallback accuracy 85.5 → 0.855，byType/byModule 同行；
/// - fallback accuracy null（尚无作答）→ null，byType/byModule 仍合并；
/// - fallback 缺 accuracy 字段（旧后端）→ null；
/// - fallback 404 → accuracy null，total/done/remaining 仍取 progress；
/// - progress 未命中（考试卷 id）→ 整体回落 fallback，accuracy 随行；
/// - 未装配 fallback → accuracy null，不编数。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:routepass/services/bank/question_bank_source.dart';

const String _base = 'http://example.test';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: const <String, String>{
    'content-type': 'application/json; charset=utf-8',
  },
);

/// 后端 set_overview 契约 fixture：accuracy 0–100 下发（bank.py 按
/// attempts 真实计算，尚无作答为 null），byType / byModule 随 F26/F35。
Map<String, Object?> _overviewPayload({
  String setId = 'ACL',
  int total = 100,
  int done = 40,
  Object? accuracy = 85.5,
  Map<String, Object?> byModule = const <String, Object?>{'ACL': 100},
}) => <String, Object?>{
  'setId': setId,
  'total': total,
  'done': done,
  'remaining': total - done,
  'accuracy': accuracy,
  'byType': <String, Object?>{'single': 75, 'multiple': 25},
  'byModule': byModule,
};

/// /practice/progress 契约是裸数组；ACL 练习集已答 40 / 100。
const List<Object?> _progressBody = <Object?>[
  <String, Object?>{
    'module': 'ACL',
    'total': 100,
    'answered': 40,
    'remaining': 60,
  },
];

void main() {
  group('HttpPracticeProgressOverviewSource：accuracy 从 fallback 概览合并', () {
    test('progress 命中模块：数字取 progress，accuracy 85.5 → 0.855，byType/byModule 同行', () async {
      final paths = <String>[];
      final source = HttpPracticeProgressOverviewSource(
        baseUrl: _base,
        fallback: HttpBankSetOverviewSource(
          baseUrl: _base,
          client: MockClient((request) async {
            paths.add(request.url.path);
            return _json(_overviewPayload());
          }),
        ),
        client: MockClient((request) async {
          paths.add(request.url.path);
          return _json(_progressBody);
        }),
      );

      final overview = await source.fetchOverview('ACL');

      expect(paths, contains('/api/v1/practice/progress'));
      expect(paths, contains('/api/v1/bank/sets/ACL/overview'));
      expect(overview, isNotNull);
      expect(overview!.total, 100);
      expect(overview.done, 40);
      expect(overview.remaining, 60);
      // F37 修复点：真实正确率随 fallback 概览合并（0–100 → 0–1）。
      expect(overview.accuracy, 0.855);
      // 回归：F26 byType / F35 byModule 仍从 fallback 合并。
      expect(overview.byType, isNotNull);
      expect(overview.byType!.single, 75);
      expect(overview.byType!.multiple, 25);
      expect(overview.byModule, <String, int>{'ACL': 100});
    });

    test('fallback accuracy null（尚无作答记录）→ null，byType/byModule 仍合并', () async {
      final source = HttpPracticeProgressOverviewSource(
        baseUrl: _base,
        fallback: HttpBankSetOverviewSource(
          baseUrl: _base,
          client: MockClient(
            (request) async => _json(_overviewPayload(done: 0, accuracy: null)),
          ),
        ),
        client: MockClient((request) async => _json(_progressBody)),
      );

      final overview = await source.fetchOverview('ACL');

      expect(overview!.done, 40);
      // 无作答 → 保持 null（前置页“正确率待接口”），绝不编 0%。
      expect(overview.accuracy, isNull);
      expect(overview.byType!.single, 75);
      expect(overview.byModule, <String, int>{'ACL': 100});
    });

    test('fallback 概览缺 accuracy 字段（旧后端）→ null，不编数', () async {
      final payload = _overviewPayload()..remove('accuracy');
      final source = HttpPracticeProgressOverviewSource(
        baseUrl: _base,
        fallback: HttpBankSetOverviewSource(
          baseUrl: _base,
          client: MockClient((request) async => _json(payload)),
        ),
        client: MockClient((request) async => _json(_progressBody)),
      );

      final overview = await source.fetchOverview('ACL');

      expect(overview!.done, 40);
      expect(overview.accuracy, isNull);
      expect(overview.byType!.multiple, 25);
      expect(overview.byModule, <String, int>{'ACL': 100});
    });

    test('fallback 404：progress 数字保留，accuracy/byType/byModule null', () async {
      final source = HttpPracticeProgressOverviewSource(
        baseUrl: _base,
        fallback: HttpBankSetOverviewSource(
          baseUrl: _base,
          client: MockClient(
            (request) async => _json(<String, Object?>{}, 404),
          ),
        ),
        client: MockClient((request) async => _json(_progressBody)),
      );

      final overview = await source.fetchOverview('ACL');

      expect(overview!.total, 100);
      expect(overview.done, 40);
      expect(overview.remaining, 60);
      expect(overview.accuracy, isNull);
      expect(overview.byType, isNull);
      expect(overview.byModule, isNull);
    });

    test('progress 未命中（考试卷 id）：整体回落 fallback，accuracy 随行', () async {
      final source = HttpPracticeProgressOverviewSource(
        baseUrl: _base,
        fallback: HttpBankSetOverviewSource(
          baseUrl: _base,
          client: MockClient(
            (request) async => _json(
              _overviewPayload(
                setId: 'h3cne-2026-01',
                done: 2,
                byModule: <String, Object?>{
                  'VLAN': 20,
                  'OSPF': 20,
                  'ACL': 20,
                  'NAT': 20,
                  'SUBNET': 20,
                },
              ),
            ),
          ),
        ),
        client: MockClient((request) async => _json(_progressBody)),
      );

      final overview = await source.fetchOverview('h3cne-2026-01');

      expect(overview!.setId, 'h3cne-2026-01');
      expect(overview.total, 100);
      expect(overview.done, 2);
      expect(overview.accuracy, 0.855);
      expect(overview.byType!.single, 75);
      expect(overview.byModule, <String, int>{
        'VLAN': 20,
        'OSPF': 20,
        'ACL': 20,
        'NAT': 20,
        'SUBNET': 20,
      });
    });

    test('未装配 fallback：accuracy null，progress 数字保留，不编数', () async {
      final source = HttpPracticeProgressOverviewSource(
        baseUrl: _base,
        client: MockClient((request) async => _json(_progressBody)),
      );

      final overview = await source.fetchOverview('ACL');

      expect(overview!.total, 100);
      expect(overview.done, 40);
      expect(overview.accuracy, isNull);
      expect(overview.byType, isNull);
      expect(overview.byModule, isNull);
    });
  });
}