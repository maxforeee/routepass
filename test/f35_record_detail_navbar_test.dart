/// F35：答题记录详情页（/bank/record-detail）与试卷页（/bank/record-paper）
/// 和作答页、套卷详情页同属全屏流程，push 后胶囊底栏必须隐藏，pop 回题库页
/// 恢复。沿用 bank_nav_test 的办法：登录进题库 tab，在内层 Navigator 上
/// pushNamed，断言树中有无 CapsuleNavBar（隐藏动画播完后底栏移出树）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/models/answer_record.dart';
import 'package:routepass/pages/bank/answer_record_detail_page.dart';
import 'package:routepass/pages/bank/answer_record_paper_page.dart';
import 'package:routepass/pages/bank/module_list_page.dart';
import 'package:routepass/router/app_router.dart';
import 'package:routepass/widgets/capsule_nav_bar.dart';

import 'test_helpers.dart';

/// 首页快捷入口也有同名文字，切 tab 必须把 finder 限定在胶囊导航里。
Finder _navTab(String label) =>
    find.descendant(of: find.byType(CapsuleNavBar), matching: find.text(label));

/// 本地完成记录（无 serverId）：详情页不请求服务端、无加载骨架，试卷页
/// 显示「暂无试卷」诚实空态——不依赖网络，也不虚构卷面。
AnswerRecord _localRecord() {
  return AnswerRecord(
    id: 'rec-f35-1',
    setId: 'VLAN',
    setTitle: 'VLAN',
    mode: 'practice',
    kind: 'completion',
    targetCount: 20,
    answeredCount: 20,
    totalCount: 100,
    correctCount: 18,
    durationMs: 120000,
    createdAt: DateTime(2026, 11, 17, 9).millisecondsSinceEpoch,
    updatedAt: DateTime(2026, 11, 17, 9, 2).millisecondsSinceEpoch,
  );
}

Future<void> _openBankTab(WidgetTester tester) async {
  await loginToHome(tester);
  await tester.tap(_navTab('题库'));
  await tester.pumpAndSettle();
}

Future<void> _pushRecordDetail(WidgetTester tester) async {
  final context = tester.element(find.byType(BankModuleListPage));
  Navigator.of(context).pushNamed(
    AppRoutes.bankRecordDetail,
    arguments: <String, Object?>{'record': _localRecord()},
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initTestServices();

  testWidgets('答题记录详情页隐藏胶囊导航，返回后恢复', (tester) async {
    await _openBankTab(tester);
    expect(find.byType(CapsuleNavBar), findsOneWidget);

    await _pushRecordDetail(tester);
    expect(find.byType(AnswerRecordDetailPage), findsOneWidget);
    expect(find.text('答题记录详情'), findsOneWidget);
    expect(find.byType(CapsuleNavBar), findsNothing);

    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.byType(AnswerRecordDetailPage), findsNothing);
    expect(find.byType(CapsuleNavBar), findsOneWidget);
  });

  testWidgets('记录试卷页隐藏胶囊导航，退回详情页仍隐藏，回题库恢复', (tester) async {
    await _openBankTab(tester);
    await _pushRecordDetail(tester);
    expect(find.byType(CapsuleNavBar), findsNothing);

    // 走真实入口：详情页「查看试卷」push 试卷页（本地记录 → 暂无试卷空态）。
    // F39 L9：finder 限定在详情页内，树里别处出现同名文字也不歧义。
    final viewPaper = find.descendant(
      of: find.byType(AnswerRecordDetailPage),
      matching: find.text('查看试卷'),
    );
    await tester.ensureVisible(viewPaper);
    await tester.pumpAndSettle();
    await tester.tap(viewPaper);
    await tester.pumpAndSettle();
    expect(find.byType(AnswerRecordPaperPage), findsOneWidget);
    expect(find.text('暂无试卷'), findsOneWidget);
    expect(find.byType(CapsuleNavBar), findsNothing);

    // 退回详情页：仍是全屏流程，底栏保持隐藏（didPop 回报告诉外壳）。
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.byType(AnswerRecordDetailPage), findsOneWidget);
    expect(find.byType(CapsuleNavBar), findsNothing);

    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.byType(BankModuleListPage), findsOneWidget);
    expect(find.byType(CapsuleNavBar), findsOneWidget);
  });
}
