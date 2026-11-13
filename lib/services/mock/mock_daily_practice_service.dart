/// DailyPracticeService 的 Mock 实现（首页 UI 方案 §11.6）。
///
/// 题库是每日一练的**样例/演示库**：7–10 道固定知识点题（端口号、私有地址
/// 之类），每题一个正确答案、不带解析；等后端每日一练题库接通后整体替换。
/// 这些题不属于 300 道主库，也不要和主库 SAMPLE-10/20/30 混用（主库 Mock
/// 按契约没有答案，判不了对错）。
///
/// 答题状态读写走 [ServiceLocator.kvStore]（与将来的真实实现同一条路径），
/// 不在 Mock 里另存内存副本。
library;

import 'dart:convert';

import '../../core/kv_store.dart';
import '../../core/service_locator.dart';
import '../../models/daily_question.dart';
import '../../models/question.dart';
import '../bank/daily_practice_service.dart';

class MockDailyPracticeService implements DailyPracticeService {
  /// 每日一练样例题库（固定知识点，无解析）。
  static const List<DailyQuestion> _bank = <DailyQuestion>[
    DailyQuestion(
      id: 'DAILY-001',
      stem: 'SSH 服务的默认端口号是',
      options: <QuestionOption>[
        QuestionOption(key: 'A', text: '21'),
        QuestionOption(key: 'B', text: '22'),
        QuestionOption(key: 'C', text: '23'),
        QuestionOption(key: 'D', text: '80'),
      ],
      correctKey: 'B',
    ),
    DailyQuestion(
      id: 'DAILY-002',
      stem: 'HTTP 服务的默认端口号是',
      options: <QuestionOption>[
        QuestionOption(key: 'A', text: '80'),
        QuestionOption(key: 'B', text: '443'),
        QuestionOption(key: 'C', text: '8080'),
        QuestionOption(key: 'D', text: '53'),
      ],
      correctKey: 'A',
    ),
    DailyQuestion(
      id: 'DAILY-003',
      stem: 'HTTPS 服务的默认端口号是',
      options: <QuestionOption>[
        QuestionOption(key: 'A', text: '80'),
        QuestionOption(key: 'B', text: '443'),
        QuestionOption(key: 'C', text: '8443'),
        QuestionOption(key: 'D', text: '22'),
      ],
      correctKey: 'B',
    ),
    DailyQuestion(
      id: 'DAILY-004',
      stem: 'DNS 服务的默认端口号是',
      options: <QuestionOption>[
        QuestionOption(key: 'A', text: '53'),
        QuestionOption(key: 'B', text: '54'),
        QuestionOption(key: 'C', text: '67'),
        QuestionOption(key: 'D', text: '123'),
      ],
      correctKey: 'A',
    ),
    DailyQuestion(
      id: 'DAILY-005',
      stem: 'FTP 控制连接的默认端口号是',
      options: <QuestionOption>[
        QuestionOption(key: 'A', text: '20'),
        QuestionOption(key: 'B', text: '21'),
        QuestionOption(key: 'C', text: '22'),
        QuestionOption(key: 'D', text: '23'),
      ],
      correctKey: 'B',
    ),
    DailyQuestion(
      id: 'DAILY-006',
      stem: 'Telnet 服务的默认端口号是',
      options: <QuestionOption>[
        QuestionOption(key: 'A', text: '21'),
        QuestionOption(key: 'B', text: '22'),
        QuestionOption(key: 'C', text: '23'),
        QuestionOption(key: 'D', text: '25'),
      ],
      correctKey: 'C',
    ),
    DailyQuestion(
      id: 'DAILY-007',
      stem: 'DHCP 服务器端的默认端口号是',
      options: <QuestionOption>[
        QuestionOption(key: 'A', text: '66'),
        QuestionOption(key: 'B', text: '67'),
        QuestionOption(key: 'C', text: '68'),
        QuestionOption(key: 'D', text: '69'),
      ],
      correctKey: 'B',
    ),
    DailyQuestion(
      id: 'DAILY-008',
      stem: 'SMTP 服务的默认端口号是',
      options: <QuestionOption>[
        QuestionOption(key: 'A', text: '23'),
        QuestionOption(key: 'B', text: '25'),
        QuestionOption(key: 'C', text: '53'),
        QuestionOption(key: 'D', text: '110'),
      ],
      correctKey: 'B',
    ),
    DailyQuestion(
      id: 'DAILY-009',
      stem: '下列地址中属于私有网络地址的是',
      options: <QuestionOption>[
        QuestionOption(key: 'A', text: '8.8.8.8'),
        QuestionOption(key: 'B', text: '192.168.1.1'),
        QuestionOption(key: 'C', text: '114.114.114.114'),
        QuestionOption(key: 'D', text: '1.1.1.1'),
      ],
      correctKey: 'B',
    ),
  ];

  /// 按日期确定性取题：一年中的第几天对题库长度取模，同一天同一题，
  /// 第二天换下一题（跨年后按新一年的第几天从头轮换）。
  @override
  Future<DailyQuestion> questionForDate(DateTime date) async {
    final dayOfYear = date.difference(DateTime(date.year, 1, 1)).inDays + 1;
    return _bank[dayOfYear % _bank.length];
  }

  @override
  Future<String?> answerForDate(DateTime date) async {
    final raw = ServiceLocator.kvStore.getString(KvStore.keyDailyAnswer);
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      if (json['date'] != _formatDate(date)) return null;
      return json['selectedKey'] as String?;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveAnswer({
    required DateTime date,
    required String questionId,
    required String selectedKey,
  }) async {
    final json = <String, Object?>{
      'date': _formatDate(date),
      'questionId': questionId,
      'selectedKey': selectedKey,
    };
    ServiceLocator.kvStore.setString(KvStore.keyDailyAnswer, jsonEncode(json));
  }

  /// 本地日期 → `yyyy-MM-dd`（kv 里按日比较，不存时间）。
  static String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}
