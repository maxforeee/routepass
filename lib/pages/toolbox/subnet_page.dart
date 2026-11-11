import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_snackbar.dart';
import '../../core/service_locator.dart';
import '../../core/theme.dart';
import '../../models/toolbox.dart';
import 'toolbox_tools.dart';

class SubnetPage extends StatefulWidget {
  const SubnetPage({super.key});

  @override
  State<SubnetPage> createState() => _SubnetPageState();
}

class _SubnetPageState extends State<SubnetPage> {
  final _ipController = TextEditingController();
  final _prefixController = TextEditingController(text: '24');
  final _maskController = TextEditingController();
  int _mode = 0; // 0 = CIDR 前缀，1 = 点分掩码
  SubnetResult? _result;
  String? _error;
  bool _calculating = false;

  @override
  void initState() {
    super.initState();
    recordRecentTool('subnet');
  }

  @override
  void dispose() {
    _ipController.dispose();
    _prefixController.dispose();
    _maskController.dispose();
    super.dispose();
  }

  Future<void> _calculate() async {
    final ip = _ipController.text.trim();
    if (ip.isEmpty) {
      setState(() {
        _error = '请输入 IP 地址';
        _result = null;
      });
      return;
    }
    late final int prefix;
    try {
      prefix = _mode == 0
          ? int.parse(_prefixController.text.trim())
          : _maskToPrefix(_maskController.text);
    } on FormatException catch (e) {
      setState(() {
        _error = e.message;
        _result = null;
      });
      return;
    }
    setState(() {
      _calculating = true;
      _error = null;
    });
    try {
      final result = await ServiceLocator.subnetCalcService.calculate(
        ip: ip,
        prefix: prefix,
      );
      if (!mounted) return;
      setState(() => _result = result);
    } on FormatException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _result = null;
      });
    } finally {
      if (mounted) setState(() => _calculating = false);
    }
  }

  /// 点分掩码转前缀长度；不是合法掩码形状（前 1 后 0）时抛 FormatException。
  int _maskToPrefix(String text) {
    final parts = text.trim().split('.');
    if (parts.length != 4) {
      throw const FormatException('掩码格式错误');
    }
    var value = 0;
    for (final p in parts) {
      final v = int.tryParse(p);
      if (v == null || v < 0 || v > 255) {
        throw const FormatException('掩码格式错误');
      }
      value = (value << 8) | v;
    }
    var prefix = 0;
    for (var i = 31; i >= 0; i--) {
      if ((value & (1 << i)) != 0) {
        prefix++;
      } else {
        break;
      }
    }
    final expected = prefix == 0
        ? 0
        : (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF;
    if (value != expected) {
      throw const FormatException('掩码不是合法的子网掩码');
    }
    return prefix;
  }

  void _copy(String value) {
    Clipboard.setData(ClipboardData(text: value));
    showAppSnackBar(context, '已复制');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('子网计算器')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _ipController,
              decoration: const InputDecoration(
                labelText: 'IP 地址',
                hintText: '192.168.1.10',
                border: OutlineInputBorder(),
              ),
              style: monoTextStyle(context, fontSize: 15),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('CIDR 前缀')),
                ButtonSegment(value: 1, label: Text('点分掩码')),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
            const SizedBox(height: 12),
            if (_mode == 0)
              TextField(
                controller: _prefixController,
                decoration: const InputDecoration(
                  labelText: 'CIDR 前缀',
                  hintText: '24',
                  border: OutlineInputBorder(),
                ),
                style: monoTextStyle(context, fontSize: 15),
                keyboardType: TextInputType.number,
              )
            else
              TextField(
                controller: _maskController,
                decoration: const InputDecoration(
                  labelText: '子网掩码',
                  hintText: '255.255.255.0',
                  border: OutlineInputBorder(),
                ),
                style: monoTextStyle(context, fontSize: 15),
                keyboardType: TextInputType.number,
              ),
            const SizedBox(height: 16),
            SizedBox(
              height: 48,
              child: FilledButton(
                onPressed: _calculating ? null : _calculate,
                child: Text(_calculating ? '计算中…' : '计算'),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            if (result != null) ...[
              const SizedBox(height: 16),
              Card(
                child: Column(
                  children: [
                    _ResultRow(
                      label: '网络地址',
                      value: result.network,
                      onCopy: _copy,
                    ),
                    _ResultRow(
                      label: '广播地址',
                      value: result.broadcast,
                      onCopy: _copy,
                    ),
                    _ResultRow(
                      label: '可用范围',
                      value: '${result.firstHost} - ${result.lastHost}',
                      onCopy: _copy,
                    ),
                    _ResultRow(
                      label: '可用主机数',
                      value: '${result.hostCount}',
                      onCopy: _copy,
                    ),
                    _ResultRow(
                      label: '子网掩码',
                      value: result.netmask,
                      onCopy: _copy,
                    ),
                    _ResultRow(
                      label: '反掩码',
                      value: result.wildcard,
                      onCopy: _copy,
                    ),
                    _ResultRow(
                      label: '网络二进制',
                      value: result.binaryNetwork,
                      onCopy: _copy,
                    ),
                    _ResultRow(
                      label: '掩码二进制',
                      value: result.binaryNetmask,
                      onCopy: _copy,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.label,
    required this.value,
    required this.onCopy,
  });

  final String label;
  final String value;
  final ValueChanged<String> onCopy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          SizedBox(width: 88, child: Text(label)),
          Expanded(
            child: Text(
              value,
              style: monoTextStyle(context, fontSize: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 24),
            onPressed: () => onCopy(value),
            tooltip: '复制',
          ),
        ],
      ),
    );
  }
}
