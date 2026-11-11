/// 端口扫描服务抽象接口（规格文档第 4 章 §4.6.4）。
///
/// 服务的页面：工具箱 端口扫描（第 16.3 节）。
/// 现在：接口 + UI 齐全，执行返回“待接本地服务”占位；以后：本地 Dart Socket 实现，永不走服务器。
library;

import '../../models/toolbox.dart';

abstract class PortScanService {
  /// 端口扫描：对目标主机的一组常用端口做 TCP 连接探测（v3.1 第 16.3 节）。
  /// 现在：接口与 UI 齐全，执行时返回占位状态，页面展示“待接本地服务”。
  /// 以后：本地 Dart Socket 实现，不走服务器；历史写入 tool_history。
  /// 合规：首次进入端口扫描必须弹确认（第 2 章 §14.17），未同意不能开始执行。
  Future<PortScanResult> scan({required String host, required List<int> ports});
}
