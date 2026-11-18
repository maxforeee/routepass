import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:routepass/core/kv_store.dart';
import 'package:routepass/models/stats.dart';
import 'package:routepass/services/auth/auth_service.dart';
import 'package:routepass/services/auth/secure_session_store.dart';
import 'package:routepass/services/bank/stats_service.dart';
import 'package:routepass/services/mock/mock_stats_service.dart';

/// F26 学习统计真实契约测试：
/// - GET /stats/overview 解析（today 为 null / 空 byModule / 精度）；
/// - getByModule 从 overview.byModule 派生，不发额外请求（无独立接口）；
/// - GET /stats/daily 解析 + 翻页取全量；
/// - 连续学习天数客户端推算（后端无 streakDays 字段）；
/// - 未登录 / 离线 / 404 回落 Mock（全 0 / 空列表，不编数字）；
/// - 401 刷新一次并重放（AuthHttpClient）。

const String _base = 'http://example.test';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: const <String, String>{
    'content-type': 'application/json; charset=utf-8',
  },
);

String _dateStr(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// 相对今天偏移 [offset] 天的本地日历日（测试不依赖固定日期，跨午夜也稳）。
DateTime _day(int offset) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day + offset);
}

Map<String, Object?> _dailyJson(
  DateTime date, {
  int answered = 5,
  int correct = 3,
  int durationSec = 120,
}) => <String, Object?>{
  'date': _dateStr(date),
  'answered': answered,
  'correct': correct,
  'durationSec': durationSec,
};

Map<String, Object?> _dailyPage(
  List<Map<String, Object?>> items, {
  required int total,
  int page = 1,
}) => <String, Object?>{
  'items': items,
  'page': page,
  'pageSize': 100,
  'total': total,
};

Map<String, Object?> _overviewJson({
  int totalAnswered = 120,
  int totalCorrect = 90,
  double accuracy = 75.0,
  int totalDurationSec = 3600,
  Map<String, Object?>? today,
  List<Map<String, Object?>> byModule = const <Map<String, Object?>>[],
}) => <String, Object?>{
  'totalAnswered': totalAnswered,
  'totalCorrect': totalCorrect,
  'accuracy': accuracy,
  'totalDurationSec': totalDurationSec,
  'today':
      today ??
      <String, Object?>{
        'date': _dateStr(_day(0)),
        'answered': 10,
        'correct': 8,
        'durationSec': 600,
      },
  'byModule': byModule,
};

