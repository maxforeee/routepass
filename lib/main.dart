import 'package:flutter/widgets.dart';

import 'app.dart';
import 'core/kv_store.dart';
import 'core/local_db.dart';
import 'core/service_locator.dart';
import 'router/app_router.dart';
import 'services/auth/auth_service.dart';
import 'services/bank/answer_record_service.dart';
import 'services/bank/answer_session_service.dart';
import 'services/bank/bank_manifest_service_http.dart';
import 'services/bank/cached_practice_service.dart';
import 'services/bank/cached_question_repository.dart';
import 'services/bank/daily_practice_service_http.dart';
import 'services/bank/exam_service.dart';
import 'services/bank/favorite_service.dart';
import 'services/bank/local_cache_service.dart';
import 'services/bank/practice_service.dart';
import 'services/bank/question_bank_source.dart';
import 'services/bank/question_repo_http.dart';
import 'services/bank/rotation_service.dart';
import 'services/bank/sqlite_wrong_favorite_service.dart';
import 'services/bank/stats_service.dart';
import 'services/bank/sync_http_service.dart';
import 'services/bank/wrong_service.dart';
import 'services/content/content_service_http.dart';
import 'services/knowledge/knowledge_repo_http.dart';
import 'services/knowledge/search_service_http.dart';
import 'services/mock/mock_auth_service.dart';
import 'services/mock/mock_cli_service.dart';
import 'services/mock/mock_content_service.dart';
import 'services/mock/mock_exam_service.dart';
import 'services/mock/mock_knowledge_repository.dart';
import 'services/mock/mock_ping_service.dart';
import 'services/mock/mock_port_scan_service.dart';
import 'services/mock/mock_practice_service.dart';
import 'services/mock/mock_question_repository.dart';
import 'services/mock/mock_rotation_service.dart';
import 'services/mock/mock_search_service.dart';
import 'services/mock/mock_stats_service.dart';
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
  // F36：错题本 / 收藏持久表与缓存共用同一个 routepass.db 连接。
  final localDb = SqfliteLocalDatabase();
  final localCache = SqliteBankLocalCache(localDb);
  // F19：登录接真实后端；accessToken 只活 15 分钟，AuthHttpClient 负责
  // 附加 Bearer、401 时刷新一次并重放。
  // F25：登出时同一份 SQLite 缓存随账号数据一并清空。
  final authService = HttpAuthService(
    localCache: localCache,
    // F34 (B3)：设备列表接口未就绪 / 失败时回落 Mock（空列表，不编造）。
    fallback: MockAuthService(),
  );
  authService.onSessionExpired = () {
    appNavigatorKey.currentState?.pushNamedAndRemoveUntil(
      AppRoutes.login,
      (route) => false,
    );
  };
  final authClient = AuthHttpClient(auth: authService);
  // F34 (B3)：getDevices 走已鉴权客户端（Bearer + 401 刷新一次重放）。
  authService.authClient = authClient;
  String? cachedToken() => authService.cachedAccessToken;
  // S11：练习会话 / 抽题 / 判分 / 记录 / 进度走真实契约；接口未上线
  // （404）或未鉴权（401）时由 HttpPracticeService 内部回落到 Mock。
  final practiceHttp = HttpPracticeService(
    fallback: MockPracticeService(),
    client: authClient,
    tokenProvider: cachedToken,
  );
  ServiceLocator.init(
    questionRepository: CachedQuestionRepository(
      // F26：模块列表接真实契约（GET /bank/modules，真实模块名 + 题量）；
      // 未登录 / 离线 / 接口未就绪时回落 Mock（5 模块全 0，不编数字）。
      // 抽题 / 单题 / 套卷统计路径不变，仍委托 Mock。
      delegate: HttpQuestionRepository(
        delegate: MockQuestionRepository(),
        client: authClient,
        tokenProvider: cachedToken,
      ),
      cache: localCache,
      // 前置页 done/remaining 读 S11 `GET /practice/progress`（裸数组），
      // 考试卷 / 未匹配模块回落 `/bank/sets/{id}/overview`（F26 chunk 6
      // 已接真实端点：真实题量 / 已完成 / 正确率，失败回落待接口文案）。
      overviewSource: HttpPracticeProgressOverviewSource(
        fallback: HttpBankSetOverviewSource(
          client: authClient,
          tokenProvider: cachedToken,
        ),
        client: authClient,
        tokenProvider: cachedToken,
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
      // F34 (A12)：离线抽题现读 sync.recent_answered，排除近 7 天已答。
      kv: ServiceLocator.kvStore,
    ),
    // F28：7 天轮回接真实契约（POST /practice/draw + /sessions/{id}/
    // answers|submit）；未登录 / 离线 / 接口未就绪时回落 Mock（诚实空态，
    // 不编题、不编解锁时间、不编分数）。与 S11 练习 / 考试流程互不调用。
    rotationService: HttpRotationService(
      fallback: MockRotationService(),
      client: authClient,
      tokenProvider: cachedToken,
    ),
    examService: HttpExamService(
      local: MockExamService(),
      client: authClient,
      tokenProvider: cachedToken,
    ),
    dailyPracticeService: HttpDailyPracticeService(),
    // F25：收藏 / 错题本接真实契约（GET/POST/DELETE）；接口未上线（404）
    // 或未鉴权（401）时回落本地。「已掌握」服务端暂无接口，仍走本地。
    // F36：本地兜底换成 SQLite 持久实现（重启不丢，不预置演示数据）。
    wrongService: HttpWrongService(
      local: SqliteWrongService(localDb),
      client: authClient,
      tokenProvider: cachedToken,
    ),
    favoriteService: HttpFavoriteService(
      local: SqliteFavoriteService(localDb),
      client: authClient,
      tokenProvider: cachedToken,
    ),
    // F26：学习统计接真实契约（GET /stats/overview + /stats/daily）；
    // 未登录 / 离线 / 接口未就绪时回落 Mock（全 0 / 空列表，不编数字）。
    statsService: HttpStatsService(
      fallback: MockStatsService(),
      client: authClient,
      tokenProvider: cachedToken,
    ),
    // F26 chunk 8：知识库接真实契约（GET /knowledge/points 分页 + 详情 +
    // 题目反查）；章/节由 code 前缀聚合，只有正式内容的 KP 进浏览结构。
    // 未登录 / 离线 / 接口未就绪时回落 Mock 样例，不抛给 UI。
    knowledgeRepository: HttpKnowledgeRepository(
      fallback: MockKnowledgeRepository(),
      client: authClient,
      tokenProvider: cachedToken,
    ),
    // F26：搜索接真实契约（GET /knowledge/search + /bank/questions/search）；
    // 未登录 / 离线 / 接口未就绪时按区回落 Mock，不拿样例冒充真实命中。
    searchService: HttpSearchService(
      fallback: MockSearchService(),
      client: authClient,
      tokenProvider: cachedToken,
    ),
    subnetCalcService: LocalSubnetCalcService(),
    ipConvertService: LocalIpConvertService(),
    pingService: MockPingService(),
    portScanService: MockPortScanService(),
    cliService: MockCliService(),
    authService: authService,
    // 同步接真实契约（pull / push / baseline）；待上传队列来自同一份
    // SQLite 缓存，接口未上线时保留本地状态。
    syncService: HttpSyncService(
      client: authClient,
      tokenProvider: cachedToken,
      localCache: localCache,
    ),
    // F34：内容清单 / 能力声明 / 探活接真实契约（GET /content/manifest +
    // /meta/capabilities + /meta/health）；未登录 / 离线 / 接口未就绪时
    // 回落 Mock。升级检查后端无契约字段，恒走 Mock（ok，不编强制升级）。
    contentService: HttpContentService(
      fallback: MockContentService(),
      client: authClient,
      tokenProvider: cachedToken,
    ),
  );
  runApp(const RoutePassApp());
}
