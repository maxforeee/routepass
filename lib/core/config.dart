class AppConfig {
  const AppConfig._();

  static const String appName = 'RoutePass';
  static const String appNameCn = '路由通';
  static const String version = '0.1.0';
  static const int buildNumber = 1;

  /// 后端尚未接入，暂时为空字符串。
  static const String baseUrl = '';

  static const bool moduleBank = false;
  static const bool moduleKnowledge = false;
  static const bool moduleToolbox = false;

  static String get versionLabel => '$appName v$version';
}
