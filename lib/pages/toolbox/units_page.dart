import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'toolbox_tools.dart';

/// 单位换算（T-B6）：纯本地计算。速率 1000 进制，容量 1024 进制。
class UnitsPage extends StatefulWidget {
  const UnitsPage({super.key});

  @override
  State<UnitsPage> createState() => _UnitsPageState();
}

class _UnitsPageState extends State<UnitsPage> {
  final _valueController = TextEditingController();
  int _group = 0; // 0 = 速率，1 = 容量
  late String _from;
  late String _to;
  String? _result;
  String? _error;

  static const _rateUnits = ['bps', 'Kbps', 'Mbps', 'Gbps'];
  static const _rateFactors = <String, double>{
    'bps': 1,
    'Kbps': 1e3,
    'Mbps': 1e6,
    'Gbps': 1e9,
  };
  static const _sizeUnits = ['B', 'KB', 'MB', 'GB', 'TB'];
  static const _sizeFactors = <String, double>{
    'B': 1,
    'KB': 1024,
    'MB': 1048576,
    'GB': 1073741824,
    'TB': 1099511627776,
  };

  List<String> get _units => _group == 0 ? _rateUnits : _sizeUnits;
  Map<String, double> get _factors => _group == 0 ? _rateFactors : _sizeFactors;

  @override
  void initState() {
    super.initState();
    recordRecentTool('units');
    _from = 'Gbps';
    _to = 'Mbps';
  }

  @override
  void dispose() {
    _valueController.dispose();
    super.dispose();
  }

  void _switchGroup(int group) {
    setState(() {
      _group = group;
      if (group == 0) {
        _from = 'Gbps';
        _to = 'Mbps';
      } else {
        _from = 'GB';
        _to = 'MB';
      }
      _result = null;
      _error = null;
    });
  }

  void _convert() {
    final text = _valueController.text.trim();
    final value = double.tryParse(text);
    if (text.isEmpty) {
      setState(() {
        _error = '请输入数值';
        _result = null;
      });
      return;
    }
    if (value == null) {
      setState(() {
        _error = '请输入有效数字';
        _result = null;
      });
      return;
    }
    final converted = value * _factors[_from]! / _factors[_to]!;
    setState(() {
      _error = null;
      _result = '${_fmt(value)} $_from = ${_fmt(converted)} $_to';
    });
  }

  String _fmt(double v) {
    if (v == v.truncateToDouble()) return '${v.toInt()}';
    var s = v.toStringAsFixed(4);
    while (s.endsWith('0')) {
      s = s.substring(0, s.length - 1);
    }
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('单位换算')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('速率')),
                ButtonSegment(value: 1, label: Text('容量')),
              ],
              selected: {_group},
              onSelectionChanged: (s) => _switchGroup(s.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _valueController,
              decoration: const InputDecoration(
                labelText: '数值',
                hintText: '1',
                border: OutlineInputBorder(),
              ),
              style: monoTextStyle(context, fontSize: 15),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButton<String>(
                    value: _from,
                    isExpanded: true,
                    items: [
                      for (final u in _units)
                        DropdownMenuItem(value: u, child: Text(u)),
                    ],
                    onChanged: (v) => setState(() => _from = v ?? _from),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward),
                ),
                Expanded(
                  child: DropdownButton<String>(
                    value: _to,
                    isExpanded: true,
                    items: [
                      for (final u in _units)
                        DropdownMenuItem(value: u, child: Text(u)),
                    ],
                    onChanged: (v) => setState(() => _to = v ?? _to),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 48,
              child: FilledButton(onPressed: _convert, child: const Text('换算')),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            if (_result != null) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _result!,
                    style: monoTextStyle(context, fontSize: 15),
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
