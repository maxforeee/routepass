import 'package:flutter/material.dart';

import '../../core/service_locator.dart';
import '../../core/theme.dart';
import '../../models/toolbox.dart';
import 'tool_result_row.dart';
import 'toolbox_tools.dart';

class CidrPage extends StatefulWidget {
  const CidrPage({super.key});

  @override
  State<CidrPage> createState() => _CidrPageState();
}

class _CidrPageState extends State<CidrPage> {
  final _inputController = TextEditingController();
  IpConvertResult? _result;
  String? _error;
  bool _converting = false;

  @override
  void initState() {
    super.initState();
    recordRecentTool('cidr');
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _convert() async {
    final input = _inputController.text.trim();
    if (input.isEmpty) {
      setState(() {
        _error = '请输入 CIDR 前缀或子网掩码';
        _result = null;
      });
      return;
    }
    setState(() {
      _converting = true;
      _error = null;
    });
    final result = await ServiceLocator.ipConvertService.convert(input);
    if (!mounted) return;
    setState(() {
      _converting = false;
      if (result.cidr == null && result.netmask == null) {
        _error = '无法识别的输入';
        _result = null;
      } else {
        _result = result;
      }
    });
  }

  int _hostCount(int prefix) {
    if (prefix == 32) return 1;
    if (prefix == 31) return 2;
    return (1 << (32 - prefix)) - 2;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = _result;
    final prefix = result?.cidr == null
        ? null
        : int.tryParse(result!.cidr!.substring(1));
    return Scaffold(
      appBar: AppBar(title: const Text('CIDR↔掩码')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _inputController,
              decoration: const InputDecoration(
                labelText: '输入',
                hintText: '/24 或 255.255.255.0',
                border: OutlineInputBorder(),
              ),
              style: monoTextStyle(context, fontSize: 15),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 48,
              child: FilledButton(
                onPressed: _converting ? null : _convert,
                child: Text(_converting ? '转换中…' : '转换'),
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
                    if (result.cidr != null)
                      ToolResultRow(label: 'CIDR', value: result.cidr!),
                    if (result.netmask != null)
                      ToolResultRow(label: '子网掩码', value: result.netmask!),
                    if (prefix != null)
                      ToolResultRow(
                        label: '可用主机数',
                        value: '${_hostCount(prefix)}',
                      ),
                    if (result.decimal != null)
                      ToolResultRow(label: '十进制', value: result.decimal!),
                    if (result.hex != null)
                      ToolResultRow(label: '十六进制', value: result.hex!),
                    if (result.binary != null)
                      ToolResultRow(label: '二进制', value: result.binary!),
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
