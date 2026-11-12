import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/app.dart';
import 'package:routepass/core/service_locator.dart';
import 'package:routepass/core/theme.dart';
import 'package:routepass/pages/bank/set_detail_page.dart';
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
import 'package:routepass/widgets/reserved_slot.dart';

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

Finder _navTab(String label) =>
    find.descendant(of: find.byType(CapsuleNavBar), matching: find.text(label));

/// 登录并进入外壳首页；已登录时直接进外壳。
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

  testWidgets('套卷详情页 100 题渲染完整', (tester) async {
    await _loginToHome(tester);

    await tester.tap(_navTab('题库'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '开始').first);
    await tester.pumpAndSettle();

    expect(find.byType(SetDetailPage), findsOneWidget);
    expect(find.text('100 题套卷'), findsOneWidget);
    expect(find.text('H3CNE 模拟套卷 · 每题含解析'), findsOneWidget);
    expect(find.text('100 题'), findsOneWidget);
    expect(find.text('单选 75 · 多选 25'), findsOneWidget);
    expect(find.text('约 60 分钟'), findsOneWidget);
    expect(find.text('知识点考察'), findsOneWidget);
    expect(find.text('VLAN'), findsOneWidget);
    expect(find.text('OSPF'), findsOneWidget);
    expect(find.text('ACL'), findsOneWidget);
    expect(find.text('NAT'), findsOneWidget);
    expect(find.text('子网划分'), findsOneWidget);
    expect(find.text('20 题 · 0%'), findsNWidgets(5));
    expect(find.byType(ReservedSlot), findsOneWidget);
    expect(find.text('预留容器 · 以后在这里加内容'), findsOneWidget);
    expect(find.text('答题说明'), findsOneWidget);
    expect(find.text('限时 60 分钟，超时自动交卷'), findsOneWidget);
    expect(find.text('交卷后可查看解析与得分'), findsOneWidget);
    expect(find.text('做错的题自动收入错题本'), findsOneWidget);
    expect(find.text('开始答题'), findsOneWidget);
  });

  testWidgets('套卷详情页 开始答题 进答题页', (tester) async {
    await _loginToHome(tester);

    await tester.tap(_navTab('题库'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '开始').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始答题'));
    await tester.pumpAndSettle();
    expect(find.text('第 1/3 题'), findsOneWidget);
  });

  testWidgets('套卷详情页 200 题推导正确', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: SetDetailPage(
          args: <String, Object?>{'mode': 'exam', 'drawCount': 200},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('200 题套卷'), findsOneWidget);
    expect(find.text('200 题'), findsOneWidget);
    expect(find.text('单选 150 · 多选 50'), findsOneWidget);
    expect(find.text('约 120 分钟'), findsOneWidget);
    expect(find.text('40 题 · 0%'), findsNWidgets(5));
    expect(find.text('限时 120 分钟，超时自动交卷'), findsOneWidget);
  });

  testWidgets('套卷详情页 50 题推导正确', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: SetDetailPage(
          args: <String, Object?>{'mode': 'exam', 'drawCount': 50},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('50 题套卷'), findsOneWidget);
    expect(find.text('50 题'), findsOneWidget);
    expect(find.text('单选 37 · 多选 13'), findsOneWidget);
    expect(find.text('约 30 分钟'), findsOneWidget);
    expect(find.text('10 题 · 0%'), findsNWidgets(5));
    expect(find.text('限时 30 分钟，超时自动交卷'), findsOneWidget);
  });

  testWidgets('首页套卷卡进详情页，快速 10 题直达答题页', (tester) async {
    await _loginToHome(tester);

    await tester.tap(find.text('100 题套卷'));
    await tester.pumpAndSettle();
    expect(find.byType(SetDetailPage), findsOneWidget);
    expect(find.text('100 题套卷'), findsOneWidget);

    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('快速 10 题'));
    await tester.pumpAndSettle();
    expect(find.text('第 1/3 题'), findsOneWidget);
  });
}
