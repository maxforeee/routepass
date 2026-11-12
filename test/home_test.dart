import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/app.dart';
import 'package:routepass/core/service_locator.dart';
import 'package:routepass/pages/bank/answer_page.dart';
import 'package:routepass/pages/bank/set_detail_page.dart';
import 'package:routepass/pages/home/home_content.dart';
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
import 'package:routepass/widgets/capsule_nav_bar.dart';

/// 与 widget_test.dart 相同的一套 Mock/本地实现装配；重复调用直接返回。
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

/// 登录并进入外壳首页（写法同 shell_test.dart 的 _loginToHome）。
/// 同文件里 MockAuthService 的登录态跨用例保留，已登录时直接进外壳。
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

  expect(find.textContaining('好，'), findsOneWidget);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _initServices();

  testWidgets('首页 10 卡片瀑布流：关键卡片齐全，继续学习（H-B1）隐藏', (tester) async {
    await _loginToHome(tester);

    expect(find.text('快速 10 题'), findsOneWidget);
    expect(find.text('100 题套卷'), findsOneWidget);
    expect(find.text('200 题套卷'), findsOneWidget);
    expect(find.text('50 题套卷'), findsOneWidget);
    expect(find.text('100 题 · 约 60 分钟'), findsOneWidget);
    expect(find.text('200 题 · 约 120 分钟'), findsOneWidget);
    expect(find.text('50 题 · 约 30 分钟'), findsOneWidget);
    expect(find.text('错题本'), findsOneWidget);
    expect(find.text('章节速览'), findsOneWidget);
    expect(find.text('VLAN 基础'), findsOneWidget);
    expect(find.text('已掌握 0/2'), findsOneWidget);
    expect(find.text('今日知识点'), findsOneWidget);
    expect(find.text('子网计算器'), findsOneWidget);
    expect(find.text('IP/进制转换'), findsOneWidget);
    expect(find.text('学习统计'), findsOneWidget);

    // Mock 无继续会话 → H-B1 隐藏。
    expect(find.text('继续学习'), findsNothing);

    // 横幅标题（今日未完成任务）。
    expect(find.text('今天还没有完成任务'), findsOneWidget);
  });

  testWidgets('本地模式同步提示条：点开同步诊断 sheet', (tester) async {
    // 同步 sheet 内容较高，用小视口会溢出，改用高视口。
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _loginToHome(tester);

    await tester.scrollUntilVisible(
      find.text('本地模式 · 未连接服务器'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('本地模式 · 未连接服务器'), findsOneWidget);
    expect(find.text('学习记录保存在本机，点击查看同步诊断'), findsOneWidget);

    await tester.tap(find.text('本地模式 · 未连接服务器'));
    await tester.pumpAndSettle();
    expect(find.text('同步诊断'), findsOneWidget);
  });

  testWidgets('首页横幅开始直达答题页，不经过套卷详情', (tester) async {
    await _loginToHome(tester);

    await tester.tap(
      find.descendant(
        of: find.byType(HomeContentPage),
        matching: find.widgetWithText(FilledButton, '开始'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AnswerPage), findsOneWidget);
    expect(find.byType(SetDetailPage), findsNothing);
  });

  testWidgets('首页 IP/进制转换方块进 IP 转换页，底栏隐藏', (tester) async {
    await _loginToHome(tester);

    await tester.ensureVisible(find.text('IP/进制转换'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('IP/进制转换'));
    await tester.pumpAndSettle();
    expect(find.byType(IpConvertPage), findsOneWidget);
    expect(find.byType(CapsuleNavBar), findsNothing);
  });
}
