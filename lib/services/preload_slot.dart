/// F27 预测性预加载的通用存储槽。
///
/// 一个槽对应一类目标页数据，按 key（setId / sessionId / kpId / 抽题参数）
/// 存「在途 Future」与「已就绪结果」：
/// - [start] 后台发起一次 fetch，同 key 不重复发；失败静默丢弃。
/// - [take] / [pending] 供目标页 initState 消费：就绪直接拿数据，
///   在途则 await 同一个 Future，不再发第二次请求。
/// - [consume] 就绪 / 在途 / 都没有 三态统一入口，都没有时走调用方的
///   原始 fetch（页面行为与无预加载时完全一致）。
///
/// 预加载只是优化：任何一步失败都回落到页面自身加载路径（骨架 + 淡入），
/// 绝不阻塞导航，也不抛给 UI。
library;

class PreloadSlot<T extends Object> {
  final Map<String, Future<T>> _inFlight = <String, Future<T>>{};
  final Map<String, T> _ready = <String, T>{};

  /// 后台发起 key 的预加载；已在途 / 已就绪直接返回。fetch 抛错只清除
  /// 在途标记（结果不落槽），由目标页自行兜底。
  void start(String key, Future<T> Function() fetch) {
    if (key.isEmpty) return;
    if (_ready.containsKey(key) || _inFlight.containsKey(key)) return;
    final future = fetch();
    _inFlight[key] = future;
    future
        .then((value) {
          _ready[key] = value;
          _inFlight.remove(key);
        })
        .catchError((Object _) {
          _inFlight.remove(key);
        });
  }

  /// 消费已就绪结果（取走即清除）；未就绪返回 null。
  T? take(String key) => _ready.remove(key);

  /// 在途 Future（不移除标记：页面消费前的重复查询拿到同一个 Future）。
  Future<T>? pending(String key) => _inFlight[key];

  /// 目标页统一消费入口：就绪 → 立即完成；在途 → 同一个 Future（取走
  /// 标记，消费后再次进入会重新拉取，保证数据新鲜）；都没有 → [fallback]。
  /// fallback 可返回 null（接口未就绪 / 离线），原样透传给调用方兜底。
  Future<T?> consume(String key, Future<T?> Function() fallback) {
    final ready = _ready.remove(key);
    if (ready != null) return Future<T>.value(ready);
    final pending = _inFlight.remove(key);
    if (pending != null) return pending;
    return fallback();
  }

  /// 测试辅助：清空全部状态。
  void debugClear() {
    _ready.clear();
    _inFlight.clear();
  }
}
