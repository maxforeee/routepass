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

  if (find.widgetWithText(TextField, '用户名').tryEvaluate()) {
    await tester.enterText(
      find.widgetWithText(TextField, '用户名'),
      'demo_user1',
    );
    await tester.enterText(find.widgetWithText(TextField, '密码'), 'Demo1234');
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();
    // 走完登录成功 Snackbar 的 4 秒自动消失 Timer，避免遗留定时器。
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  expect(find.textContaining('欢迎回来'), findsOneWidget);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _initServices();

  testWidgets('首页 12 方块瀑布流：关键方块齐全，继续学习（H-B1）隐藏',
      (tester) async {
    await _loginToHome(tester);

    expect(find.text('快速 10 题'), findsOneWidget);
    expect(find.text('100 题套卷'), findsOneWidget);
    expect(find.text('错题本'), findsOneWidget);
    expect(find.text('子网计算器'), findsOneWidget);
    expect(find.text('学习统计'), findsOneWidget);

    // Mock 无继续会话 → H-B1 隐藏。
    expect(find.text('继续学习'), findsNothing);

    expect(find.text('今天还没有完成任务'), findsOneWidget);
  });
}
