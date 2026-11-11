import 'package:flutter/material.dart';

import '../../core/service_locator.dart';
import '../../core/theme.dart';
import '../../models/toolbox.dart';
import 'toolbox_tools.dart';

/// 端口扫描合规确认的 kv 键（派生键，不在规格文档 §4.9.1 表内，与 `kb.masteredIds` 同例，只存本地）。
const _kPortScanConsent = 'toolbox.portscanConsent';

/// 扫描的常用端口（固定列表，展示用）。
const _commonPorts = <int>[
  21,
  22,
  23,
  25,
  53,
  80,
  110,
  143,
  443,
  445,
  3306,
  3389,
  8080,
];

class PortScanPage extends StatefulWidget {
  const PortScanPage({super.key});

  @override
  State<PortScanPage> createState() => _PortScanPageState();
}

class _PortScanPageState extends State<PortScanPage> {
  final _hostController = TextEditingController();
  PortScanResult? _result;
  String? _error;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    recordRecentTool('portscan');
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowConsent());
  }

  @override
  void dispose() {
    _hostController.dispose();
    super.dispose();
  }

  bool get _consented =>
      ServiceLocator.kvStore.getString(_kPortScanConsent) == '1';

  /// 未确认过合规声明时，进页弹一次确认 dialog。
  Future<void> _maybeShowConsent() async {
    if (!mounted || _consented) return;
    await _showConsentDialog();
  }

  Future<bool> _showConsentDialog() async {
    final agreed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('合规确认'),
        content: const Text('端口扫描仅可用于你拥有或已获授权的设备。扫描他人设备可能违反法律法规。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('我已知晓并确认'),
          ),
        ],
      ),
    );
    if (agreed == true) {
      ServiceLocator.kvStore.setString(_kPortScanConsent, '1');
    }
    return agreed == true;
  }

  Future<void> _start() async {
    if (!_consented) {
      await _showConsentDialog();
      return;
    }
    final host = _hostController.text.trim();
    if (host.isEmpty) {
      setState(() {
        _error = '请输入目标主机';
        _result = null;
      });
      return;
    }
    setState(() {
      _running = true;
      _error = null;
    });
    final result = await ServiceLocator.portScanService.scan(
      host: host,
      ports: _commonPorts,
    );
    if (!mounted) return;
    setState(() {
      _running = false;
      _result = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('端口扫描')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _hostController,
              decoration: const InputDecoration(
                labelText: '目标主机',
                hintText: '192.168.1.1 或域名',
                border: OutlineInputBorder(),
              ),
              style: monoTextStyle(context, fontSize: 15),
            ),
            const SizedBox(height: 12),
            Text('扫描端口', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in _commonPorts)
                  Chip(
                    label: Text(
                      '$p',
                      style: monoTextStyle(context, fontSize: 13),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 48,
              child: FilledButton(
                onPressed: _running ? null : _start,
                child: Text(_running ? '扫描中…' : '开始'),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            if (result != null) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '状态：${result.message}',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      const Text('开放端口：—'),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
