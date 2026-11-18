/// F34：展示版本号漂移守卫。
///
/// `AppConfig.version` / `buildNumber` 是手工常量（versionLabel 等处展示），
/// 发版只改 pubspec.yaml 时容易忘了同步（F23 遗留：pubspec 已到 0.2.12+14，
/// 常量还停在 0.2.8）。这里直接读 pubspec.yaml 的 version 行比对：
/// 漂移即测试失败，不再靠人肉记。`flutter test` 的工作目录是项目根。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/core/config.dart';

void main() {
  test('AppConfig.version / buildNumber 与 pubspec.yaml 一致', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version:\s*(\S+)\s*$',
      multiLine: true,
    ).firstMatch(pubspec);
    expect(match, isNotNull, reason: 'pubspec.yaml 必须声明 version');
    final parts = match!.group(1)!.split('+');
    expect(
      AppConfig.version,
      parts[0],
      reason: 'AppConfig.version 落后于 pubspec.yaml——发版请同步',
    );
    expect(
      AppConfig.buildNumber,
      int.parse(parts[1]),
      reason: 'AppConfig.buildNumber 落后于 pubspec.yaml——发版请同步',
    );
  });
}
