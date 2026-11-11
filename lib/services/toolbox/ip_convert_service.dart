/// IP/进制转换服务抽象接口（规格文档第 4 章 §4.6.2）。
///
/// 服务的页面：工具箱 T-B2、T-B3 的计算部分。
/// 现在就是本地真实实现，纯本地计算，永不走服务器；本任务只写抽象接口。
library;

import '../../models/toolbox.dart';

abstract class IpConvertService {
  /// IP ↔ 进制互转、CIDR ↔ 掩码互转（T-B2、T-B3 的计算部分）。
  /// 现在就是真实实现，纯本地计算，不走服务器。
  Future<IpConvertResult> convert(String input);
}
