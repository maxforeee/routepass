/// PingService 的 Mock 实现（规格文档第 4 章 §4.6.3）。
///
/// 接口齐全，执行返回占位状态 {state: 'not_connected', message: '待接本地服务'}，
/// 绝不许假装跑出了时延数字；以后由本地 Dart Socket 实现替换。
library;

import '../../models/toolbox.dart';
import '../toolbox/ping_service.dart';

class MockPingService implements PingService {
  @override
  Future<PingResult> ping({
    required String host,
    required int port,
    int timeoutMs = 3000,
  }) async {
    return PingResult(state: 'not_connected', message: '待接本地服务');
  }
}
