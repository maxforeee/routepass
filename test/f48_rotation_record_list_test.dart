/// F48：7 天轮回批次进答题记录列表（A12）。
///
/// 全部用 fake / 内存 kv，不发真实网络请求。服务端记录项一律经
/// `PracticeRecordSummary.fromJson` 构造（契约 JSON 形状），因此本文件
/// 在未改动的旧代码上也能编译运行——映射 / 删除守卫 / 前置页分组用例
/// 在旧代码上是行为性失败（fail-first），回归用例在两侧都通过。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/core/kv_store.dart';
import 'package:routepass/core/theme.dart';
import 'package:routepass/models/answer_record.dart';
import 'package:routepass/models/practice.dart';
import 'package:routepass/models/question.dart';
import 'package:routepass/pages/bank/answer_record_detail_page.dart';
import 'package:routepass/pages/bank/set_detail_page.dart';
import 'package:routepass/services/bank/answer_record_service.dart';
import 'package:routepass/services/bank/answer_session_service.dart';
import 'package:routepass/services/bank/practice_service.dart';
import 'package:routepass/services/mock/mock_bank_manifest_service.dart';
import 'package:routepass/services/mock/mock_practice_service.dart';
import 'package:routepass/services/mock/mock_question_repository.dart';
import 'package:routepass/widgets/answer_records_card.dart';

import 'test_helpers.dart';

/// 服务端记录项（GET /practice/records 的 items 元素，契约 JSON）。
PracticeRecordSummary _summary({
  required String id,
  String module = '',
  required String status,
  int answered = 10,
  int correct = 8,
  bool isRotation = false,
  String? bankId,
  int started = 1000,
  int? completed,
}) {
  return PracticeRecordSummary.fromJson(<String, dynamic>{
    'id': id,
    'module': module,
    'status': status,
    'answeredCount': answered,
    'correctCount': correct,
    'startedAt': started,
    'completedAt': completed,
    'bankId': bankId,
    'isRotation': isRotation,
  });
}

/// 本地断点记录（setId '' = 全模块练习，旧代码里进行中轮回行会错误匹配它）。
AnswerRecord _breakpoint({String setId = '', String mode = 'practice'}) {
  return AnswerRecord(
    id: 'rec-bp-$setId',
    setId: setId,
    setTitle: setId.isEmpty ? '全部' : setId,
    mode: mode,
    kind: 'breakpoint',
    targetCount: 20,
    answeredCount: 5,
    totalCount: 20,
    durationMs: 0,
    createdAt: 500,
    updatedAt: 500,
  );
}

/// 轮回完成记录（syncFromServer 的产物形状，页面用例直接种入本地 kv）。
AnswerRecord _rotationRecord({String serverId = 'rot-1'}) {
  return AnswerRecord(
    id: 'srv-$serverId',
    setId: '',
    setTitle: '7天轮回',
    mode: 'rotation',
    kind: 'completion',
    targetCount: 10,
    answeredCount: 10,
    totalCount: 10,
    correctCount: 8,
    durationMs: 60000,
    createdAt: 1000,
    updatedAt: 2000,
    synced: true,
    serverId: serverId,
  );
}

class _FakePracticeService implements PracticeService {
  PracticeRecordDetail? detail;
  bool deleteResult = true;
  final List<String> detailCalls = <String>[];
  final List<String> deleteCalls = <String>[];

  @override
  Future<PracticeRecordDetail?> getRecordDetail(String sessionId) async {
    detailCalls.add(sessionId);
    return detail;
  }

