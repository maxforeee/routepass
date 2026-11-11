/// 服务定位器（规格文档第 4 章 §4.1 分层规则）。
///
/// UI 只通过本定位器拿抽象接口，页面里不许出现 http/dio/sqflite/后端地址。
/// 换实现只改 main.dart 里的装配与 config.dart 的 baseUrl，UI 文件一个字不动。
/// 现在装配的全部是 Mock / 本地实现（见 main.dart）。
library;

import '../services/bank/bank_sync_service.dart';
import '../services/bank/exam_service.dart';
import '../services/bank/favorite_service.dart';
import '../services/bank/practice_service.dart';
import '../services/bank/question_repo.dart';
import '../services/bank/stats_service.dart';
import '../services/bank/wrong_service.dart';
import '../services/base/auth_service.dart';
import '../services/base/content_service.dart';
import '../services/knowledge/knowledge_repo.dart';
import '../services/knowledge/search_service.dart';
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
  static late final PracticeService practiceService;
  static late final ExamService examService;
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

  /// 本地 kv（设备本地 UI 状态，见规格文档 §4.9.1；不是 16 个后端服务接口之一）。
  /// 现在用内存实现；以后接 SQLite kv 表时只换这里，调用方不动。
  static final KvStore kvStore = InMemoryKvStore();

  /// 由 main.dart 在 runApp 之前调用一次；重复调用直接返回，不重复装配。
  static void init({
    required QuestionRepository questionRepository,
    required PracticeService practiceService,
    required ExamService examService,
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
  }) {
    if (_initialized) return;
    ServiceLocator.questionRepository = questionRepository;
    ServiceLocator.practiceService = practiceService;
    ServiceLocator.examService = examService;
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
    _initialized = true;
  }
}
