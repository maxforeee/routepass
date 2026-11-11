/// ContentService 的 Mock 实现（规格文档第 4 章 §4.7.2）。
///
/// 返回本地写死的版本号常量；升级检查恒返回 {compatibility: 'ok'}，永不触发升级。
library;

import '../../models/content.dart';
import '../base/content_service.dart';

class MockContentService implements ContentService {
  @override
  Future<ContentVersion> getContentVersion() async {
    return ContentVersion(
      pair_seq: 0,
      bank_version: '1.0.0',
      knowledge_version: '1.0.0',
      bank_count: 0,
      knowledge_count: 0,
      status: 'active',
    );
  }

  @override
  Future<UpgradeCheck> checkUpgrade() async {
    return UpgradeCheck(
      latest: '0.1.0',
      min_supported: '0.1.0',
      compatibility: 'ok',
      upgrade_url: '',
      force: false,
    );
  }

  @override
  Future<Capabilities> getCapabilities() async {
    return Capabilities(
      features: <String>[],
      supported_question_types: <String>['single', 'multiple'],
    );
  }
}
