class AppConfig {
  const AppConfig._();

  static const String appName = 'RoutePass';
  static const String appNameCn = '路由通';

  /// 与 pubspec.yaml 的 version 保持同步（test/f34_app_version_test.dart
  /// 守卫漂移：发版只改 pubspec 时这里忘了同步会直接挂测试）。
  static const String version = '1.0.0';
  static const int buildNumber = 17;

  /// 题库后端地址（F10 接入 manifest 接口）。
  /// W1：可用 --dart-define=API_BASE_URL=... 在构建期覆盖（web 部署在
  /// HTTPS 页面时必须指向 HTTPS 后端，否则浏览器按混合内容拦截）；
  /// 默认值不变，Android 行为不受影响。
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://198.23.213.22',
  );

  static const bool moduleBank = false;
  static const bool moduleKnowledge = false;
  static const bool moduleToolbox = false;

  static String get versionLabel => '$appName v$version';
}
