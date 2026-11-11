/// 通用结果封装：成功带值 / 失败带 message。
///
/// 用于可能失败的本地操作（如 kv 读写、后续的本地服务调用），
/// 避免在 UI 层到处 try/catch。
class Result<T> {
  const Result._ok(this._value)
      : _message = null,
        isOk = true,
        isErr = false;

  const Result._err(this._message)
      : _value = null,
        isOk = false,
        isErr = true;

  final T? _value;
  final String? _message;

  /// 是否成功。
  final bool isOk;

  /// 是否失败。
  final bool isErr;

  /// 成功时的值；失败时为 null。
  T? get valueOrNull => _value;

  /// 失败时的错误信息；成功时为 null。
  String? get message => _message;

  /// 构造成功结果。
  static Result<T> ok<T>(T value) => Result<T>._ok(value);

  /// 构造失败结果。
  static Result<T> err<T>(String message) => Result<T>._err(message);

  @override
  String toString() =>
      isOk ? 'Result.ok($valueOrNull)' : 'Result.err($_message)';
}
