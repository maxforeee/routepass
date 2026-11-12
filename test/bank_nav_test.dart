import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/app.dart';
import 'package:routepass/core/kv_store.dart';
import 'package:routepass/core/service_locator.dart';
import 'package:routepass/models/practice.dart';
import 'package:routepass/pages/bank/favorites_page.dart';
import 'package:routepass/pages/bank/module_list_page.dart';
import 'package:routepass/pages/bank/set_detail_page.dart';
import 'package:routepass/pages/bank/stats_page.dart';
import 'package:routepass/pages/bank/wrong_page.dart';
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
Future<void> _loginToHome(WidgetTester tester) async {
  await tester.pumpWidget(const RoutePassApp());
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

  // 上一个用例可能停在别的 tab（AppShell 按 kv `ui.lastTab` 恢复）；先切回首页。
  await tester.tap(_navTab('首页'));
  await tester.pumpAndSettle();
  expect(find.textContaining('，Max'), findsOneWidget);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _initServices();

  testWidgets('点底栏题库进题库页', (tester) async {
    await _loginToHome(tester);

    await tester.tap(_navTab('题库'));
    await tester.pumpAndSettle();
    expect(find.byType(BankModuleListPage), findsOneWidget);
    expect(find.text('H3CNE 300 道 · 每套含解析'), findsOneWidget);
    expect(find.text('100 题套卷'), findsOneWidget);
  });

  testWidgets('点套卷卡开始进套卷详情页', (tester) async {
    await _loginToHome(tester);

    await tester.tap(_navTab('题库'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '开始').first);
    await tester.pumpAndSettle();
    expect(find.byType(SetDetailPage), findsOneWidget);
    expect(find.text('100 题套卷'), findsOneWidget);
  });

  testWidgets('错题本入口进错题本页（空态）', (tester) async {
    // 入口行在 600 高默认视口下首屏外（ListView 懒构建，滚不到）；用 1400 高视口。
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _loginToHome(tester);

    await tester.tap(_navTab('题库'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('错题本'));
    await tester.pumpAndSettle();
    expect(find.byType(WrongPage), findsOneWidget);
    expect(find.text('暂无错题'), findsOneWidget);
  });

  testWidgets('收藏入口进收藏页（空态）', (tester) async {
    // 同错题本：入口行在默认视口下首屏外，用 1400 高视口。
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _loginToHome(tester);

    await tester.tap(_navTab('题库'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('收藏'));
    await tester.pumpAndSettle();
    expect(find.byType(FavoritesPage), findsOneWidget);
    expect(find.text('暂无收藏'), findsOneWidget);
  });

  testWidgets('首页学习统计方块进统计页', (tester) async {
    await _loginToHome(tester);

    await tester.ensureVisible(find.text('学习统计'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('学习统计'));
    await tester.pumpAndSettle();
    expect(find.byType(StatsPage), findsOneWidget);
  });

  testWidgets('kv 有进度指针时首页不再显示继续学习', (tester) async {
    ServiceLocator.kvStore.setString(
      KvStore.keyHomeContinue,
      jsonEncode(
        const ContinueSession(
          mode: 'practice',
          answeredCount: 2,
          totalCount: 10,
          questionId: 'SAMPLE-20',
        ).toJson(),
      ),
    );
    addTearDown(() => ServiceLocator.kvStore.remove(KvStore.keyHomeContinue));

    await _loginToHome(tester);
    expect(find.text('继续学习'), findsNothing);
  });
}
