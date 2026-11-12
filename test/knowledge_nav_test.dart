import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/app.dart';
import 'package:routepass/core/service_locator.dart';
import 'package:routepass/pages/knowledge/knowledge_detail_page.dart';
import 'package:routepass/pages/knowledge/knowledge_home_page.dart';
import 'package:routepass/pages/knowledge/knowledge_search_page.dart';
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

/// 从知识库列表进详情页（点行展开面板，再点“查看详情”）。
Future<void> _openDetailFromList(WidgetTester tester) async {
  await tester.tap(_navTab('知识'));
  await tester.pumpAndSettle();
  // 展开态经 kv 持久化，跨用例可能仍是展开的；此时再点行会收起，故只在未展开时点行。
  if (find.text('查看详情').evaluate().isEmpty) {
    await tester.tap(find.text('样例知识点：VLAN 是什么'));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.text('查看详情'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _initServices();

  testWidgets('点底栏知识库进列表页', (tester) async {
    await _loginToHome(tester);

    await tester.tap(_navTab('知识'));
    await tester.pumpAndSettle();
    expect(find.byType(KnowledgeHomePage), findsOneWidget);
    expect(find.text('样例章节：VLAN 基础'), findsOneWidget);
  });

  testWidgets('点知识点行展开面板，点查看详情进详情页', (tester) async {
    await _loginToHome(tester);
    await _openDetailFromList(tester);

    expect(find.byType(KnowledgeDetailPage), findsOneWidget);
    expect(find.text('常用命令'), findsOneWidget);
    expect(find.text('display vlan'), findsOneWidget);
  });

  testWidgets('详情页返回回列表页', (tester) async {
    await _loginToHome(tester);
    await _openDetailFromList(tester);

    await tester.tap(find.text('返回知识库'));
    await tester.pumpAndSettle();
    expect(find.text('样例章节：VLAN 基础'), findsOneWidget);
  });

  testWidgets('列表页搜索框提交进搜索页', (tester) async {
    await _loginToHome(tester);

    await tester.tap(_navTab('知识'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'VLAN');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.byType(KnowledgeSearchPage), findsOneWidget);
    expect(find.text('样例知识点：VLAN 是什么'), findsOneWidget);
  });

  testWidgets('首页今日知识点进详情页', (tester) async {
    await _loginToHome(tester);

    await tester.ensureVisible(find.text('样例知识点：VLAN 是什么'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('样例知识点：VLAN 是什么'));
    await tester.pumpAndSettle();
    expect(find.byType(KnowledgeDetailPage), findsOneWidget);
    expect(find.text('返回首页'), findsOneWidget);
  });

  testWidgets('首页章节速览切到知识库 tab', (tester) async {
    await _loginToHome(tester);

    await tester.ensureVisible(find.text('章节速览'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('章节速览'));
    await tester.pumpAndSettle();
    expect(find.byType(KnowledgeHomePage), findsOneWidget);
    expect(find.text('样例章节：VLAN 基础'), findsOneWidget);
  });
}