DailyStats _row(String date, {int answered = 3}) => DailyStats(
  stat_date: date,
  answered: answered,
  correct: 1,
  duration_sec: 60,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HttpStatsService.getOverview（真实契约解析）', () {
    test('累计 / 正确率 / 今日计数按契约映射，正确率转 0–1 小数', () async {
      final client = MockClient((request) async {
        if (request.url.path == '/api/v1/stats/overview') {
          return _json(_overviewJson());
        }
        expect(request.url.path, '/api/v1/stats/daily');
        return _json(
          _dailyPage(<Map<String, Object?>>[
            _dailyJson(_day(0)),
            _dailyJson(_day(-1)),
          ], total: 2),
        );
      });
      final service = HttpStatsService(client: client, baseUrl: _base);

      final ov = await service.getOverview();
      expect(ov.answeredTotal, 120);
      expect(ov.correctRate, closeTo(0.75, 1e-9));
      expect(ov.todayAnswered, 10);
      expect(ov.todayCorrect, 8);
      expect(ov.streakDays, 2);
    });

    test('accuracy 保留后端 1 位小数精度（85.5 → 0.855）', () async {
      final client = MockClient((request) async {
        if (request.url.path == '/api/v1/stats/overview') {
          return _json(_overviewJson(accuracy: 85.5));
        }
        return _json(_dailyPage(const <Map<String, Object?>>[], total: 0));
      });
      final service = HttpStatsService(client: client, baseUrl: _base);

      final ov = await service.getOverview();
      expect(ov.correctRate, closeTo(0.855, 1e-9));
    });

    test('today.date 为 null（今天还没答）→ 今日计数 0，不编数字', () async {
      final client = MockClient((request) async {
        if (request.url.path == '/api/v1/stats/overview') {
          return _json(
            _overviewJson(
              today: <String, Object?>{
                'date': null,
                'answered': 0,
                'correct': 0,
                'durationSec': 0,
              },
            ),
          );
        }
        return _json(_dailyPage(const <Map<String, Object?>>[], total: 0));
      });
      final service = HttpStatsService(client: client, baseUrl: _base);

      final ov = await service.getOverview();
      expect(ov.todayAnswered, 0);
      expect(ov.todayCorrect, 0);
      expect(ov.answeredTotal, 120);
      expect(ov.streakDays, 0);
    });

    test('today 字段为 null 或缺失 → 今日计数 0，累计值不受影响', () async {
      final nullToday = _overviewJson()..['today'] = null;
      final missingToday = _overviewJson()..remove('today');
      for (final payload in <Map<String, Object?>>[nullToday, missingToday]) {
        final client = MockClient((request) async {
          if (request.url.path == '/api/v1/stats/overview') {
            return _json(payload);
          }
          return _json(_dailyPage(const <Map<String, Object?>>[], total: 0));
        });
        final service = HttpStatsService(client: client, baseUrl: _base);

        final ov = await service.getOverview();
        expect(ov.todayAnswered, 0);
        expect(ov.todayCorrect, 0);
        expect(ov.answeredTotal, 120);
        expect(ov.streakDays, 0);
      }
    });

    test('空 byModule + 空 daily → getByModule 空列表、streak 0', () async {
      final client = MockClient((request) async {
        if (request.url.path == '/api/v1/stats/overview') {
          return _json(
            _overviewJson(
              totalAnswered: 0,
              totalCorrect: 0,
              accuracy: 0.0,
              today: <String, Object?>{
                'date': null,
                'answered': 0,
                'correct': 0,
                'durationSec': 0,
              },
            ),
          );
        }
        return _json(_dailyPage(const <Map<String, Object?>>[], total: 0));
      });
      final service = HttpStatsService(client: client, baseUrl: _base);

      final ov = await service.getOverview();
      expect(ov.answeredTotal, 0);
      expect(ov.todayAnswered, 0);
      expect(ov.streakDays, 0);
      expect(await service.getByModule(), isEmpty);
    });

    test('daily 接口未就绪（404）不影响 overview 真实数字，streak 记 0', () async {
      final client = MockClient((request) async {
        if (request.url.path == '/api/v1/stats/overview') {
          return _json(_overviewJson());
        }
        return _json(<String, Object?>{}, 404);
      });
      final service = HttpStatsService(client: client, baseUrl: _base);

      final ov = await service.getOverview();
      expect(ov.answeredTotal, 120);
      expect(ov.todayAnswered, 10);
      expect(ov.streakDays, 0);
    });

    test('登录态带 Bearer 头；未登录（token null）不带 Authorization', () async {
      final headers = <Map<String, String>>[];
      final client = MockClient((request) async {
        headers.add(request.headers);
        if (request.url.path == '/api/v1/stats/overview') {
          return _json(_overviewJson());
        }
        return _json(_dailyPage(const <Map<String, Object?>>[], total: 0));
      });

      final loggedIn = HttpStatsService(
        client: client,
        baseUrl: _base,
        tokenProvider: () => 'tok-123',
      );
      await loggedIn.getOverview();
      expect(headers.last['Authorization'], 'Bearer tok-123');

      final loggedOut = HttpStatsService(
        client: client,
        baseUrl: _base,
        tokenProvider: () => null,
      );
      await loggedOut.getOverview();
      expect(headers.last.containsKey('Authorization'), isFalse);
    });
  });

  group('HttpStatsService.getByModule（从 overview 派生，无独立接口）', () {
    test('getOverview 之后复用缓存，不发额外请求；total 未知记 0', () async {
      var overviewCalls = 0;
      final client = MockClient((request) async {
        if (request.url.path == '/api/v1/stats/overview') {
          overviewCalls++;
          return _json(
            _overviewJson(
              byModule: <Map<String, Object?>>[
                <String, Object?>{
                  'module': 'VLAN',
                  'answered': 40,
                  'correct': 30,
                  'accuracy': 75.0,
                },
                <String, Object?>{
                  'module': '子网',
                  'answered': 20,
                  'correct': 10,
                  'accuracy': 50.0,
                },
              ],
            ),
          );
        }
        return _json(_dailyPage(const <Map<String, Object?>>[], total: 0));
      });
      final service = HttpStatsService(client: client, baseUrl: _base);

      await service.getOverview();
      final callsAfterOverview = overviewCalls;
      final modules = await service.getByModule();

      expect(overviewCalls, callsAfterOverview);
      expect(modules.length, 2);
      expect(modules[0].module, 'VLAN');
      expect(modules[0].answered, 40);
      expect(modules[0].total, 0);
      expect(modules[0].correctRate, closeTo(0.75, 1e-9));
      // 后端模块名原样保留（中文名不经过 SUBNET 之类的代码映射）。
      expect(modules[1].module, '子网');
      expect(modules[1].correctRate, closeTo(0.5, 1e-9));
    });

    test('冷启动直接调 getByModule：只拉一次 overview 派生', () async {
      var overviewCalls = 0;
      final client = MockClient((request) async {
        expect(request.url.path, '/api/v1/stats/overview');
        overviewCalls++;
        return _json(
          _overviewJson(
            byModule: <Map<String, Object?>>[
              <String, Object?>{
                'module': 'OSPF',
                'answered': 12,
                'correct': 9,
                'accuracy': 75.0,
              },
            ],
          ),
        );
      });
      final service = HttpStatsService(client: client, baseUrl: _base);

      final modules = await service.getByModule();
      expect(overviewCalls, 1);
      expect(modules.single.module, 'OSPF');
      expect(modules.single.answered, 12);
      expect(modules.single.correctRate, closeTo(0.75, 1e-9));
    });
  });

  group('HttpStatsService.getDaily（解析 + 分页）', () {
    test('单页解析：date/durationSec 映射到契约 snake_case 字段', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/v1/stats/daily');
        expect(request.url.queryParameters['page'], '1');
        expect(request.url.queryParameters['pageSize'], '100');
        return _json(
          _dailyPage(<Map<String, Object?>>[
            _dailyJson(_day(0), answered: 10, correct: 8, durationSec: 600),
            _dailyJson(_day(-1), answered: 6, correct: 2, durationSec: 300),
          ], total: 2),
        );
      });
      final service = HttpStatsService(client: client, baseUrl: _base);

      final rows = await service.getDaily();
      expect(rows.length, 2);
      expect(rows.first.stat_date, _dateStr(_day(0)));
      expect(rows.first.answered, 10);
      expect(rows.first.correct, 8);
      expect(rows.first.duration_sec, 600);
      expect(rows.last.stat_date, _dateStr(_day(-1)));
      expect(rows.last.duration_sec, 300);
    });

    test('total 超过单页上限时翻页取全量（150 行 → 2 页，新的在前）', () async {
      final all = <Map<String, Object?>>[
        for (var i = 0; i < 150; i++) _dailyJson(_day(-i)),
      ];
      final pages = <int>[];
      final client = MockClient((request) async {
        expect(request.url.path, '/api/v1/stats/daily');
        final page = int.parse(request.url.queryParameters['page']!);
        pages.add(page);
        final items = all.skip((page - 1) * 100).take(100).toList();
        return _json(_dailyPage(items, total: 150, page: page));
      });
      final service = HttpStatsService(client: client, baseUrl: _base);

      final rows = await service.getDaily();
      expect(pages, <int>[1, 2]);
      expect(rows.length, 150);
      expect(rows.first.stat_date, _dateStr(_day(0)));
      expect(rows.last.stat_date, _dateStr(_day(-149)));
    });

    test('恰好取满 total 即停，不多翻一页', () async {
      final items = <Map<String, Object?>>[
        for (var i = 0; i < 100; i++) _dailyJson(_day(-i)),
      ];
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return _json(_dailyPage(items, total: 100));
      });
      final service = HttpStatsService(client: client, baseUrl: _base);

      final rows = await service.getDaily();
      expect(calls, 1);
      expect(rows.length, 100);
    });

    test('翻页中途失败：保留已取到的真实行，不回落也不编造', () async {
      final items = <Map<String, Object?>>[
        for (var i = 0; i < 100; i++) _dailyJson(_day(-i)),
      ];
      final client = MockClient((request) async {
        final page = int.parse(request.url.queryParameters['page']!);
        if (page == 1) {
          return _json(_dailyPage(items, total: 150));
        }
        throw Exception('offline');
      });
      final service = HttpStatsService(
        client: client,
        baseUrl: _base,
        fallback: MockStatsService(),
      );

      final rows = await service.getDaily();
      expect(rows.length, 100);
      expect(rows.first.stat_date, _dateStr(_day(0)));
    });
  });

  group('连续学习天数（客户端推算，后端无 streakDays）', () {
    final now = DateTime(2026, 11, 16);

    test('连续 3 天到今天 → 3', () {
      final rows = <DailyStats>[
        _row('2026-11-16'),
        _row('2026-11-15'),
        _row('2026-11-14'),
      ];
      expect(HttpStatsService.streakDaysFromDaily(rows, now: now), 3);
    });

    test('今天没答、链尾在昨天 → 仍计数（锚定昨天）', () {
      final rows = <DailyStats>[_row('2026-11-15'), _row('2026-11-14')];
      expect(HttpStatsService.streakDaysFromDaily(rows, now: now), 2);
    });

    test('中间缺一天 → 链条在缺口处断开', () {
      final rows = <DailyStats>[
        _row('2026-11-16'),
        _row('2026-11-15'),
        _row('2026-11-13'),
      ];
      expect(HttpStatsService.streakDaysFromDaily(rows, now: now), 2);
    });

    test('最新答题日早于昨天 → 0（连续已中断）', () {
      final rows = <DailyStats>[_row('2026-11-14'), _row('2026-11-13')];
      expect(HttpStatsService.streakDaysFromDaily(rows, now: now), 0);
    });

    test('空列表 / 全 0 答题日 → 0', () {
      expect(
        HttpStatsService.streakDaysFromDaily(const <DailyStats>[], now: now),
        0,
      );
      expect(
        HttpStatsService.streakDaysFromDaily(<DailyStats>[
          _row('2026-11-16', answered: 0),
        ], now: now),
        0,
      );
    });

    test('0 答题日断开链条（只数 answered > 0 的连续日）', () {
      final rows = <DailyStats>[
        _row('2026-11-16'),
        _row('2026-11-15', answered: 0),
        _row('2026-11-14'),
      ];
      expect(HttpStatsService.streakDaysFromDaily(rows, now: now), 1);
    });

    test('今天 0 答题但昨天起连续 → 锚定昨天计数', () {
      final rows = <DailyStats>[
        _row('2026-11-16', answered: 0),
        _row('2026-11-15'),
        _row('2026-11-14'),
      ];
      expect(HttpStatsService.streakDaysFromDaily(rows, now: now), 2);
    });

    test('输入乱序也能推算（内部按日期降序整理）', () {
      final rows = <DailyStats>[
        _row('2026-11-14'),
        _row('2026-11-16'),
        _row('2026-11-15'),
      ];
      expect(HttpStatsService.streakDaysFromDaily(rows, now: now), 3);
    });

    test('跨月边界连续（3-01 / 2-28 / 2-27）→ 3', () {
      final rows = <DailyStats>[
        _row('2026-03-01'),
        _row('2026-02-28'),
        _row('2026-02-27'),
      ];
      expect(
        HttpStatsService.streakDaysFromDaily(rows, now: DateTime(2026, 3, 1)),
        3,
      );
    });

    test('getOverview 翻页推算：链断即停，不翻完全部历史', () async {
      // 第 1 页：今天起连续 100 天；第 2 页：缺一天（-100），链在页首断开。
      final page1 = <Map<String, Object?>>[
        for (var i = 0; i < 100; i++) _dailyJson(_day(-i)),
      ];
      final page2 = <Map<String, Object?>>[
        for (var i = 101; i < 151; i++) _dailyJson(_day(-i)),
      ];
      var dailyCalls = 0;
      final client = MockClient((request) async {
        if (request.url.path == '/api/v1/stats/overview') {
          return _json(_overviewJson());
        }
        dailyCalls++;
        final page = int.parse(request.url.queryParameters['page']!);
        if (page > 2) {
          throw StateError('链已断开，不应翻到第 $page 页');
        }
        return _json(
          _dailyPage(page == 1 ? page1 : page2, total: 150, page: page),
        );
      });
      final service = HttpStatsService(client: client, baseUrl: _base);

      final ov = await service.getOverview();
      expect(ov.streakDays, 100);
      expect(dailyCalls, 2);
    });

    test('getOverview 翻页推算：跨页连续则继续累计到 total', () async {
      final page1 = <Map<String, Object?>>[
        for (var i = 0; i < 100; i++) _dailyJson(_day(-i)),
      ];
      final page2 = <Map<String, Object?>>[
        for (var i = 100; i < 150; i++) _dailyJson(_day(-i)),
      ];
      var dailyCalls = 0;
      final client = MockClient((request) async {
        if (request.url.path == '/api/v1/stats/overview') {
          return _json(_overviewJson());
        }
        dailyCalls++;
        final page = int.parse(request.url.queryParameters['page']!);
        return _json(
          _dailyPage(page == 1 ? page1 : page2, total: 150, page: page),
        );
      });
      final service = HttpStatsService(client: client, baseUrl: _base);

      final ov = await service.getOverview();
      expect(ov.streakDays, 150);
      expect(dailyCalls, 2);
    });
  });

  group('未登录 / 离线 / 接口未就绪 → 回落 Mock（不编数字）', () {
    test('401（未登录 / 会话失效）三个方法都回落 Mock', () async {
      final client = MockClient((request) async {
        return _json(<String, Object?>{'detail': '未登录'}, 401);
      });
      final service = HttpStatsService(
        client: client,
        baseUrl: _base,
        fallback: MockStatsService(),
        tokenProvider: () => null,
      );

      final ov = await service.getOverview();
      expect(ov.answeredTotal, 0);
      expect(ov.correctRate, 0.0);
      expect(ov.streakDays, 0);
      expect(ov.todayAnswered, 0);
      expect(ov.todayCorrect, 0);

      final modules = await service.getByModule();
      expect(modules.length, 5);
      expect(modules.every((m) => m.answered == 0 && m.total == 0), isTrue);

      expect(await service.getDaily(), isEmpty);
    });

    test('网络异常（离线）回落 Mock，不抛给 UI', () async {
      final client = MockClient((request) async {
        throw Exception('offline');
      });
      final service = HttpStatsService(
        client: client,
        baseUrl: _base,
        fallback: MockStatsService(),
      );

      final ov = await service.getOverview();
      expect(ov.answeredTotal, 0);
      expect(ov.streakDays, 0);
      expect(
        (await service.getByModule()).every((m) => m.answered == 0),
        isTrue,
      );
      expect(await service.getDaily(), isEmpty);
    });

    test('404（接口未上线）回落 Mock', () async {
      final client = MockClient((request) async {
        return _json(<String, Object?>{}, 404);
      });
      final service = HttpStatsService(
        client: client,
        baseUrl: _base,
        fallback: MockStatsService(),
      );

      expect((await service.getOverview()).answeredTotal, 0);
      expect(await service.getDaily(), isEmpty);
    });

    test('200 但非 JSON 响应 → 按未就绪回落 Mock，不抛给 UI', () async {
      final client = MockClient((request) async {
        return http.Response('<html>gateway</html>', 200);
      });
      final service = HttpStatsService(
        client: client,
        baseUrl: _base,
        fallback: MockStatsService(),
      );

      expect((await service.getOverview()).answeredTotal, 0);
      expect(
        (await service.getByModule()).every((m) => m.answered == 0),
        isTrue,
      );
      expect(await service.getDaily(), isEmpty);
    });

    test('无兜底时：getOverview 抛异常，列表方法返回空（UI 走既有空态）', () async {
      final client = MockClient((request) async {
        return _json(<String, Object?>{}, 500);
      });
      final service = HttpStatsService(client: client, baseUrl: _base);

      await expectLater(
        service.getOverview(),
        throwsA(isA<StatsServiceException>()),
      );
      expect(await service.getByModule(), isEmpty);
      expect(await service.getDaily(), isEmpty);
    });
  });

  group('401 刷新一次并重放（AuthHttpClient + HttpStatsService）', () {
    test('overview 首次 401 → 刷新 token 重放成功，拿到真实数字', () async {
      final kv = InMemoryKvStore();
      final authorization = <String?>[];
      final client = MockClient((request) async {
        final path = request.url.path;
        if (path == '/api/v1/auth/login') {
          return _json(<String, Object?>{
            'accessToken': 'access-1',
            'refreshToken': 'refresh-1',
            'tokenType': 'Bearer',
            'expiresIn': 900,
            'user': <String, Object?>{
              'id': 7,
              'nickname': 'Max',
              'avatarUrl': null,
            },
          });
        }
        if (path == '/api/v1/auth/refresh') {
          return _json(<String, Object?>{
            'accessToken': 'access-2',
            'refreshToken': 'refresh-2',
            'tokenType': 'Bearer',
            'expiresIn': 900,
          });
        }
        if (path == '/api/v1/stats/overview') {
          final header = request.headers['authorization'];
          authorization.add(header);
          if (header == 'Bearer access-1') {
            return _json(<String, Object?>{'detail': '登录会话已失效'}, 401);
          }
          return _json(_overviewJson());
        }
        if (path == '/api/v1/stats/daily') {
          return _json(_dailyPage(const <Map<String, Object?>>[], total: 0));
        }
        return _json(<String, Object?>{}, 404);
      });
      final auth = HttpAuthService(
        client: client,
        kvStore: kv,
        secureStore: InMemorySecureSessionStore(),
        baseUrl: _base,
      );
      await auth.login(phone: '13800138000', password: 'secret123');
      final authed = AuthHttpClient(auth: auth, inner: client);
      final service = HttpStatsService(
        client: authed,
        baseUrl: _base,
        fallback: MockStatsService(),
        tokenProvider: () => auth.cachedAccessToken,
      );

      final ov = await service.getOverview();
      expect(ov.answeredTotal, 120);
      expect(ov.todayAnswered, 10);
      expect(authorization, <String>['Bearer access-1', 'Bearer access-2']);
      expect(auth.cachedAccessToken, 'access-2');
    });
  });
}
