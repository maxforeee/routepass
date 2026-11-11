/// PortScanService 的 Mock 实现（规格文档第 4 章 §4.6.4）。
///
/// 接口齐全，执行返回占位状态，页面展示“待接本地服务”；
/// 以后由本地 Dart Socket 实现替换。
library;

import '../../models/toolbox.dart';
import '../toolbox/port_scan_service.dart';

class MockPortScanService implements PortScanService {
  @override
  Future<PortScanResult> scan({
    required String host,
    required List<int> ports,
  }) async {
    return PortScanResult(
      state: 'not_connected',
      message: '待接本地服务',
      openPorts: <int>[],
    );
  }
}
