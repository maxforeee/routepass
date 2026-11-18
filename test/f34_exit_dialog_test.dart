/// F34：退出确认文案必须如实指向真实恢复路径。
///
/// 首页 H-B1「继续学习」已随 F14c 移除（home_test / bank_nav_test 守卫其
/// 不存在），旧文案「退出后可在首页“继续学习”恢复作答」是假承诺：
/// - 套卷答题（QuizPage）退出写断点记录，真实入口是套卷详情页
///   「答题记录」断点行的「继续」（set_detail_page 的 onContinue）；
/// - 旧答题页（AnswerPage）不写断点、home.continue 指针无页面渲染，
///   没有续答入口，文案如实说明进度不保留。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/pages/bank/answer_widgets.dart';

Future<void> _openDialog(
  WidgetTester tester,
  Future<bool> Function(BuildContext context) open,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () => open(context),
              child: const Text('打开退出确认'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开退出确认'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('默认文案指向套卷详情页答题记录断点「继续」，不再承诺首页恢复', (tester) async {
    await _openDialog(tester, (context) => showExitConfirmDialog(context));

    expect(find.text('退出答题'), findsOneWidget);
    expect(
      find.text('退出后可在套卷详情页「答题记录」的断点行点「继续」恢复作答。'),
      findsOneWidget,
    );
    expect(find.textContaining('首页'), findsNothing);
    expect(find.textContaining('继续学习'), findsNothing);
    expect(
      find.widgetWithText(FilledButton, '退出并保留进度'),
      findsOneWidget,
    );
  });

  testWidgets('旧答题页传入如实文案：进度不保留、确认按钮「退出」', (tester) async {
    await _openDialog(
      tester,
      (context) => showExitConfirmDialog(
        context,
        content: '退出后本次作答进度不保留。',
        confirmLabel: '退出',
      ),
    );

    expect(find.text('退出后本次作答进度不保留。'), findsOneWidget);
    expect(
      find.text('退出后可在套卷详情页「答题记录」的断点行点「继续」恢复作答。'),
      findsNothing,
    );
    expect(find.widgetWithText(FilledButton, '退出'), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, '退出并保留进度'),
      findsNothing,
    );
  });
}
