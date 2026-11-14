import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/core/kv_store.dart';
import 'package:routepass/core/theme.dart';
import 'package:routepass/models/answer_record.dart';
import 'package:routepass/services/bank/answer_record_service.dart';
import 'package:routepass/widgets/answer_records_card.dart';
import 'package:routepass/widgets/daily_card_border_painter.dart';

AnswerRecord _record({
  String id = 'rec-1',
  String setId = 'VLAN',
  String mode = 'practice',
  String kind = 'completion',
  int target = 20,
  int answered = 20,
  int? correct = 16,
  int? score,
  int updatedAt = 1000,
}) {
  return AnswerRecord(
    id: id,
    setId: setId,
    setTitle: 'VLAN',
    mode: mode,
    kind: kind,
    targetCount: target,
    answeredCount: answered,
    totalCount: 100,
    correctCount: correct,
    score: score,
    durationMs: 760000,
    createdAt: updatedAt,
    updatedAt: updatedAt,
  );
}

Widget _host(Widget child) {
  return MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: Center(child: SizedBox(width: 348, child: child)),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AnswerRecordsCard', () {
    testWidgets('空态高度 200 且显示暂无答题记录', (tester) async {
      await tester.pumpWidget(
        _host(const AnswerRecordsCard(records: <AnswerRecord>[])),
      );

      expect(find.text('暂无答题记录'), findsOneWidget);
      expect(find.text('答题记录'), findsOneWidget);
      expect(tester.getSize(find.byType(AnswerRecordsCard)).height, 200);
    });

    testWidgets('展示完成记录：次数、正确率与进度条', (tester) async {
      await tester.pumpWidget(
        _host(AnswerRecordsCard(records: <AnswerRecord>[_record()])),
      );

      expect(find.text('已完成 · 20/20 题'), findsOneWidget);
      expect(find.textContaining('练习 · VLAN'), findsOneWidget);
      expect(find.text('正确率 80%'), findsOneWidget);
      final bars = find.descendant(
        of: find.byType(AnswerRecordsCard),
        matching: find.byType(FractionallySizedBox),
      );
      expect(bars, findsOneWidget);
      expect((tester.widget<FractionallySizedBox>(bars)).widthFactor, 1.0);
    });

    testWidgets('断点行显示继续，点击回调', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(
        _host(
          AnswerRecordsCard(
            records: <AnswerRecord>[
              _record(id: 'bp', kind: 'breakpoint', answered: 15, correct: 12),
            ],
            onContinue: () => tapped++,
          ),
        ),
      );

      expect(find.text('断点 · 15/20 题'), findsOneWidget);
      await tester.tap(find.text('继续'));
      expect(tapped, 1);
    });

    testWidgets('内容超过可视高上限时卡内滚动', (tester) async {
      final records = <AnswerRecord>[
        for (var i = 0; i < 20; i++) _record(id: 'rec-$i', updatedAt: 2000 - i),
      ];
      await tester.pumpWidget(_host(AnswerRecordsCard(records: records)));

      // 默认 600 高视口 × 0.5 = 300 上限。
      expect(tester.getSize(find.byType(AnswerRecordsCard)).height, 300);
      expect(
        find.descendant(
          of: find.byType(AnswerRecordsCard),
          matching: find.byType(ListView),
        ),
        findsOneWidget,
      );
    });

    testWidgets('标题缺口与错题本同算法：gapStart 20，gapEnd = 20+标题宽+20', (tester) async {
      await tester.pumpWidget(
        _host(const AnswerRecordsCard(records: <AnswerRecord>[])),
      );

      final paint = tester.widget<CustomPaint>(
        find
            .descendant(
              of: find.byType(AnswerRecordsCard),
              matching: find.byType(CustomPaint),
            )
            .first,
      );
      final painter = paint.painter! as DailyCardBorderPainter;
      expect(painter.gapStart, 20);
      expect(painter.gapEnd, greaterThan(60));
      expect(painter.radius, AppRadii.card);
    });
  });

  group('KvAnswerRecordService', () {
    late KvStore kv;
    late KvAnswerRecordService service;

    setUp(() {
      kv = InMemoryKvStore();
      service = KvAnswerRecordService(kvStore: kv);
    });

    test('完成记录按 id 更新，不新建', () {
      final first = _record(id: 'c1', answered: 20);
      service.upsert(first);
      service.upsert(first.copyWith(answeredCount: 35, updatedAt: 2000));

      final records = service.recordsFor(setId: 'VLAN', mode: 'practice');
      expect(records.length, 1);
      expect(records.single.answeredCount, 35);
      expect(service.breakpointOf(setId: 'VLAN', mode: 'practice'), isNull);
    });

    test('断点同 setId+mode 去重并复用 id', () {
      service.upsert(_record(id: 'bp1', kind: 'breakpoint', answered: 10));
      service.upsert(
        _record(id: 'bp2', kind: 'breakpoint', answered: 15, updatedAt: 3000),
      );

      final records = service.recordsFor(setId: 'VLAN', mode: 'practice');
      expect(records.length, 1);
      expect(records.single.id, 'bp1');
      expect(records.single.answeredCount, 15);
    });

    test('完成记录回收同 setId+mode 的旧断点', () {
      service.upsert(_record(id: 'bp', kind: 'breakpoint', answered: 15));
      expect(service.breakpointOf(setId: 'VLAN', mode: 'practice'), isNotNull);

      service.upsert(_record(id: 'c1', kind: 'completion', answered: 20));

      final records = service.recordsFor(setId: 'VLAN', mode: 'practice');
      expect(records.length, 1);
      expect(records.single.id, 'c1');
      expect(records.single.kind, 'completion');
      expect(service.breakpointOf(setId: 'VLAN', mode: 'practice'), isNull);
    });

    test('完成记录不动其它模式 / 其它套卷的断点', () {
      service.upsert(
        _record(id: 'bp-exam', mode: 'exam', kind: 'breakpoint', answered: 5),
      );
      service.upsert(
        _record(id: 'bp-other', setId: 'OSPF', kind: 'breakpoint', answered: 5),
      );

      service.upsert(_record(id: 'c1', kind: 'completion', answered: 20));

      expect(service.breakpointOf(setId: 'VLAN', mode: 'exam'), isNotNull);
      expect(service.breakpointOf(setId: 'OSPF', mode: 'practice'), isNotNull);
    });

    test('单 set 最多 20 条，超出丢最旧', () {
      for (var i = 0; i < 25; i++) {
        service.upsert(
          _record(id: 'rec-$i', answered: 20, updatedAt: 1000 + i),
        );
      }
      final records = service.recordsFor(setId: 'VLAN', mode: 'practice');
      expect(records.length, 10); // recordsFor 展示上限 10
      // 最新的是 updatedAt 最大的 rec-24。
      expect(records.first.id, 'rec-24');
    });

    test('pendingSync 返回未同步记录，markSynced 后可清空', () {
      service.upsert(_record(id: 'a'));
      service.upsert(_record(id: 'b'));
      expect(service.pendingSync().length, 2);

      service.markSynced('a', 'server-a');
      final pending = service.pendingSync();
      expect(pending.length, 1);
      expect(pending.single.id, 'b');
    });

    test('损坏 JSON 丢弃不抛错', () {
      kv.setString(KvStore.keyAnswerRecords, '{not json');
      expect(service.recordsFor(setId: 'VLAN', mode: 'practice'), isEmpty);
    });
  });
}
