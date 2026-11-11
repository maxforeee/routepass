import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/core/service_locator.dart';
import 'package:routepass/pages/knowledge/knowledge_detail_page.dart';
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

const Map<String, Object?> _args = <String, Object?>{
  'kpId': 'KP-VLAN-01-01',
  'sectionId': 'VLAN-01-01',
  'chapterTitle': '样例章节：VLAN 基础',
  'sectionTitle': '样例小节：VLAN 概念',
  'returnTo': 'knowledge',
};

Future<void> _pumpDetail(
  WidgetTester tester, [
  Map<String, Object?> args = _args,
]) async {
  await tester.pumpWidget(MaterialApp(home: KnowledgeDetailPage(args: args)));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _initServices();

  testWidgets('加载详情：标题/正文/命令/易错点/版本', (tester) async {
    await _pumpDetail(tester);

    expect(find.text('返回知识库'), findsOneWidget);
    expect(find.text('样例知识点：VLAN 是什么'), findsWidgets);
    expect(find.text('这是一段样例正文，仅用于界面展示。'), findsOneWidget);
    expect(find.text('常用命令'), findsOneWidget);
    expect(find.text('display vlan'), findsOneWidget);
    expect(find.text('易错点'), findsOneWidget);
    expect(find.text('样例易错点'), findsOneWidget);
    expect(find.text('内容版本 1.0.0'), findsOneWidget);
    // 同节只有 1 个点：关联知识点区隐藏。
    expect(find.text('关联知识点'), findsNothing);
  });

  testWidgets('关联题目：同知识点样例题 2 道', (tester) async {
    await _pumpDetail(tester);

    expect(find.text('关联题目'), findsOneWidget);
    expect(find.textContaining('样例题'), findsWidgets);
  });

  testWidgets('上一/下一：同节只有 1 点时均禁用', (tester) async {
    await _pumpDetail(tester);

    final prev = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, '上一知识点'),
    );
    final next = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, '下一知识点'),
    );
    expect(prev.onPressed, isNull);
    expect(next.onPressed, isNull);
  });

  testWidgets('掌握开关切换', (tester) async {
    await _pumpDetail(tester);

    final before = tester.widget<Switch>(find.byType(Switch)).value;
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    final after = tester.widget<Switch>(find.byType(Switch)).value;
    expect(after, isNot(before));
  });

  testWidgets('不存在的知识点显示空态', (tester) async {
    await _pumpDetail(tester, const <String, Object?>{'kpId': 'KP-NOPE'});

    expect(find.text('知识点不存在或已下线'), findsOneWidget);
  });

  testWidgets('无 sectionId 时关联区与上一下一隐藏', (tester) async {
    await _pumpDetail(tester, const <String, Object?>{
      'kpId': 'KP-VLAN-01-01',
      'returnTo': 'home',
    });

    expect(find.text('返回首页'), findsOneWidget);
    expect(find.text('关联知识点'), findsNothing);
    expect(find.text('上一知识点'), findsNothing);
    expect(find.text('下一知识点'), findsNothing);
  });
}
