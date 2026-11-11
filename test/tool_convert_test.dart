import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/core/service_locator.dart';
import 'package:routepass/pages/toolbox/cidr_page.dart';
import 'package:routepass/pages/toolbox/ip_convert_page.dart';
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

  testWidgets('IP 转十/十六/二进制', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: IpConvertPage()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '192.168.1.1');
    await tester.tap(find.widgetWithText(FilledButton, '转换'));
    await tester.pumpAndSettle();
    expect(find.text('3232235777'), findsOneWidget);
    expect(find.text('0xC0A80101'), findsOneWidget);
    expect(find.text('11000000.10101000.00000001.00000001'), findsOneWidget);
  });

  testWidgets('纯前缀 /24 转掩码', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: IpConvertPage()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '/24');
    await tester.tap(find.widgetWithText(FilledButton, '转换'));
    await tester.pumpAndSettle();
    // '/24' 既是输入框内容又是结果值，同 255.255.255.192 用 findsWidgets
    expect(find.text('/24'), findsWidgets);
    expect(find.text('255.255.255.0'), findsOneWidget);
  });

  testWidgets('无法识别的输入显示错误', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: IpConvertPage()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'abc');
    await tester.tap(find.widgetWithText(FilledButton, '转换'));
    await tester.pumpAndSettle();
    expect(find.text('无法识别的输入'), findsOneWidget);
  });

  testWidgets('掩码 255.255.255.192 转 /26 与 62 台主机', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: CidrPage()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '255.255.255.192');
    await tester.tap(find.widgetWithText(FilledButton, '转换'));
    await tester.pumpAndSettle();
    expect(find.text('/26'), findsOneWidget);
    expect(find.text('255.255.255.192'), findsWidgets);
    expect(find.text('62'), findsOneWidget);
  });

  testWidgets('前缀 /25 转掩码与 126 台主机', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: CidrPage()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '/25');
    await tester.tap(find.widgetWithText(FilledButton, '转换'));
    await tester.pumpAndSettle();
    // '/25' 同上，输入框与结果行各出现一次
    expect(find.text('/25'), findsWidgets);
    expect(find.text('255.255.255.128'), findsOneWidget);
    expect(find.text('126'), findsOneWidget);
  });
}
