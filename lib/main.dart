import 'package:flutter/widgets.dart';

import 'app.dart';
import 'core/kv_store.dart';
import 'core/local_db.dart';
import 'core/service_locator.dart';
import 'services/bank/answer_record_service.dart';
import 'services/bank/answer_session_service.dart';
import 'services/bank/bank_manifest_service_http.dart';
import 'services/bank/cached_practice_service.dart';
import 'services/bank/cached_question_repository.dart';
import 'services/bank/daily_practice_service_http.dart';
import 'services/bank/exam_service.dart';
import 'services/bank/local_cache_service.dart';
import 'services/bank/practice_service.dart';
import 'services/bank/question_bank_source.dart';
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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // F17：kv 升级为 shared_preferences 持久实现（每日一练日期锁与作答
  // 状态重启不丢），必须在装配服务之前。
  ServiceLocator.kvStore = await SharedPreferencesKvStore.create();
  // 题库清单 / 每日一练已接 HTTP，其余仍是 Mock / 本地实现；以后接后端
  // 只改这里的装配与 config.dart 的 baseUrl，UI 文件不动。
  // F19：SQLite 本地缓存是读取的第一层（overview 计数、练习题库、作答）。
  final localCache = SqliteBankLocalCache(SqfliteLocalDatabase());
  // S11：练习会话 / 抽题 / 判分 / 记录 / 进度走真实契约；接口未上线
  // （404）或未鉴权（401）时由 HttpPracticeService 内部回落到 Mock。
  final practiceHttp = HttpPracticeService(fallback: MockPracticeService());
  ServiceLocator.init(
    questionRepository: CachedQuestionRepository(
      delegate: MockQuestionRepository(),
      cache: localCache,
      // 前置页 done/remaining 读 S11 `GET /practice/progress`（裸数组），
      // 考试卷 / 未匹配模块回落 `/bank/sets/{id}/overview`（当前 404）。
      overviewSource: HttpPracticeProgressOverviewSource(
        fallback: HttpBankSetOverviewSource(),
      ),
    ),
    bankManifestService: HttpBankManifestService(),
    answerRecordService: KvAnswerRecordService(
      serverRecords: practiceHttp.fetchPracticeRecords,
    ),
    answerSessionService: KvAnswerSessionService(),
    practiceService: CachedPracticeService(
      delegate: practiceHttp,
      cache: localCache,
      bankSource: HttpBankQuestionBankSource(),
    ),
    examService: HttpExamService(local: MockExamService()),
    dailyPracticeService: HttpDailyPracticeService(),
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
