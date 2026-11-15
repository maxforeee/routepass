import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:routepass/models/practice.dart';
import 'package:routepass/services/bank/exam_service.dart';
import 'package:routepass/services/bank/practice_service.dart';
import 'package:routepass/services/mock/mock_exam_service.dart';

/// F24 B6：线上后端的时间字段是 ISO 8601 字符串（东八区偏移，
/// `_iso()` = `datetime.astimezone(SHANGHAI).isoformat()`），旧契约与本地
/// 快照是毫秒时间戳。fromJson 必须两种都接受：字符串经 DateTime 解析成
/// 毫秒时间戳，数字原样保留，缺失 / 非法回落默认值。
///
/// 修复前 `(json['startedAt'] as num?)` 遇到 ISO 字符串直接抛 TypeError：
/// 登录用户开始练习落到错误页，练习记录调和静默失败，续考计时丢失。

const String _base = 'http://example.test';

/// 后端 `_session_dict` 的真实输出形状。
const String _isoStarted = '2026-11-15T09:30:00+08:00';
const String _isoCompleted = '2026-11-15T09:42:05.123456+08:00';

/// 同一时刻的 UTC 毫秒值：断言不依赖测试机时区。
final int _startedMs = DateTime.utc(2026, 11, 15, 1, 30).millisecondsSinceEpoch;
final int _completedMs = DateTime.utc(
  2026,
  11,
  15,
  1,
  42,
  5,
  123,
).millisecondsSinceEpoch;

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: const <String, String>{
    'content-type': 'application/json; charset=utf-8',
  },
);

