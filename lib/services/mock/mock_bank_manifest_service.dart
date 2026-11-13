/// BankManifestService 的 Mock 实现（测试 / 离线用）。
///
/// 默认返回 2026-11-13 实测的线上清单（练习 1 条、考试 2 卷），让 widget
/// 测试不依赖网络也能覆盖真实数据结构。页面默认装配的是 HTTP 实现。
library;

import '../../models/bank_manifest.dart';
import '../bank/bank_manifest_service.dart';

/// 线上 `GET /api/v1/bank/manifest` 的真实响应（2026-11-13）。
const Map<String, dynamic> kLiveManifestJson = <String, dynamic>{
  'bankId': 'bank_default',
  'version': '1.0.0',
  'questionCount': 300,
  'knowledgeVersion': '1.0.0',
  'knowledgeCount': 5,
  'digest':
      'sha256:0f1a98e0e4870e7588d88cf9808b115cfcb2d672d44bb5365e56ffb6a31ae10a',
  'updatedAt': '2026-11-13T21:47:05.105395+08:00',
  'exams': <Map<String, dynamic>>[
    <String, dynamic>{
      'id': 'h3cne-2026-01',
      'title': 'H3CNE 模拟卷 A',
      'questionCount': 100,
    },
    <String, dynamic>{
      'id': 'h3cne-2026-02',
      'title': 'H3CNE 模拟卷 B',
      'questionCount': 100,
    },
  ],
  'practiceByModule': <String, dynamic>{'H3CNE': 100},
};

class MockBankManifestService implements BankManifestService {
  MockBankManifestService({BankManifest? manifest})
    : _manifest = manifest ?? defaultManifest;

  /// 与线上响应等价的默认清单。
  static final BankManifest defaultManifest = BankManifest.fromJson(
    kLiveManifestJson,
  );

  final BankManifest _manifest;

  @override
  Future<BankManifest> fetchManifest() async => _manifest;
}
