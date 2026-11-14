/// 服务定位器（规格文档第 4 章 §4.1 分层规则）。
///
/// UI 只通过本定位器拿抽象接口，页面里不许出现 http/dio/sqflite/后端地址。
/// 换实现只改 main.dart 里的装配与 config.dart 的 baseUrl，UI 文件一个字不动。
/// 现在装配的全部是 Mock / 本地实现（见 main.dart）。
library;

import '../services/bank/answer_record_service.dart';
import '../services/bank/answer_session_service.dart';
import '../services/bank/bank_manifest_service.dart';
import '../services/bank/bank_sync_service.dart';
import '../services/bank/daily_practice_service.dart';
import '../services/bank/exam_service.dart';
import '../services/bank/favorite_service.dart';
import '../services/bank/practice_service.dart';
import '../services/bank/question_repo.dart';
import '../services/bank/stats_service.dart';
import '../services/bank/wrong_service.dart';
import '../services/base/auth_service.dart';
import '../services/base/content_service.dart';
import '../services/connectivity_service.dart';
import '../services/knowledge/knowledge_repo.dart';
import '../services/knowledge/search_service.dart';
import '../services/sync_mode_service.dart';
import '../services/toolbox/cli_service.dart';
import '../services/toolbox/ip_convert_service.dart';
import '../services/toolbox/ping_service.dart';
import '../services/toolbox/port_scan_service.dart';
import '../services/toolbox/subnet_calc_service.dart';
import 'kv_store.dart';

class ServiceLocator {
  ServiceLocator._();

  static bool _initialized = false;

  static late final QuestionRepository questionRepository;
  static late final BankManifestService bankManifestService;
  static late final AnswerRecordService answerRecordService;
  static late final AnswerSessionService answerSessionService;
  static late final PracticeService practiceService;
  static late final ExamService examService;
  static late final DailyPracticeService dailyPracticeService;
  static late final WrongService wrongService;
  static late final FavoriteService favoriteService;
  static late final StatsService statsService;
  static late final KnowledgeRepository knowledgeRepository;
  static late final SearchService searchService;
  static late final SubnetCalcService subnetCalcService;
  static late final IpConvertService ipConvertService;
  static late final PingService pingService;
  static late final PortScanService portScanService;
  static late final CliService cliService;
  static late final AuthService authService;
  static late final SyncService syncService;
  static late final ContentService contentService;

  /// 首页同步模式（网络 + 登录态 + 服务器可达性）。
  /// 非 final：测试可替换为可控实现（生产只在 init 里装配一次）。
  static late SyncModeService syncModeService;

  /// 本地 kv（设备本地 UI 状态，见规格文档 §4.9.1；不是 16 个后端服务接口之一）。
  /// 默认内存实现（测试用）；main.dart 在 runApp 前升级为 shared_preferences
  /// 持久实现（F17：每日一练日期锁必须重启不丢），调用方不动。
  static KvStore kvStore = InMemoryKvStore();

  /// 由 main.dart 在 runApp 之前调用一次；重复调用直接返回，不重复装配。
  static void init({
    required QuestionRepository questionRepository,
    required BankManifestService bankManifestService,
    required AnswerRecordService answerRecordService,
    required AnswerSessionService answerSessionService,
    required PracticeService practiceService,
    required ExamService examService,
    required DailyPracticeService dailyPracticeService,
    required WrongService wrongService,
    required FavoriteService favoriteService,
    required StatsService statsService,
    required KnowledgeRepository knowledgeRepository,
    required SearchService searchService,
    required SubnetCalcService subnetCalcService,
    required IpConvertService ipConvertService,
    required PingService pingService,
    required PortScanService portScanService,
    required CliService cliService,
    required AuthService authService,
    required SyncService syncService,
    required ContentService contentService,
    SyncModeService? syncModeService,
  }) {
    if (_initialized) return;
    ServiceLocator.questionRepository = questionRepository;
    ServiceLocator.bankManifestService = bankManifestService;
    ServiceLocator.answerRecordService = answerRecordService;
    ServiceLocator.answerSessionService = answerSessionService;
    ServiceLocator.practiceService = practiceService;
    ServiceLocator.examService = examService;
    ServiceLocator.dailyPracticeService = dailyPracticeService;
    ServiceLocator.wrongService = wrongService;
    ServiceLocator.favoriteService = favoriteService;
    ServiceLocator.statsService = statsService;
    ServiceLocator.knowledgeRepository = knowledgeRepository;
    ServiceLocator.searchService = searchService;
    ServiceLocator.subnetCalcService = subnetCalcService;
    ServiceLocator.ipConvertService = ipConvertService;
    ServiceLocator.pingService = pingService;
    ServiceLocator.portScanService = portScanService;
    ServiceLocator.cliService = cliService;
    ServiceLocator.authService = authService;
    ServiceLocator.syncService = syncService;
    ServiceLocator.contentService = contentService;
    ServiceLocator.syncModeService =
        syncModeService ??
        SyncModeService(
          connectivity: PlatformConnectivityService(),
          syncService: syncService,
          isLoggedIn: () async => (await authService.getCurrentUser()) != null,
        );
    _initialized = true;
  }
}
