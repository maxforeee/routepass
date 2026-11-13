import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/core/config.dart';

/// F12: 题库清单走 `http://198.23.213.22`（裸 IP、无证书）。Android 9+ 默认
/// 禁止明文 HTTP，且 release 构建不会合并 debug 的 INTERNET 权限，所以这两项
/// 必须写在 main 的 manifest / 网络安全配置里，否则手机上的题库页只会显示
/// “题库清单加载失败”。
void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml')
      .readAsStringSync();

  group('F12 Android 明文 HTTP 配置', () {
    test('main manifest 声明 INTERNET 权限', () {
      expect(
        manifest,
        contains(
          '<uses-permission android:name="android.permission.INTERNET"/>',
        ),
      );
    });

    test('application 引用 networkSecurityConfig', () {
      expect(
        manifest,
        contains(
          'android:networkSecurityConfig="@xml/network_security_config"',
        ),
      );
    });

    test('网络安全配置只对后端主机放开 cleartext', () {
      final configFile = File(
        'android/app/src/main/res/xml/network_security_config.xml',
      );
      expect(configFile.existsSync(), isTrue);
      final config = configFile.readAsStringSync();

      expect(config, contains('cleartextTrafficPermitted="true"'));

      final host = Uri.parse(AppConfig.baseUrl).host;
      expect(
        config,
        contains('<domain includeSubdomains="false">$host</domain>'),
      );
      expect(AppConfig.baseUrl, startsWith('http://'));
    });
  });
}
