/// 子网计算服务抽象接口（规格文档第 4 章 §4.6.1）。
///
/// 服务的页面：工具箱 T-B1、T-B3、T-B4。
/// 现在就是本地真实实现（v3.1 第 16.1 节算法），永不走服务器；本任务只写抽象接口。
library;

import '../../models/toolbox.dart';

abstract class SubnetCalcService {
  /// 子网计算。调用时机：用户输完 IP/掩码点“计算”时（T-08）。
  /// 现在就是真实实现，按 v3.1 第 16.1 节纯位运算算法，不走 Mock、不走服务器。
  /// 返回：网络地址、广播地址、可用范围、主机数、掩码、反掩码、二进制（T-09 结果表字段）。
  Future<SubnetResult> calculate({required String ip, required int prefix});

  /// VLSM 拆分（加分项，第 16.1 节）。现在可先返回“暂不支持”占位，以后在 Service 内补算法，页面不动。
  Future<VlsmPlan?> planVlsm({
    required String network,
    required List<int> hostCounts,
  });
}
