/// 内容服务抽象接口（规格文档第 4 章 §4.7.2）。
///
/// 服务的组件：G-02、G-05 强制升级 dialog、H-B12。
/// 现在的实现是 Mock（本地写死的版本号常量）；以后真实实现走
/// `GET /meta/version`（唯一升级源）、`GET /meta/capabilities`、
/// `GET /bank/manifest`、`/knowledge/manifest`、`/content/manifest`。
library;

import '../../models/content.dart';

abstract class ContentService {
  /// 内容版本（题库 + 知识库配对版本）。调用时机：启动时 1 次、进首页时 1 次。
  /// Mock：返回本地写死的常量 {bankVersion: '1.0.0', knowledgeVersion: '1.0.0', pairSeq: 0}。
  /// 以后：GET /content/manifest（?since=pair_seq 增量），配对表见 §4.8.8。
  Future<ContentVersion> getContentVersion();

  /// 检查升级。调用时机：启动时 1 次。
  /// Mock：返回 {compatibility: 'ok'}，永不触发升级。
  /// 以后：GET /meta/version（唯一升级源，Cache-Control: no-store），返回
  /// {latest, min_supported, compatibility: 'ok' | 'soft' | 'hard', upgrade_url, force}。
  /// compatibility 为 'hard' 或收到 426（client_major < server_floor）→ 弹 G-05，不可关闭；
  /// 为 'soft' → G-02 显示轻量提示“现在更新 / 稍后”，不中断当前会话（第 1 章终裁第 4 条）。
  Future<UpgradeCheck> checkUpgrade();

  /// 能力查询（仅能力 flag，不含任何升级字段）。Mock：返回 {features: [], supported_question_types: ['single', 'multiple']}。
  /// 以后：GET /meta/capabilities。升级判断只看 /meta/version，不看 capabilities（v3.1 D13）。
  Future<Capabilities> getCapabilities();
}
