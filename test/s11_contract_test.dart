import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:routepass/core/kv_store.dart';
import 'package:routepass/models/answer_record.dart';
import 'package:routepass/models/exam.dart';
import 'package:routepass/models/practice.dart';
import 'package:routepass/models/question.dart';
import 'package:routepass/models/stats.dart';
import 'package:routepass/services/bank/answer_record_service.dart';
import 'package:routepass/services/bank/exam_service.dart';
import 'package:routepass/services/bank/practice_service.dart';
import 'package:routepass/services/bank/question_bank_source.dart';
import 'package:routepass/services/mock/mock_exam_service.dart';
import 'package:routepass/services/mock/mock_practice_service.dart';

/// S11 真实契约形状测试：
/// - 裸数组进度、`answers` 列表恢复、会话开始/结束状态；
/// - submit 带 sessionId；/practice/next 只传 module + sessionId；
/// - 404 / 401（线上尚未部署 S11）回落本地行为，不编数据。

const String _base = 'http://example.test';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: const <String, String>{
    'content-type': 'application/json; charset=utf-8',
  },
);

Map<String, dynamic> _apiQuestion(
  String id, {
  List<int> answer = const <int>[0],
}) => <String, dynamic>{
  'id': id,
  'module': 'VLAN',
  'type': 'single',
  'stem': '题干 $id',
  'options': <String>['A 选项', 'B 选项'],
  'answer': answer,
  'explanation': '解析 $id',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HttpPracticeService（S11 练习契约）', () {
    test('GET /practice/progress 解析裸数组（无题型分布）', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/v1/practice/progress');
        return _json(<Map<String, Object?>>[
          <String, Object?>{
            'module': 'VLAN',
            'total': 100,
            'answered': 12,
            'remaining': 88,
          },
          <String, Object?>{
            'module': 'OSPF',
            'total': 80,
            'answered': 0,
            'remaining': 80,
          },
        ]);
      });
      final service = HttpPracticeService(client: client, baseUrl: _base);

      final progress = await service.fetchPracticeProgress();
      expect(progress.length, 2);
      expect(progress.first.module, 'VLAN');
      expect(progress.first.total, 100);
      expect(progress.first.answered, 12);
      expect(progress.first.remaining, 88);
    });

    test('POST /practice/sessions 传 module，解析 in_progress 会话', () async {
      late Map<String, dynamic> sent;
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/v1/practice/sessions');
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return _json(<String, Object?>{
          'id': 'sess-1',
          'kind': 'practice',
          'module': 'VLAN',
          'status': 'in_progress',
          'answeredCount': 5,
          'correctCount': 3,
          'startedAt': 1763000000000,
        });
      });
      final service = HttpPracticeService(client: client, baseUrl: _base);

      final session = await service.startPracticeSession(module: 'VLAN');
      expect(sent['module'], 'VLAN');
      expect(session?.id, 'sess-1');
      expect(session?.isCompleted, isFalse);
      expect(session?.answeredCount, 5);
      expect(session?.correctCount, 3);
    });

    test(
      'POST /sessions/{id}/end：满 20 题返回 completed，未满保留 in_progress',
      () async {
        var calls = 0;
        final client = MockClient((request) async {
          calls++;
          expect(request.url.path, '/api/v1/practice/sessions/sess-1/end');
          if (calls == 1) {
            return _json(<String, Object?>{
              'id': 'sess-1',
              'status': 'completed',
              'answeredCount': 20,
              'correctCount': 17,
              'startedAt': 1,
              'completedAt': 2,
            });
          }
          return _json(<String, Object?>{
            'id': 'sess-1',
            'status': 'in_progress',
            'answeredCount': 8,
            'correctCount': 6,
            'startedAt': 1,
          });
        });
        final service = HttpPracticeService(client: client, baseUrl: _base);

        final done = await service.endPracticeSession('sess-1');
        expect(done?.status, PracticeSessionInfo.statusCompleted);
        expect(done?.answeredCount, 20);
        expect(done?.isCompleted, isTrue);

        final partial = await service.endPracticeSession('sess-1');
        expect(partial?.status, PracticeSessionInfo.statusInProgress);
        expect(partial?.isCompleted, isFalse);
      },
    );

    test('GET /sessions/{id} 解析 answeredQuestionIds', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/v1/practice/sessions/sess-2');
        return _json(<String, Object?>{
          'id': 'sess-2',
          'status': 'in_progress',
          'answeredCount': 2,
          'correctCount': 2,
          'startedAt': 1,
          'answeredQuestionIds': <String>['VLAN-0001', 'VLAN-0003'],
        });
      });
      final service = HttpPracticeService(client: client, baseUrl: _base);

      final detail = await service.fetchPracticeSession('sess-2');
      expect(detail?.answeredQuestionIds, <String>['VLAN-0001', 'VLAN-0003']);
    });

    test('GET /practice/next 只传 module + sessionId，解析答案与解析', () async {
      late Uri uri;
      final client = MockClient((request) async {
        uri = request.url;
        return _json(<String, Object?>{
          'question': _apiQuestion('VLAN-0007'),
          'sessionId': 'sess-9',
        });
      });
      final service = HttpPracticeService(client: client, baseUrl: _base);

      final next = await service.drawNextQuestion(
        setId: 'VLAN',
        module: 'VLAN',
        excludedIds: <String>{'VLAN-0001'},
        sessionId: 'sess-9',
      );
      expect(uri.path, '/api/v1/practice/next');
      expect(uri.queryParameters['module'], 'VLAN');
      expect(uri.queryParameters['sessionId'], 'sess-9');
      expect(uri.queryParameters.containsKey('exclude'), isFalse);
      expect(next?.question.id, 'VLAN-0007');
      expect(next?.question.answer, <String>['A']);
      expect(next?.question.explanation, '解析 VLAN-0007');
      expect(next?.sessionId, 'sess-9');
    });

    test(
      'POST /practice/submit 带 sessionId，解析 correct/answer/explanation',
      () async {
        late Map<String, dynamic> sent;
        final client = MockClient((request) async {
          expect(request.url.path, '/api/v1/practice/submit');
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return _json(<String, Object?>{
            'correct': true,
            'answer': <String>['A'],
            'explanation': '解析内容',
          });
        });
        final service = HttpPracticeService(client: client, baseUrl: _base);

        final result = await service.submitAnswer(
          sessionId: 'sess-9',
          questionId: 'VLAN-0007',
          chosen: <String>['A'],
          durationMs: 1200,
          setId: 'VLAN',
          opId: 'op-1',
          mode: 'practice',
        );
        expect(sent['sessionId'], 'sess-9');
        expect(sent['questionId'], 'VLAN-0007');
        expect(result.correct, isTrue);
        expect(result.correctKeys, <String>['A']);
        expect(result.explanation, '解析内容');
      },
    );

    test('GET /practice/records 解析 items（分页）', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/v1/practice/records');
        expect(request.url.queryParameters['page'], '1');
        expect(request.url.queryParameters['pageSize'], '20');
        return _json(<String, Object?>{
          'items': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'rec-1',
              'module': 'VLAN',
              'status': 'completed',
              'answeredCount': 20,
              'correctCount': 18,
              'startedAt': 10,
              'completedAt': 20,
            },
          ],
        });
      });
      final service = HttpPracticeService(client: client, baseUrl: _base);

      final records = await service.fetchPracticeRecords();
      expect(records.length, 1);
      expect(records.single.id, 'rec-1');
      expect(records.single.isCompleted, isTrue);
      expect(records.single.completedAt, 20);
    });

    test('404 / 401 回落本地：抽题与判分走 fallback，会话与进度返回 null / 空', () async {
      final fallback = MockPracticeService();
      final client = MockClient((_) async => _json(<String, String>{}, 404));
      final service = HttpPracticeService(
        client: client,
        baseUrl: _base,
        fallback: fallback,
      );

      expect(await service.startPracticeSession(module: 'VLAN'), isNull);
      expect(await service.endPracticeSession('sess-x'), isNull);
      expect(await service.fetchPracticeSession('sess-x'), isNull);
      expect(await service.fetchPracticeProgress(), isEmpty);
      expect(await service.fetchPracticeRecords(), isEmpty);

      final next = await service.drawNextQuestion(
        setId: 'VLAN',
        module: 'VLAN',
        excludedIds: const <String>{},
      );
      expect(next, isNotNull, reason: '接口未就绪时回落本地 Mock 样例题');

      final result = await service.submitAnswer(
        sessionId: 'sess-x',
        questionId: next!.question.id,
        chosen: const <String>['A'],
        durationMs: 1,
      );
      expect(result.correct, isNull, reason: 'Mock 不判分');
    });

    test('401（S11 未鉴权）同样回落，不抛给 UI', () async {
      final client = MockClient((_) async => _json(<String, String>{}, 401));
      final service = HttpPracticeService(
        client: client,
        baseUrl: _base,
        fallback: MockPracticeService(),
      );
      expect(await service.fetchPracticeProgress(), isEmpty);
      expect(await service.startPracticeSession(module: 'OSPF'), isNull);
    });

    test('没有 fallback 且接口失败时抛异常（由 UI 显示“抽题失败”）', () async {
      final client = MockClient((_) async => _json(<String, String>{}, 404));
      final service = HttpPracticeService(client: client, baseUrl: _base);
      expect(
        () => service.drawNextQuestion(
          setId: 'VLAN',
          excludedIds: const <String>{},
        ),
        throwsA(isA<PracticeServiceException>()),
      );
    });
  });

  group('HttpPracticeProgressOverviewSource（前置页计数）', () {
    test('按模块映射 total/answered/remaining，byType 为 null', () async {
      final source = HttpPracticeProgressOverviewSource(
        client: MockClient((request) async {
          expect(request.url.path, '/api/v1/practice/progress');
          return _json(<Map<String, Object?>>[
            <String, Object?>{
              'module': 'VLAN',
              'total': 100,
              'answered': 12,
              'remaining': 88,
            },
          ]);
        }),
        baseUrl: _base,
      );

      final overview = await source.fetchOverview('VLAN');
      expect(overview?.total, 100);
      expect(overview?.done, 12);
      expect(overview?.remaining, 88);
      expect(overview?.byType, isNull, reason: 'S11 不提供题型分布，不推算');
    });

    test('接口 404 时回落 /bank/sets overview（考试卷 id）', () async {
      var fallbackCalls = 0;
      final fallback = _StubOverviewSource(() async {
        fallbackCalls++;
        return null;
      });
      final source = HttpPracticeProgressOverviewSource(
        client: MockClient((_) async => _json(<String, String>{}, 404)),
        baseUrl: _base,
        fallback: fallback,
      );

      expect(await source.fetchOverview('h3cne-2026-01'), isNull);
      expect(fallbackCalls, 1);
    });
  });

  group('HttpExamService（S11 考试契约）', () {
    test('POST /exam/{id}/answers 只发 questionId + answer', () async {
      late Map<String, dynamic> sent;
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/v1/exam/EX-1/answers');
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return _json(<String, bool>{'saved': true});
      });
      final service = HttpExamService(
        local: MockExamService(),
        client: client,
        baseUrl: _base,
      );

      await service.saveAnswer(
        examId: 'EX-1',
        questionId: 'Q-1',
        chosen: <String>['B'],
        opId: 'op-1',
      );
      expect(sent['questionId'], 'Q-1');
      expect(sent['answer'], <String>['B']);
      expect(sent.containsKey('correct'), isFalse);
    });

    test('GET /exam/{id}：卷面无答案，answers 是列表 [{questionId, chosen}]', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/v1/exam/EX-2');
        return _json(<String, Object?>{
          'id': 'EX-2',
          'startedAt': 1763000000000,
          'total': 2,
          'questions': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'Q-1',
              'module': 'VLAN',
              'type': 'single',
              'stem': '题干 1',
              'options': <String>['A 选项', 'B 选项'],
            },
            <String, Object?>{
              'id': 'Q-2',
              'module': 'VLAN',
              'type': 'single',
              'stem': '题干 2',
              'options': <String>['A 选项', 'B 选项'],
            },
          ],
          'answers': <Map<String, Object?>>[
            <String, Object?>{
              'questionId': 'Q-1',
              'chosen': <String>['B'],
            },
          ],
        });
      });
      final service = HttpExamService(
        local: MockExamService(),
        client: client,
        baseUrl: _base,
      );

      final recovery = await service.loadExamForResume('EX-2');
      expect(recovery, isNotNull);
      expect(recovery!.questions.length, 2);
      expect(recovery.questions.first.answer, isEmpty, reason: '卷面不含答案');
      expect(recovery.answers, <String, List<String>>{
        'Q-1': <String>['B'],
      });
      expect(recovery.total, 2);
    });

    test('POST /exam/{id}/submit 判分；404 回落本地 Mock（不计分）', () async {
      final local = MockExamService();
      final ok = HttpExamService(
        local: local,
        client: MockClient((request) async {
          expect(request.url.path, '/api/v1/exam/EX-3/submit');
          return _json(<String, Object?>{'score': 88, 'passed': true});
        }),
        baseUrl: _base,
      );
      final graded = await ok.submitExam(
        examId: 'EX-3',
        answers: <String, List<String>>{
          'Q-1': <String>['A'],
        },
        durationMs: 1000,
      );
      expect(graded?.score, 88);
      expect(graded?.passed, isTrue);

      final notReady = HttpExamService(
        local: local,
        client: MockClient((_) async => _json(<String, String>{}, 404)),
        baseUrl: _base,
      );
      final fallbackResult = await notReady.submitExam(
        examId: 'EX-3',
        answers: const <String, List<String>>{},
        durationMs: 1000,
      );
      expect(fallbackResult?.score, isNull, reason: '接口未就绪不计分');
    });

    test('404 恢复返回 null（改用本地快照续考）', () async {
      final service = HttpExamService(
        local: MockExamService(),
        client: MockClient((_) async => _json(<String, String>{}, 404)),
        baseUrl: _base,
      );
      expect(await service.loadExamForResume('EX-4'), isNull);
    });
  });

  group('KvAnswerRecordService.syncFromServer（服务端记录调和）', () {
    test('已完成会话并入本地（serverId 回填），本地断点被标记已同步', () async {
      final kv = InMemoryKvStore();
      final localRecord = AnswerRecord(
        id: 'rec-local-1',
        setId: 'VLAN',
        setTitle: 'VLAN',
        mode: 'practice',
        kind: 'breakpoint',
        targetCount: 20,
        answeredCount: 8,
        totalCount: 100,
        correctCount: 6,
        durationMs: 1000,
        createdAt: 5,
        updatedAt: 6,
      );
      final service = KvAnswerRecordService(
        kvStore: kv,
        serverRecords: () async => const <PracticeRecordSummary>[
          PracticeRecordSummary(
            id: 'srv-rec-1',
            module: 'VLAN',
            status: PracticeSessionInfo.statusCompleted,
            answeredCount: 20,
            correctCount: 18,
            startedAt: 100,
            completedAt: 200,
          ),
          PracticeRecordSummary(
            id: 'srv-rec-2',
            module: 'VLAN',
            status: PracticeSessionInfo.statusInProgress,
            answeredCount: 8,
            correctCount: 6,
            startedAt: 5,
          ),
        ],
      );
      service.upsert(localRecord);

      await service.syncFromServer();

      final records = service.recordsFor(setId: 'VLAN', mode: 'practice');
      expect(records.length, 2, reason: '完成记录并入 + 本地断点保留');
      final completed = records.firstWhere((r) => r.isCompletion);
      expect(completed.serverId, 'srv-rec-1');
      expect(completed.answeredCount, 20);
      expect(completed.targetCount, 20, reason: '完成会话的最终题数即目标');
      expect(completed.correctCount, 18);
      expect(completed.synced, isTrue);

      final breakpoint = records.firstWhere((r) => r.isBreakpoint);
      expect(breakpoint.id, 'rec-local-1');
      expect(breakpoint.serverId, 'srv-rec-2');
      expect(breakpoint.synced, isTrue);
    });

    test('服务端无记录 / 请求失败：本地记录原样保留（不删除、不编造）', () async {
      final kv = InMemoryKvStore();
      final service = KvAnswerRecordService(
        kvStore: kv,
        serverRecords: () async => throw Exception('offline'),
      );
      service.upsert(
        AnswerRecord(
          id: 'rec-local-2',
          setId: 'VLAN',
          setTitle: 'VLAN',
          mode: 'practice',
          kind: 'completion',
          targetCount: 20,
          answeredCount: 20,
          totalCount: 100,
          correctCount: 20,
          durationMs: 1000,
          createdAt: 7,
          updatedAt: 8,
        ),
      );

      await service.syncFromServer();

      final records = service.recordsFor(setId: 'VLAN', mode: 'practice');
      expect(records.length, 1);
      expect(records.single.id, 'rec-local-2');
      expect(service.pendingSync().length, 1, reason: '未确认记录继续待同步');
    });

    test('没有服务端数据源时是 no-op', () async {
      final service = KvAnswerRecordService(kvStore: InMemoryKvStore());
      await service.syncFromServer();
      expect(service.recordsFor(setId: 'VLAN', mode: 'practice'), isEmpty);
    });
  });

  group('模型契约', () {
    test('PracticeSessionInfo 只读不透明 id（VARCHAR(40)，非 UUID）', () {
      final info = PracticeSessionInfo.fromJson(<String, dynamic>{
        'id': 'sess-abc-123',
        'status': 'completed',
        'answeredCount': 20,
        'correctCount': 20,
        'startedAt': 1,
      });
      expect(info.id, 'sess-abc-123');
      expect(info.isCompleted, isTrue);
    });

    test('ExamRecovery 的 answers 是 map，但由列表还原', () {
      const recovery = ExamRecovery(
        id: 'EX-1',
        questions: <Question>[],
        answers: <String, List<String>>{
          'Q-1': <String>['A', 'C'],
        },
      );
      expect(recovery.answers['Q-1'], <String>['A', 'C']);
    });
  });
}

class _StubOverviewSource implements BankSetOverviewSource {
  _StubOverviewSource(this._fetch);

  final Future<Object?> Function() _fetch;

  @override
  Future<BankSetOverview?> fetchOverview(String setId) async =>
      await _fetch() as BankSetOverview?;
}
