/// BankManifestService 的 HTTP 实现。
///
/// `GET {baseUrl}/api/v1/bank/manifest` 是公开接口（无需鉴权）。baseUrl 来自
/// AppConfig，由 main.dart 装配时注入，页面里不出现任何后端地址。
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config.dart';
import '../../models/bank_manifest.dart';
import 'bank_manifest_service.dart';

class HttpBankManifestService implements BankManifestService {
  HttpBankManifestService({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? AppConfig.baseUrl;

  final http.Client _client;
  final String _baseUrl;

  static const Duration _timeout = Duration(seconds: 10);

  @override
  Future<BankManifest> fetchManifest() async {
    final uri = Uri.parse('$_baseUrl/api/v1/bank/manifest');
    final http.Response response;
    try {
      response = await _client.get(uri).timeout(_timeout);
    } catch (e) {
      throw BankManifestException('题库清单请求失败：$e');
    }

    if (response.statusCode != 200) {
      throw BankManifestException('题库清单请求失败（HTTP ${response.statusCode}）');
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (e) {
      throw BankManifestException('题库清单解析失败：$e');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const BankManifestException('题库清单格式错误');
    }
    return BankManifest.fromJson(decoded);
  }
}
