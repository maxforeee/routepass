import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/core/service_locator.dart';
import 'package:routepass/pages/knowledge/knowledge_home_page.dart';
import 'package:routepass/services/mock/mock_auth_service.dart';
import 'package:routepass/services/mock/mock_cli_service.dart';
import 'package:routepass/services/mock/mock_content_service.dart';
import 'package:routepass/services/mock/mock_exam_service.dart';
import 'package:routepass/services/mock/mock_favorite_service.dart';
import 'package:routepass/services/mock/mock_knowledge_repository.dart';
import 'package:routepass/services/mock/mock_ping_service.dart';
import 'package:routepass/services/mock/mock_port_scan_service.dart';
import 'package:routepass/services/mock/mock_practice_service.dart';
import 'package:routepass/services/mock/mock_question_repository.dart';
import 'package:routepass/services/mock/mock_search_service.dart';
import 'package:routepass/services/mock/mock_stats_service.dart';
import 'package:routepass/services/mock/mock_sync_service.dart';
import 'package:routepass/services/mock/mock_wrong_service.dart';
import 'package:routepass/services/toolbox/ip_convert_service_impl.dart';
import 'package:routepass/services/toolbox/subnet_calc_service_impl.dart';

/// 与 shell_test.dart 相同的一套 Mock/本地实现装配；重复调用直接返回。
void _initServices() {
  ServiceLocator.init(
    questionRepository: MockQuestionRepository(),
    practiceService: MockPracticeService(),
    examService: MockExamService(),
    wrongService: MockWrongService(),
    favoriteService: MockFavoriteService(),
    statsService: MockStatsService(),
    knowledgeRepository: MockKnowledgeRepository(),
    searchService: MockSearchService(),
    subnetCalcService: LocalSubnetCalcService(),
    ipConvertService: LocalIpConvertService(),
    pingService: MockPingService(),
    portScanService: MockPortScanService(),
    cliService: MockCliService(),
    authService: MockAuthService(),
    syncService: MockSyncService(),
    contentService: MockContentService(),
  );
}

Future<void> _pumpPage(WidgetTester tester) async {
  await tester.pumpWidget(
    const MaterialApp(home: KnowledgeHomePage()),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _initServices();

  testWidgets('加载章节与小节', (tester) async {
    await _pumpPage(tester);

    expect(find.text('样例章节：VLAN 基础'), findsOneWidget);
    expect(find.text('样例小节：VLAN 概念'), findsOneWidget);
    expect(find.text('样例章节：子网划分基础'), findsOneWidget);
    expect(find.text('已掌握 0/2'), findsOneWidget);
  });

  testWidgets('点小节折叠/展开知识点行，点行展开面板', (tester) async {
    await _pumpPage(tester);

    // 默认展开：知识点行可见。
    expect(find.text('样例知识点：VLAN 是什么'), findsOneWidget);
    // 点小节 header 折叠，行消失；再点展开，行回来。
    await tester.tap(find.text('样例小节：VLAN 概念'));
    await tester.pumpAndSettle();
    expect(find.text('样例知识点：VLAN 是什么'), findsNothing);
    await tester.tap(find.text('样例小节：VLAN 概念'));
    await tester.pumpAndSettle();
    expect(find.text('样例知识点：VLAN 是什么'), findsOneWidget);
    // 点行展开面板，摘要出现。
    await tester.tap(find.text('样例知识点：VLAN 是什么'));
    await tester.pumpAndSettle();
    expect(
      find.text('这是一条样例知识点摘要，仅用于界面展示。'),
      findsOneWidget,
    );
    expect(find.text('练一练'), findsOneWidget);
    expect(find.text('查看详情'), findsOneWidget);
    // 再点行收起面板。
    await tester.tap(find.text('样例知识点：VLAN 是什么'));
    await tester.pumpAndSettle();
    expect(
      find.text('这是一条样例知识点摘要，仅用于界面展示。'),
      findsNothing,
    );
  });

  testWidgets('掌握切换更新进度', (tester) async {
    await _pumpPage(tester);

    await tester.tap(find.byIcon(Icons.radio_button_unchecked).first);
    await tester.pumpAndSettle();
    expect(find.text('已掌握 1/2'), findsOneWidget);
    // 再点已掌握的 icon 取消。
    await tester.tap(find.byIcon(Icons.check_circle).first);
    await tester.pumpAndSettle();
    expect(find.text('已掌握 0/2'), findsOneWidget);
  });

  testWidgets('搜索过滤：只剩命中点，清空恢复', (tester) async {
    await _pumpPage(tester);

    await tester.enterText(find.byType(TextField), '子网');
    await tester.pumpAndSettle();
    expect(find.text('样例知识点：子网掩码'), findsOneWidget);
    expect(find.text('样例知识点：VLAN 是什么'), findsNothing);
    expect(find.text('样例章节：VLAN 基础'), findsNothing);
    // 清空恢复。
    await tester.tap(find.byIcon(Icons.clear));
    await tester.pumpAndSettle();
    expect(find.text('样例知识点：VLAN 是什么'), findsOneWidget);
    expect(find.text('样例知识点：子网掩码'), findsOneWidget);
  });

  testWidgets('展开态持久化：重建页面后面板仍展开', (tester) async {
    await _pumpPage(tester);

    await tester.tap(find.text('样例知识点：VLAN 是什么'));
    await tester.pumpAndSettle();
    expect(
      find.text('这是一条样例知识点摘要，仅用于界面展示。'),
      findsOneWidget,
    );
    // 重建页面（kv 里的展开态应恢复）。
    await _pumpPage(tester);
    expect(
      find.text('这是一条样例知识点摘要，仅用于界面展示。'),
      findsOneWidget,
    );
  });
}