/// 练习会话 dict（`POST /practice/sessions`、`GET /practice/records` 共用）。
Map<String, dynamic> _sessionJson({
  Object? startedAt = _isoStarted,
  Object? completedAt,
  String status = 'in_progress',
}) => <String, dynamic>{
  'id': 'sess-1',
  'kind': 'practice',
  'module': 'VLAN',
  'status': status,
  'answeredCount': 5,
  'correctCount': 3,
  'startedAt': startedAt,
  'completedAt': completedAt,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('epochMillisFromJson（ISO 字符串 + 数字双契约）', () {
    test('ISO 字符串带东八区偏移：按绝对时刻解析，不当成本地时间', () {
      expect(epochMillisFromJson(_isoStarted), _startedMs);
      expect(
        DateTime.fromMillisecondsSinceEpoch(epochMillisFromJson(_isoStarted)!)
            .toUtc(),
        DateTime.utc(2026, 11, 15, 1, 30),
      );
    });

    test('ISO 字符串带微秒（Python isoformat 精度）解析到毫秒', () {
      expect(epochMillisFromJson(_isoCompleted), _completedMs);
    });

    test('ISO 字符串以 Z 结尾（UTC）同样接受', () {
      expect(epochMillisFromJson('2026-11-15T01:30:00Z'), _startedMs);
    });

    test('数字（旧契约毫秒时间戳）原样取整', () {
      expect(epochMillisFromJson(1763000000000), 1763000000000);
      expect(epochMillisFromJson(1763000000000.9), 1763000000000);
    });

    test('null / 空串 / 非法字符串返回 null，由调用方给默认值', () {
      expect(epochMillisFromJson(null), isNull);
      expect(epochMillisFromJson(''), isNull);
      expect(epochMillisFromJson('not-a-time'), isNull);
    });
  });

  group('PracticeSessionInfo.fromJson（B6 会话时间）', () {
    test('ISO startedAt 不再抛异常，解析成毫秒时间戳', () {
      final info = PracticeSessionInfo.fromJson(_sessionJson());
      expect(info.id, 'sess-1');
      expect(info.startedAt, _startedMs);
      expect(info.answeredCount, 5);
      expect(info.correctCount, 3);
      expect(info.isCompleted, isFalse);
    });

    test('数字 startedAt 仍然接受（向后兼容旧后端 / 本地数据）', () {
      final info = PracticeSessionInfo.fromJson(
        _sessionJson(startedAt: 1763000000000),
      );
      expect(info.startedAt, 1763000000000);
    });

    test('startedAt 缺失 / null / 非法时回落 0，不抛异常', () {
      final missing = _sessionJson()..remove('startedAt');
      expect(PracticeSessionInfo.fromJson(missing).startedAt, 0);
      expect(
        PracticeSessionInfo.fromJson(_sessionJson(startedAt: null)).startedAt,
        0,
      );
      expect(
        PracticeSessionInfo.fromJson(_sessionJson(startedAt: 'garbage'))
            .startedAt,
        0,
      );
    });
  });

  group('PracticeRecordSummary.fromJson（B6 记录时间）', () {
    test('ISO startedAt + completedAt 都解析成毫秒时间戳', () {
      final record = PracticeRecordSummary.fromJson(
        _sessionJson(status: 'completed', completedAt: _isoCompleted),
      );
      expect(record.startedAt, _startedMs);
      expect(record.completedAt, _completedMs);
      expect(record.isCompleted, isTrue);
    });

    test('in_progress 断点：后端 completedAt 为 null 时保持 null', () {
      final record = PracticeRecordSummary.fromJson(_sessionJson());
      expect(record.startedAt, _startedMs);
      expect(record.completedAt, isNull);
    });

    test('数字 startedAt / completedAt 仍然接受（向后兼容）', () {
      final record = PracticeRecordSummary.fromJson(
        _sessionJson(status: 'completed', startedAt: 10, completedAt: 20),
      );
      expect(record.startedAt, 10);
      expect(record.completedAt, 20);
    });
  });

  group('HttpPracticeService（线上 ISO 契约端到端）', () {
    test('POST /practice/sessions 返回 ISO startedAt：会话可用，不落错误页', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/v1/practice/sessions');
        return _json(_sessionJson());
      });
      final service = HttpPracticeService(client: client, baseUrl: _base);

      final session = await service.startPracticeSession(module: 'VLAN');
      expect(session, isNotNull);
      expect(session!.id, 'sess-1');
      expect(session.startedAt, _startedMs);
    });

    test(
      'GET /practice/sessions/{id} 详情：ISO 时间 + answeredQuestionIds',
      () async {
        final client = MockClient((request) async {
          expect(request.url.path, '/api/v1/practice/sessions/sess-1');
          return _json(<String, dynamic>{
            ..._sessionJson(),
            'answeredQuestionIds': <String>['VLAN-0001', 'VLAN-0003'],
          });
        });
        final service = HttpPracticeService(client: client, baseUrl: _base);

        final detail = await service.fetchPracticeSession('sess-1');
        expect(detail?.startedAt, _startedMs);
        expect(detail?.answeredQuestionIds, <String>['VLAN-0001', 'VLAN-0003']);
      },
    );

    test('GET /practice/records 的 ISO items 全部解析（记录调和不再失败）', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/v1/practice/records');
        return _json(<String, dynamic>{
          'items': <Map<String, dynamic>>[
            _sessionJson(status: 'completed', completedAt: _isoCompleted),
            _sessionJson(),
          ],
          'page': 1,
          'pageSize': 20,
          'total': 2,
        });
      });
      final service = HttpPracticeService(client: client, baseUrl: _base);

      final records = await service.fetchPracticeRecords();
      expect(records.length, 2);
      expect(records.first.completedAt, _completedMs);
      expect(records.first.isCompleted, isTrue);
      expect(records.last.startedAt, _startedMs);
      expect(records.last.completedAt, isNull);
    });
  });

  group('HttpExamService.loadExamForResume（B6 续考时间）', () {
    Map<String, dynamic> examJson(
      Object? startedAt, {
      String key = 'startedAt',
    }) => <String, dynamic>{
      'id': 'EX-1',
      key: startedAt,
      'total': 1,
      'questions': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'Q-1',
          'module': 'VLAN',
          'type': 'single',
          'stem': '题干 1',
          'options': <String>['A 选项', 'B 选项'],
        },
      ],
      'answers': <Map<String, dynamic>>[
        <String, dynamic>{
          'questionId': 'Q-1',
          'chosen': <String>['B'],
        },
      ],
    };

    HttpExamService serviceReturning(Map<String, dynamic> body) =>
        HttpExamService(
          local: MockExamService(),
          client: MockClient((request) async {
            expect(request.url.path, '/api/v1/exam/EX-1');
            return _json(body);
          }),
          baseUrl: _base,
        );

    test('ISO startedAt 解析成毫秒时间戳（续考计时不再从 0 起算）', () async {
      final recovery = await serviceReturning(examJson(_isoStarted))
          .loadExamForResume('EX-1');
      expect(recovery, isNotNull);
      expect(recovery!.startedAt, _startedMs);
      expect(recovery.questions.length, 1);
      expect(recovery.answers, <String, List<String>>{
        'Q-1': <String>['B'],
      });
    });

    test('数字 startedAt 仍然接受（向后兼容）', () async {
      final recovery = await serviceReturning(examJson(1763000000000))
          .loadExamForResume('EX-1');
      expect(recovery?.startedAt, 1763000000000);
    });

    test('蛇形旧字段 started_at 同样接受 ISO 字符串', () async {
      final recovery = await serviceReturning(
        examJson(_isoStarted, key: 'started_at'),
      ).loadExamForResume('EX-1');
      expect(recovery?.startedAt, _startedMs);
    });

    test('startedAt 缺失 / 非法时回落 0，不抛异常', () async {
      final missing = examJson(null)..remove('startedAt');
      final absent = await serviceReturning(missing).loadExamForResume('EX-1');
      expect(absent?.startedAt, 0);

      final garbage = await serviceReturning(examJson('garbage'))
          .loadExamForResume('EX-1');
      expect(garbage?.startedAt, 0);
    });
  });
}