  @override
  Future<bool> deleteRecord(String sessionId) async {
    deleteCalls.add(sessionId);
    return deleteResult;
  }

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

Widget _detailHost({
  required AnswerRecord record,
  required _FakePracticeService practice,
  required KvAnswerRecordService records,
  required KvAnswerSessionService sessions,
}) {
  return MaterialApp(
    theme: AppTheme.light,
    home: AnswerRecordDetailPage(
      args: <String, Object?>{'record': record},
      practiceService: practice,
      recordService: records,
      sessionService: sessions,
    ),
  );
}

Widget _prePageHost({
  required String mode,
  required String setId,
  required KvAnswerRecordService records,
  required KvAnswerSessionService sessions,
}) {
  return MaterialApp(
    theme: AppTheme.light,
    home: SetDetailPage(
      args: <String, Object?>{'mode': mode, 'setId': setId, 'drawCount': 100},
      manifestService: MockBankManifestService(),
      questionRepository: MockQuestionRepository(),
      recordService: records,
      sessionService: sessions,
      practiceService: MockPracticeService(),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initTestServices();

  late KvStore kv;

  setUp(() {
    kv = InMemoryKvStore();
  });

  group('syncFromServer 轮回映射', () {
    test('已交卷轮回映射为全局完成记录，且不标记任何本地断点', () async {
      final service = KvAnswerRecordService(
        kvStore: kv,
        serverRecords: () async => <PracticeRecordSummary>[
          _summary(
            id: 'rot-1',
            status: 'submitted',
            isRotation: true,
            bankId: 'bank_default',
            answered: 10,
            correct: 8,
            completed: 2000,
          ),
        ],
      );
      // 全模块练习断点（setId ''）：旧代码把 submitted 轮回当进行中，
      // 会按 module '' 错误匹配并标记它。
      service.upsert(_breakpoint());

      expect(await service.syncFromServer(), isTrue);

      final rotation = service.recordsFor(setId: '', mode: 'rotation');
      expect(rotation, hasLength(1));
      final r = rotation.single;
      expect(r.setId, '');
      expect(r.setTitle, '7天轮回');
      expect(r.mode, 'rotation');
      expect(r.kind, 'completion');
      expect(r.targetCount, 10);
      expect(r.answeredCount, 10);
      expect(r.correctCount, 8);
      expect(r.synced, isTrue);
      expect(r.serverId, 'rot-1');

      final bp = service.breakpointOf(setId: '', mode: 'practice');
      expect(bp, isNotNull);
      expect(bp!.synced, isFalse);
      expect(bp.serverId, isNull);
    });

    test('进行中轮回不造展示记录，也不标记本地断点', () async {
      final service = KvAnswerRecordService(
        kvStore: kv,
        serverRecords: () async => <PracticeRecordSummary>[
          _summary(
            id: 'rot-2',
            status: 'in_progress',
            isRotation: true,
            bankId: 'bank_default',
            answered: 3,
          ),
        ],
      );
      service.upsert(_breakpoint());

      expect(await service.syncFromServer(), isTrue);

      expect(service.recordsFor(setId: '', mode: 'rotation'), isEmpty);
      // 也没有落成 practice 完成记录。
      final practiceCompletions = service
          .recordsFor(setId: '', mode: 'practice')
          .where((r) => r.isCompletion);
      expect(practiceCompletions, isEmpty);
      final bp = service.breakpointOf(setId: '', mode: 'practice');
      expect(bp, isNotNull);
      expect(bp!.synced, isFalse);
      expect(bp.serverId, isNull);
    });

    test('模块练习映射不变：完成按模块落记录，进行中只标记同模块断点', () async {
      final service = KvAnswerRecordService(
        kvStore: kv,
        serverRecords: () async => <PracticeRecordSummary>[
          _summary(
            id: 'mod-1',
            module: 'VLAN',
            status: 'completed',
            answered: 20,
            correct: 16,
            completed: 3000,
          ),
          _summary(
            id: 'mod-2',
            module: 'OSPF',
            status: 'in_progress',
            answered: 5,
          ),
        ],
      );
      service.upsert(_breakpoint(setId: 'OSPF'));

      expect(await service.syncFromServer(), isTrue);

      final vlan = service.recordsFor(setId: 'VLAN', mode: 'practice');
      expect(vlan, hasLength(1));
      expect(vlan.single.setTitle, 'VLAN');
      expect(vlan.single.kind, 'completion');
      expect(vlan.single.targetCount, 20);
      expect(vlan.single.serverId, 'mod-1');

      final ospfBp = service.breakpointOf(setId: 'OSPF', mode: 'practice');
      expect(ospfBp, isNotNull);
      expect(ospfBp!.synced, isTrue);
      expect(ospfBp.serverId, 'mod-2');

      expect(service.recordsFor(setId: '', mode: 'rotation'), isEmpty);
    });
  });

  group('详情页轮回守卫', () {
    late KvAnswerRecordService records;
    late KvAnswerSessionService sessions;
    late _FakePracticeService practice;

    setUp(() {
      records = KvAnswerRecordService(kvStore: kv);
      sessions = KvAnswerSessionService(kvStore: kv);
      practice = _FakePracticeService();
    });

    testWidgets('轮回记录隐藏删除按钮，标题为 7天轮回（无模块名）', (tester) async {
      practice.detail = null; // 离线回落本地摘要
      await tester.pumpWidget(
        _detailHost(
          record: _rotationRecord(),
          practice: practice,
          records: records,
          sessions: sessions,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('答题记录详情'), findsOneWidget);
      expect(find.textContaining('7天轮回 · 已完成'), findsOneWidget);
      expect(find.textContaining('练习 ·'), findsNothing);
      expect(find.text('删除记录'), findsNothing);
      // 查看试卷保留：详情 / 试卷接口本就能解析轮回会话。
      expect(find.text('查看试卷'), findsOneWidget);
      expect(practice.deleteCalls, isEmpty);
    });

    testWidgets('普通练习记录仍显示删除按钮（回归）', (tester) async {
      practice.detail = null;
      final record = AnswerRecord(
        id: 'srv-sess-1',
        setId: 'VLAN',
        setTitle: 'VLAN',
        mode: 'practice',
        kind: 'completion',
        targetCount: 20,
        answeredCount: 20,
        totalCount: 20,
        correctCount: 16,
        durationMs: 760000,
        createdAt: 1000,
        updatedAt: 1000,
        synced: true,
        serverId: 'sess-1',
      );
      await tester.pumpWidget(
        _detailHost(
          record: record,
          practice: practice,
          records: records,
          sessions: sessions,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('练习 · VLAN'), findsOneWidget);
      expect(find.text('删除记录'), findsOneWidget);
    });
  });

  group('前置页轮回分组', () {
    testWidgets('练习前置页记录卡渲染 7天轮回 分组与批次行', (tester) async {
      final records = KvAnswerRecordService(kvStore: kv);
      final sessions = KvAnswerSessionService(kvStore: kv);
      records.upsert(_rotationRecord());

      await tester.pumpWidget(
        _prePageHost(
          mode: 'practice',
          setId: 'VLAN',
          records: records,
          sessions: sessions,
        ),
      );
      await tester.pumpAndSettle();

      // 记录卡在页面最底部，先滚进视口；组标题限定在记录卡内（页面另有
      // 7天轮回入口行，不能全局匹配）。
      final groupHeader = find.descendant(
        of: find.byType(AnswerRecordsCard),
        matching: find.text('7天轮回'),
      );
      await tester.ensureVisible(groupHeader);
      await tester.pumpAndSettle();

      expect(groupHeader, findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AnswerRecordsCard),
          matching: find.text('已完成 · 10/10 题'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('考试前置页不渲染轮回分组（仅练习）', (tester) async {
      final records = KvAnswerRecordService(kvStore: kv);
      final sessions = KvAnswerSessionService(kvStore: kv);
      records.upsert(_rotationRecord());

      await tester.pumpWidget(
        _prePageHost(
          mode: 'exam',
          setId: 'h3cne-2026-01',
          records: records,
          sessions: sessions,
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byType(AnswerRecordsCard));
      await tester.pumpAndSettle();

      expect(find.text('7天轮回'), findsNothing);
    });
  });
}
