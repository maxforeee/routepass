import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/app.dart';
import 'package:routepass/core/service_locator.dart';
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

/// main() 里的 ServiceLocator.init 在测试进程不会执行，这里用与 main.dart
/// 完全相同的一套 Mock/本地实现装配一次；ServiceLocator.init 重复调用直接返回。
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

  testWidgets('启动判定进登录页；登录后进首页外壳与 4 个 tab', (tester) async {
    await tester.pumpWidget(const RoutePassApp());
    // splash 的异步判定（getCurrentUser + checkUpgrade）需要 pumpAndSettle 走完。
    await tester.pumpAndSettle();

    // 登录页：'登录' 同时出现在 AppBar 标题与按钮上，用 findsWidgets。
    expect(find.text('登录'), findsWidgets);

    await tester.enterText(find.widgetWithText(TextField, '用户名'), 'demo_user1');
    await tester.enterText(find.widgetWithText(TextField, '密码'), 'Demo1234');
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();
    // 让 Snackbar 的 4 秒自动消失 Timer 走完，避免测试结束时仍挂定时器。
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    // 首页内容 + 底栏 4 个 tab 标签。
    expect(find.textContaining('欢迎回来'), findsOneWidget);
    expect(find.text('首页'), findsWidgets);
    expect(find.text('题库'), findsWidgets);
    expect(find.text('知识库'), findsWidgets);
    expect(find.text('工具箱'), findsWidgets);
  });
}
