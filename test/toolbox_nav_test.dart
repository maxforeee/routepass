import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/app.dart';
import 'package:routepass/core/service_locator.dart';
import 'package:routepass/pages/toolbox/osi_page.dart';
import 'package:routepass/pages/toolbox/ping_page.dart';
import 'package:routepass/pages/toolbox/portscan_page.dart';
import 'package:routepass/pages/toolbox/subnet_page.dart';
import 'package:routepass/pages/toolbox/toolbox_home_page.dart';
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
import 'package:routepass/widgets/capsule_nav_bar.dart';

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

/// 首页快捷入口也有同名文字，切 tab 必须把 finder 限定在胶囊导航里。
Finder _navTab(String label) =>
    find.descendant(of: find.byType(CapsuleNavBar), matching: find.text(label));

/// 登录并进入外壳首页（登录流程同 shell_test.dart）。
/// 同文件里 MockAuthService 的登录态跨用例保留，已登录时直接进外壳。
/// 上一个用例可能停在别的 tab（AppShell 按 kv `ui.lastTab` 恢复），进首页后先切回首页 tab。
Future<void> _loginToHome(WidgetTester tester) async {
  await tester.pumpWidget(const RoutePassApp());
  await tester.pumpAndSettle();
  // Splash dwells ~2s: pumpAndSettle stops while the dwell timer is pending
  // (no frame scheduled), so advance fake time past it explicitly.
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();

  if (find.widgetWithText(TextField, '用户名').tryEvaluate()) {
    await tester.enterText(find.widgetWithText(TextField, '用户名'), 'demo_user1');
    await tester.enterText(find.widgetWithText(TextField, '密码'), 'Demo1234');
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();
    // 走完登录成功 Snackbar 的 4 秒自动消失 Timer，避免遗留定时器。
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  await tester.tap(_navTab('首页'));
  await tester.pumpAndSettle();
  expect(find.textContaining('，Max'), findsOneWidget);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _initServices();

  testWidgets('点子网卡进子网页，底栏隐藏，返回后最近使用出现', (tester) async {
    await _loginToHome(tester);

    await tester.tap(_navTab('工具'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('子网计算器'));
    await tester.pumpAndSettle();
    expect(find.byType(SubnetPage), findsOneWidget);
    expect(find.byType(CapsuleNavBar), findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(ToolboxHomePage), findsOneWidget);
    expect(find.text('最近使用'), findsOneWidget);
    expect(find.text('子网计算器'), findsWidgets);
  });

  testWidgets('点 Ping 卡进 Ping 页', (tester) async {
    // GridView 懒构建：600 高视口下第 4 行起的卡不在树里，改用 1400 高视口。
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await _loginToHome(tester);

    await tester.tap(_navTab('工具'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ping'));
    await tester.pumpAndSettle();
    expect(find.byType(PingPage), findsOneWidget);
    expect(find.byType(CapsuleNavBar), findsNothing);
  });

  testWidgets('点端口扫描卡进页弹合规确认，取消后不扫描', (tester) async {
    // GridView 懒构建：600 高视口下第 4 行起的卡不在树里，改用 1400 高视口。
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await _loginToHome(tester);

    await tester.tap(_navTab('工具'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('端口扫描'));
    await tester.pumpAndSettle();
    expect(find.byType(PortScanPage), findsOneWidget);
    expect(find.text('合规确认'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(find.text('合规确认'), findsNothing);
    expect(find.textContaining('待接本地服务'), findsNothing);
  });

  testWidgets('点 OSI 卡进对照页', (tester) async {
    // GridView 懒构建：600 高视口下第 4 行起的卡不在树里，改用 1400 高视口。
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await _loginToHome(tester);

    await tester.tap(_navTab('工具'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OSI/TCP-IP 对照'));
    await tester.pumpAndSettle();
    expect(find.byType(OsiPage), findsOneWidget);
  });

  testWidgets('首页子网计算器方块进子网页', (tester) async {
    await _loginToHome(tester);

    await tester.ensureVisible(find.text('子网计算器'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('子网计算器'));
    await tester.pumpAndSettle();
    expect(find.byType(SubnetPage), findsOneWidget);
    expect(find.byType(CapsuleNavBar), findsNothing);
  });
}
