/// 题库清单服务抽象接口。
///
/// 页面只依赖本接口；真实实现走 `GET /api/v1/bank/manifest`，测试用 Mock。
/// 换实现只改 main.dart 的装配与 config.dart 的 baseUrl。
library;

import '../../models/bank_manifest.dart';

/// 题库清单请求失败（网络错误 / 非 200 / 响应格式不对）。
class BankManifestException implements Exception {
  const BankManifestException(this.message);

  final String message;

  @override
  String toString() => 'BankManifestException: $message';
}

abstract class BankManifestService {
  /// 拉取题库清单：练习记录（1 条/模块）+ 考试卷列表。
  Future<BankManifest> fetchManifest();
}
