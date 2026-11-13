class AppConfig {
  const AppConfig._();

  static const String appName = 'RoutePass';
  static const String appNameCn = '路由通';
  static const String version = '0.1.0';
  static const int buildNumber = 1;

  /// 题库后端地址（F10 接入 manifest 接口）。
  static const String baseUrl = 'http://198.23.213.22';

  static const bool moduleBank = false;
  static const bool moduleKnowledge = false;
  static const bool moduleToolbox = false;

  static String get versionLabel => '$appName v$version';
}
