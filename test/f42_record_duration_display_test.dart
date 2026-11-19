/// F42：记录详情用时行 —— 服务端 durationMs 优先，本地记录回落，
/// null / ≤0 显示 '--'（mm:ss 格式与记录卡 `_durationText` 一致）。
///
/// 注入模式同 f25_record_detail_test：fake PracticeService + 内存 kv，
/// 不发真实网络请求，不注册 ServiceLocator。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/core/kv_store.dart';
import 'package:routepass/core/theme.dart';
import 'package:routepass/models/answer_record.dart';
import 'package:routepass/models/practice.dart';
import 'package:routepass/models/question.dart';
import 'package:routepass/pages/bank/answer_record_detail_page.dart';
import 'package:routepass/services/bank/answer_record_service.dart';
import 'package:routepass/services/bank/answer_session_service.dart';
import 'package:routepass/services/bank/practice_service.dart';

AnswerRecord _record({int durationMs = 61000}) {
  return AnswerRecord(
    id: 'srv-sess-1',
    setId: 'VLAN',
    setTitle: 'VLAN',
    mode: 'practice',
    kind: 'completion',
    targetCount: 20,
    answeredCount: 20,
    totalCount: 100,
    correctCount: 16,
    durationMs: durationMs,
    createdAt: 1000,
    updatedAt: 1000,
    synced: true,
    serverId: 'sess-1',
  );
}

PracticeRecordDetail _detail({int? durationMs}) {
  return PracticeRecordDetail(
    sessionId: 'sess-1',
    module: 'VLAN',
    status: 'completed',
    answered: 20,
    total: 20,
    correct: 16,
    score: 80,
    durationMs: durationMs,
  );
}

Map<String, dynamic> _detailJson() {
  return <String, dynamic>{
    'sessionId': 'sess-1',
    'module': 'VLAN',
    'status': 'completed',
    'answered': 20,
    'total': 20,
    'correct': 16,
    'score': 80,
    'weakPoints': const <Map<String, dynamic>>[],
  };
}

class _FakePracticeService implements PracticeService {
  PracticeRecordDetail? detail;
  final List<String> detailCalls = <String>[];

  @override
  Future<PracticeRecordDetail?> getRecordDetail(String sessionId) async {
    detailCalls.add(sessionId);
    return detail;
  }

  @override
  Future<bool> deleteRecord(String sessionId) async => true;

  @override
  Future<PracticeRecordPaper?> getRecordPaper(String sessionId) async => null;

  @override
  Future<PracticeSession> startSession({
    required List<Question> questions,
    required String mode,
  }) => throw UnimplementedError();

  @override
  Future<AnswerResult> submitAnswer({
    required String sessionId,
    required String questionId,
    required List<String> chosen,
    required int durationMs,
    String? setId,
    String? opId,
    String? mode,
  }) => throw UnimplementedError();

  @override
  Future<PracticeNext?> drawNextQuestion({
    required String setId,
    String? module,
    required Set<String> excludedIds,
    String? sessionId,
  }) async => null;

  @override
  Future<PracticeSessionInfo?> startPracticeSession({String? module}) async =>
      null;

  @override
  Future<PracticeSessionInfo?> fetchPracticeSession(String sessionId) async =>
      null;

  @override
  Future<PracticeSessionInfo?> endPracticeSession(String sessionId) async =>
      null;

  @override
  Future<List<PracticeRecordSummary>> fetchPracticeRecords({
    int page = 1,
    int pageSize = 20,
  }) async => const <PracticeRecordSummary>[];

  @override
  Future<List<PracticeModuleProgress>> fetchPracticeProgress() async =>
      const <PracticeModuleProgress>[];

  @override
  Future<ContinueSession?> resumeSession({required String setId}) async => null;

  @override
  Future<ContinueSession?> getContinueSession() async => null;
}

/// 详情页直接作为 home（渲染类用例），服务全部注入。
Widget _host(AnswerRecord record, _FakePracticeService practice) {
  final kv = InMemoryKvStore();
  return MaterialApp(
    theme: AppTheme.light,
    home: AnswerRecordDetailPage(
      args: <String, Object?>{'record': record},
      practiceService: practice,
      recordService: KvAnswerRecordService(kvStore: kv),
      sessionService: KvAnswerSessionService(kvStore: kv),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PracticeRecordDetail.durationMs 解析', () {
    test('durationMs: 125000 原样解析', () {
      final json = _detailJson()..['durationMs'] = 125000;
      expect(PracticeRecordDetail.fromJson(json).durationMs, 125000);
    });

    test('字段缺失 → null，不是 0', () {
      expect(PracticeRecordDetail.fromJson(_detailJson()).durationMs, isNull);
    });

    test('durationMs: null → null，不是 0', () {
      final json = _detailJson()..['durationMs'] = null;
      expect(PracticeRecordDetail.fromJson(json).durationMs, isNull);
    });
  });

  group('AnswerRecordDetailPage 用时行', () {
    testWidgets('服务端值优先：125000 → 02:05，本地 61000 不生效', (tester) async {
      final practice = _FakePracticeService()
        ..detail = _detail(durationMs: 125000);
      await tester.pumpWidget(_host(_record(durationMs: 61000), practice));
      await tester.pumpAndSettle();

      expect(find.text('用时'), findsOneWidget);
      expect(find.text('02:05'), findsOneWidget);
      expect(find.text('01:01'), findsNothing);
    });

    testWidgets('服务端 durationMs 缺失回落本地：61000 → 01:01', (tester) async {
      final practice = _FakePracticeService()..detail = _detail();
      await tester.pumpWidget(_host(_record(durationMs: 61000), practice));
      await tester.pumpAndSettle();

      expect(find.text('用时'), findsOneWidget);
      expect(find.text('01:01'), findsOneWidget);
    });

    testWidgets('服务端缺失且本地 0 → --，不是 00:00', (tester) async {
      final practice = _FakePracticeService()..detail = _detail();
      await tester.pumpWidget(_host(_record(durationMs: 0), practice));
      await tester.pumpAndSettle();

      expect(find.text('用时'), findsOneWidget);
      // 答对 16 / 正确率 80% 均非 '--'，唯一的 '--' 就是用时未知态。
      expect(find.text('--'), findsOneWidget);
      expect(find.text('00:00'), findsNothing);
    });

    testWidgets('无服务端详情（接口返回 null）：本地 90000 → 01:30', (tester) async {
      final practice = _FakePracticeService(); // detail 默认 null
      await tester.pumpWidget(_host(_record(durationMs: 90000), practice));
      await tester.pumpAndSettle();

      expect(practice.detailCalls, <String>['sess-1']);
      expect(find.text('用时'), findsOneWidget);
      expect(find.text('01:30'), findsOneWidget);
    });
  });
}