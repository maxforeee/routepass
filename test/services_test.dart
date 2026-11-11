import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/services/mock/mock_content_service.dart';
import 'package:routepass/services/mock/mock_exam_service.dart';
import 'package:routepass/services/mock/mock_ping_service.dart';
import 'package:routepass/services/mock/mock_question_repository.dart';
import 'package:routepass/services/mock/mock_stats_service.dart';
import 'package:routepass/services/toolbox/ip_convert_service_impl.dart';
import 'package:routepass/services/toolbox/subnet_calc_service_impl.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Mock 样例题：3 道、answer 为 []、explanation 为空、题干以开头', () async {
 final repo = MockQuestionRepository();
 final questions = await repo.drawQuestions(mode: 'quick', drawCount: 10);
 expect(questions.length, 3);
 for (final q in questions) {
 expect(q.answer, isEmpty);
 expect(q.explanation, isEmpty);
 expect(q.stem.startsWith(''), isTrue);
}
 final modules = await repo.getModules();
 expect(modules.length, 5);
 expect(modules.every((m) => m.total == 0), isTrue);
});

 test('Mock 统计全 0', () async {
 final stats = MockStatsService();
 final overview = await stats.getOverview();
 expect(overview.answeredTotal, 0);
 expect(overview.todayAnswered, 0);
});

 test('子网计算 192.168.1.0/24', () async {
 final svc = LocalSubnetCalcService();
 final r = await svc.calculate(ip: '192.168.1.0', prefix: 24);
 expect(r.network, '192.168.1.0');
 expect(r.broadcast, '192.168.1.255');
 expect(r.firstHost, '192.168.1.1');
 expect(r.lastHost, '192.168.1.254');
 expect(r.hostCount, 254);
 expect(r.netmask, '255.255.255.0');
 expect(r.wildcard, '0.0.0.255');
 final vlsm = await svc.planVlsm(
 network: '192.168.1.0/24',
 hostCounts: [50, 20],
);
 expect(vlsm, isNull);
});

 test('IP/进制转换', () async {
 final svc = LocalIpConvertService();
 final a = await svc.convert('192.168.1.1');
 expect(a.decimal, '3232235777');
 expect(a.hex, '0xC0A80101');
 final b = await svc.convert('/24');
 expect(b.cidr, '/24');
 expect(b.netmask, '255.255.255.0');
 final c = await svc.convert('255.255.255.0');
 expect(c.cidr, '/24');
});

 test('Mock 考试不计分：score 为 null', () async {
 final svc = MockExamService();
 final session = await svc.startExam(drawCount: 100);
 expect(session.total, 3);
 final result = await svc.submitExam(
 examId: session.id,
 answers: {},
 durationMs: 0,
);
 expect(result?.score, isNull);
});

 test('Mock Ping 返回待接本地服务占位', () async {
 final svc = MockPingService();
 final r = await svc.ping(host: '192.168.1.1', port: 80);
 expect(r.state, 'not_connected');
 expect(r.message, '待接本地服务');
 expect(r.latencyMs, isNull);
});

 test('Mock 内容版本与升级检查永不触发升级', () async {
 final svc = MockContentService();
 final v = await svc.getContentVersion();
 expect(v.bank_version, '1.0.0');
 final check = await svc.checkUpgrade();
 expect(check.compatibility, 'ok');
 expect(check.force, isFalse);
});
}
