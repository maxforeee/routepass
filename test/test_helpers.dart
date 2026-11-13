import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/app.dart';
import 'package:routepass/core/service_locator.dart';
import 'package:routepass/widgets/capsule_nav_bar.dart';
import 'package:routepass/services/mock/mock_auth_service.dart';
import 'package:routepass/services/mock/mock_cli_service.dart';
import 'package:routepass/services/mock/mock_content_service.dart';
import 'package:routepass/services/mock/mock_daily_practice_service.dart';
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

void initTestServices() {
  ServiceLocator.init(
    questionRepository: MockQuestionRepository(),
    practiceService: MockPracticeService(),
    examService: MockExamService(),
    dailyPracticeService: MockDailyPracticeService(),
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

Future<void> loginToHome(WidgetTester tester) async {
  await tester.pumpWidget(const RoutePassApp());
  await tester.pumpAndSettle();
  // Splash dwells ~2s: pumpAndSettle stops while the dwell timer is pending
  // (no frame scheduled), so advance fake time past it explicitly.
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();

  if (find.text('欢迎回来').tryEvaluate()) {
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '13800138000');
    await tester.enterText(fields.at(1), 'Demo1234');
    await tester.tap(find.widgetWithText(FilledButton, '登录 / 注册'));
    await tester.pumpAndSettle();
    // Walk past the login-success Snackbar's 4s auto-dismiss timer.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  // A previous test may have left another tab active (AppShell restores kv
  // `ui.lastTab` at startup); always land on the home tab first.
  await tester.tap(
    find.descendant(of: find.byType(CapsuleNavBar), matching: find.text('首页')),
  );
  await tester.pumpAndSettle();

  // G1b: greeting block shows time-of-day greeting + nickname, no AppBar.
  expect(find.textContaining('好！'), findsOneWidget);
  expect(find.text('Max'), findsOneWidget);
}
