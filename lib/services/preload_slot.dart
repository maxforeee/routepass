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
/// 绝不阻塞导航，也不抛给 UI。fetch 同步抛错被吞掉（不占用 key）；
/// fetch 结果为 null（接口未就绪 / 数据不存在）不落槽，消费方回落重新拉取；
/// 永不完成的 fetch 由 [fetchTimeout] 兜底：超时把在途 Future 落定为失败
/// （等待中的消费方随之回落）并释放 key；已就绪结果在下次访问该 key 时
/// 按 [readyTtl] 做超龄检查，过期即丢弃（访问时的新鲜度检查，见 readyTtl）。
library;

import 'dart:async';

class PreloadSlot<T extends Object> {
  PreloadSlot({
    this.fetchTimeout = const Duration(seconds: 30),
    this.readyTtl = const Duration(minutes: 5),
  });

  /// 在途 fetch 的安全上限：超时按失败处理——在途 Future 以超时错误落定
  /// （已 await 的消费方收到失败并回落，不再永久挂起），同时清除在途标记
  /// （结果不落槽）。正常 HTTP 数据源自带 10s 请求超时，这里只兜底异常
  /// 实现；定时器在 Future 落定时取消，不留挂起定时器。迟到的落定被静默
  /// 吸收：不重复落定、不成为未处理异步错误、不污染同 key 的新 fetch。
  final Duration fetchTimeout;

  /// 已就绪结果的保鲜期：[start] / [take] / [pending] / [consume] 访问
  /// 该 key 时超龄即丢弃。注意这是访问时的新鲜度检查，不是内存上限——
  /// 从未被再次访问的 key 会驻留到 [debugClear]（或进程结束）。单个结果
  /// 体量小、key 空间有限（套卷 / 知识点 / 会话），驻留代价可控。
  final Duration readyTtl;

  final Map<String, Future<T?>> _inFlight = <String, Future<T?>>{};
  final Map<String, T> _ready = <String, T>{};
  final Map<String, DateTime> _readyAt = <String, DateTime>{};
  final Map<String, Timer> _watchdogs = <String, Timer>{};

  /// 后台发起 key 的预加载；已在途 / 已就绪直接返回。fetch 同步抛错不
  /// 占用 key；异步失败把在途 Future 落定为同一错误并清除标记（结果不
  /// 落槽，消费方回落）；fetch 返回 null 同样不落槽，由目标页消费时自行
  /// 兜底重新拉取。
  void start(String key, Future<T?> Function() fetch) {
    if (key.isEmpty) return;
    _expireReady(key);
    if (_ready.containsKey(key) || _inFlight.containsKey(key)) return;
    final Future<T?> future;
    try {
      future = fetch();
    } catch (_) {
      return;
    }
    // F30：槽位自持 Completer，超时不只释放 key，还把在途 Future 落定为
    // 失败——已 await 的消费方（consume / pending）随之回落，不再永久挂起。
    final completer = Completer<T?>();
    final guarded = completer.future;
    // 无人消费时失败也不成为未处理异步错误。
    guarded.catchError((Object _) => null);
    _inFlight[key] = guarded;
    _watchdogs.remove(key)?.cancel();
    late final Timer watchdog;
    watchdog = Timer(fetchTimeout, () {
      // F30：同 key 已挂上新兜底定时器时，旧回调不得误删新定时器。
      if (!identical(_watchdogs[key], watchdog)) return;
      _watchdogs.remove(key);
      if (identical(_inFlight[key], guarded)) _inFlight.remove(key);
      if (!completer.isCompleted) {
        completer.completeError(
          TimeoutException('preload fetch timeout', fetchTimeout),
        );
      }
    });
    _watchdogs[key] = watchdog;
    future
        .then((value) {
          // F30：迟到落定不得取消同 key 新 fetch 的兜底定时器。
          if (identical(_watchdogs[key], watchdog)) {
            _watchdogs.remove(key);
            watchdog.cancel();
          }
          if (!completer.isCompleted) completer.complete(value);
          // 超时释放后 key 可能已被新的 fetch 占用：旧结果不再落槽。
          if (!identical(_inFlight[key], guarded)) return;
          _inFlight.remove(key);
          if (value != null) {
            _ready[key] = value;
            _readyAt[key] = DateTime.now();
          }
        })
        .catchError((Object error) {
          if (identical(_watchdogs[key], watchdog)) {
            _watchdogs.remove(key);
            watchdog.cancel();
          }
          if (!completer.isCompleted) completer.completeError(error);
          if (identical(_inFlight[key], guarded)) _inFlight.remove(key);
        });
  }

  /// 消费已就绪结果（取走即清除）；未就绪 / 已过期返回 null。
  T? take(String key) {
    _expireReady(key);
    _readyAt.remove(key);
    return _ready.remove(key);
  }

  /// 在途 Future（不移除标记：落定前重复查询拿到同一个 Future）。
  Future<T?>? pending(String key) {
    _expireReady(key);
    return _inFlight[key];
  }

  /// 目标页统一消费入口：就绪 → 立即完成；在途 → 同一个 Future（标记
  /// 保留到 Future 落定，由 [start] 的回调清除，并发消费不发第二次请求）；
  /// 都没有 → [fallback]。在途结果为 null（接口未就绪）时同样回落
  /// [fallback] 重新拉取。fallback 可返回 null，原样透传给调用方兜底。
  Future<T?> consume(String key, Future<T?> Function() fallback) {
    _expireReady(key);
    final ready = _ready.remove(key);
    if (ready != null) {
      _readyAt.remove(key);
      return Future<T>.value(ready);
    }
    final pending = _inFlight[key];
    if (pending != null) {
      // F30：在途 fetch 失败（含兜底超时）同样回落 fallback——
      // 「预加载失败静默回落」在槽位层面强制，不把错误抛给消费方。
      return pending.then(
        (value) => value ?? fallback(),
        onError: (_) => fallback(),
      );
    }
    return fallback();
  }

  /// 测试辅助：清空全部状态（含取消在途兜底定时器）。
  void debugClear() {
    for (final timer in _watchdogs.values) {
      timer.cancel();
    }
    _watchdogs.clear();
    _ready.clear();
    _readyAt.clear();
    _inFlight.clear();
  }

  void _expireReady(String key) {
    final at = _readyAt[key];
    if (at == null) return;
    if (DateTime.now().difference(at) >= readyTtl) {
      _ready.remove(key);
      _readyAt.remove(key);
    }
  }
}
