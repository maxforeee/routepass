import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/app.dart';
import 'package:routepass/core/service_locator.dart';
import 'package:routepass/pages/base/login_page.dart';
import 'package:routepass/widgets/capsule_nav_bar.dart';
import 'package:routepass/services/mock/mock_answer_record_service.dart';
import 'package:routepass/services/mock/mock_answer_session_service.dart';
import 'package:routepass/services/mock/mock_auth_service.dart';
import 'package:routepass/services/mock/mock_bank_manifest_service.dart';
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
import 'package:routepass/services/sync_mode_service.dart';

import 'support/fake_connectivity.dart';

void initTestServices() {
  final syncService = MockSyncService();
  // 测试默认离线：同步条显示“本地模式”，不依赖真实网络。
  final connectivity = FakeConnectivityService();
  ServiceLocator.init(
    questionRepository: MockQuestionRepository(),
    bankManifestService: MockBankManifestService(),
    answerRecordService: MockAnswerRecordService(),
    answerSessionService: MockAnswerSessionService(),
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
    syncService: syncService,
    contentService: MockContentService(),
    syncModeService: SyncModeService(
      connectivity: connectivity,
      syncService: syncService,
      isLoggedIn: () async =>
          (await ServiceLocator.authService.getCurrentUser()) != null,
    ),
  );
}

Future<void> loginToHome(WidgetTester tester) async {
  await tester.pumpWidget(const RoutePassApp());
  await tester.pumpAndSettle();
  // Splash dwells ~2s: pumpAndSettle stops while the dwell timer is pending
  // (no frame scheduled), so advance fake time past it explicitly.
  await tester.pump(const Duration(seconds: 2));
  // 登录页顶部图形无限动画，不能 pumpAndSettle：显式推帧走完 splash→login 转场。
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));

  if (find.byType(LoginPage).tryEvaluate()) {
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '13800138000');
    await tester.enterText(fields.at(1), 'Demo1234');
    // 默认 800x600 视口下 login 按钮在折叠线以下，先滚进视口再点。
    await tester.ensureVisible(find.text('login'));
    await tester.pump();
    await tester.tap(find.text('login'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
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
