import 'package:flutter/material.dart';

import '../../core/service_locator.dart';
import '../../core/theme.dart';
import '../../models/toolbox.dart';
import 'toolbox_tools.dart';

class PingPage extends StatefulWidget {
  const PingPage({super.key});

  @override
  State<PingPage> createState() => _PingPageState();
}

class _PingPageState extends State<PingPage> {
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '80');
  PingResult? _result;
  String? _error;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    recordRecentTool('ping');
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim());
    if (host.isEmpty) {
      setState(() {
        _error = '请输入目标主机';
        _result = null;
      });
      return;
    }
    if (port == null || port < 1 || port > 65535) {
      setState(() {
        _error = '端口应为 1–65535 的数字';
        _result = null;
      });
      return;
    }
    setState(() {
      _running = true;
      _error = null;
    });
    final result = await ServiceLocator.pingService.ping(
      host: host,
      port: port,
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
      appBar: AppBar(title: const Text('Ping')),
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
            TextField(
              controller: _portController,
              decoration: const InputDecoration(
                labelText: '端口',
                hintText: '80',
                border: OutlineInputBorder(),
              ),
              style: monoTextStyle(context, fontSize: 15),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 48,
              child: FilledButton(
                onPressed: _running ? null : _start,
                child: Text(_running ? '探测中…' : '开始'),
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
                      Text('状态：${result.message}', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      const Text('本地 TCP 探测暂未接入执行，不会假装跑出时延。'),
                      const SizedBox(height: 4),
                      const Text('Ping 为 TCP 端口探测（非 ICMP），以后由本地 Socket 实现。'),
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
