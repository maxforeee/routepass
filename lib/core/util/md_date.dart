/// 毫秒时间戳 → 月-日（MM-dd）文案。
///
/// 错题本 / 收藏页条目的“加入日期”用；不引 intl，手动补零即可。
library;

String formatMonthDay(int milliseconds) {
  final time = DateTime.fromMillisecondsSinceEpoch(milliseconds);
  final month = time.month.toString().padLeft(2, '0');
  final day = time.day.toString().padLeft(2, '0');
  return '$month-$day';
}
