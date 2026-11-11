import 'package:flutter/widgets.dart';

import 'app.dart';
import 'core/service_locator.dart';
import 'services/mock/mock_auth_service.dart';
import 'services/mock/mock_cli_service.dart';
import 'services/mock/mock_content_service.dart';
import 'services/mock/mock_exam_service.dart';
import 'services/mock/mock_favorite_service.dart';
import 'services/mock/mock_knowledge_repository.dart';
import 'services/mock/mock_ping_service.dart';
import 'services/mock/mock_port_scan_service.dart';
import 'services/mock/mock_practice_service.dart';
import 'services/mock/mock_question_repository.dart';
import 'services/mock/mock_search_service.dart';
import 'services/mock/mock_stats_service.dart';
import 'services/mock/mock_sync_service.dart';
import 'services/mock/mock_wrong_service.dart';
import 'services/toolbox/ip_convert_service_impl.dart';
import 'services/toolbox/subnet_calc_service_impl.dart';

void main() {
 // 现在全部是 Mock / 本地实现；以后接后端时只改这里的装配与
 // config.dart 的 baseUrl，UI 文件不动。
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
 runApp(const RoutePassApp());
}
