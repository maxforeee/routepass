import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/core/service_locator.dart';
import 'package:routepass/pages/toolbox/cli_page.dart';
import 'package:routepass/pages/toolbox/ping_page.dart';
import 'package:routepass/pages/toolbox/portscan_page.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _initServices();

  testWidgets('命令速查显示 4 条样例命令', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: CliPage()));
    await tester.pumpAndSettle();
    expect(find.text('display vlan'), findsOneWidget);
    expect(find.text('vlan 10'), findsOneWidget);
    expect(find.text('display ospf peer'), findsOneWidget);
    expect(find.text('ip address 192.168.1.1 24'), findsOneWidget);
  });

  testWidgets('命令速查搜索 ospf 只剩 1 条', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: CliPage()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'ospf');
    await tester.pumpAndSettle();
    expect(find.text('display ospf peer'), findsOneWidget);
    expect(find.text('display vlan'), findsNothing);
  });

  testWidgets('点命令卡复制出已复制提示', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: CliPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('display vlan'));
    await tester.pumpAndSettle();
    expect(find.text('已复制'), findsOneWidget);
  });

  testWidgets('Ping 开始后显示待接本地服务', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PingPage()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '192.168.1.1');
    await tester.tap(find.widgetWithText(FilledButton, '开始'));
    await tester.pumpAndSettle();
    expect(find.textContaining('待接本地服务'), findsWidgets);
  });

  testWidgets('端口扫描：未确认不能开始，确认后开始显示占位', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PortScanPage()));
    await tester.pumpAndSettle();
    // 进页弹合规确认。
    expect(find.text('合规确认'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(find.text('合规确认'), findsNothing);
    // 未确认时点开始，再弹确认。
    await tester.tap(find.widgetWithText(FilledButton, '开始'));
    await tester.pumpAndSettle();
    expect(find.text('合规确认'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '我已知晓并确认'));
    await tester.pumpAndSettle();
    expect(find.text('合规确认'), findsNothing);
    // 确认后点开始，显示占位。
    await tester.enterText(find.byType(TextField), '192.168.1.1');
    await tester.tap(find.widgetWithText(FilledButton, '开始'));
    await tester.pumpAndSettle();
    expect(find.textContaining('待接本地服务'), findsOneWidget);
  });
}
