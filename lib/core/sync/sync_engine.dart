/// 同步引擎抽象（规格文档第 4 章 §4.2 第 15 行列出的文件位置）。
///
/// 注意：文档只列出本文件位置，未定义 SyncEngine 的方法契约——
/// 同步的对外方法全部在 SyncService（见 lib/services/bank/bank_sync_service.dart）。
/// 本文件先只占位：以后接真实同步引擎时在此补方法，UI 不直接依赖它。
/// 现在不许往里面加任何方法、网络或数据库调用。
library;

abstract class SyncEngine {}
