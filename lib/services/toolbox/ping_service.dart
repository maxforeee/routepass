/// Ping 服务抽象接口（规格文档第 4 章 §4.6.3）。
///
/// 服务的页面：工具箱 Ping（第 16.2 节）。
/// 现在：接口 + UI 齐全，执行返回“待接本地服务”占位；以后：本地 Dart Socket 实现，永不走服务器。
library;

import '../../models/toolbox.dart';

abstract class PingService {
  /// TCP 探测：对目标端口做 TCP 连接测时延，非 ICMP（v3.1 第 16.2 节）。
  /// 调用时机：用户输目标点“开始”时。超时 3 秒，可中断，不卡界面（第 16.2 节 D4）。
  /// 现在：接口与 UI 齐全，执行时返回占位状态 {state: 'not_connected', message: '待接本地服务'}，
  /// 页面按第 3 章 §22.10 的占位态展示，绝不许假装跑出了时延数字。
  /// 以后：本地 Dart Socket 实现，不走服务器；历史写入 tool_history（最近 50 条，不上传服务端）。
  Future<PingResult> ping({
    required String host,
    required int port,
    int timeoutMs = 3000,
  });
}
