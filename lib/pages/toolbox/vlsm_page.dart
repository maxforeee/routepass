import 'package:flutter/material.dart';

import '../../core/service_locator.dart';
import '../../core/theme.dart';
import '../../models/toolbox.dart';
import 'toolbox_tools.dart';

class VlsmPage extends StatefulWidget {
  const VlsmPage({super.key});

  @override
  State<VlsmPage> createState() => _VlsmPageState();
}

class _VlsmPageState extends State<VlsmPage> {
  final _networkController = TextEditingController();
  final _hostsController = TextEditingController();
  VlsmPlan? _plan;
  String? _error;
  bool _planning = false;

  @override
  void initState() {
    super.initState();
    recordRecentTool('vlsm');
  }

  @override
  void dispose() {
    _networkController.dispose();
    _hostsController.dispose();
    super.dispose();
  }

  Future<void> _planSubnets() async {
    final network = _networkController.text.trim();
    final hostsText = _hostsController.text.trim();
    if (network.isEmpty || hostsText.isEmpty) {
      setState(() {
        _error = '请输入母网和主机数';
        _plan = null;
      });
      return;
    }
    final hostCounts = <int>[];
    for (final part in hostsText.split(',')) {
      final v = int.tryParse(part.trim());
      if (v == null || v <= 0) {
        setState(() {
          _error = '主机数格式错误，用逗号分隔数字';
          _plan = null;
        });
        return;
      }
      hostCounts.add(v);
    }
    setState(() {
      _planning = true;
      _error = null;
    });
    try {
      final plan = await ServiceLocator.subnetCalcService.planVlsm(
        network: network,
        hostCounts: hostCounts,
      );
      if (!mounted) return;
      setState(() => _plan = plan);
    } on FormatException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _plan = null;
      });
    } finally {
      if (mounted) setState(() => _planning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plan = _plan;
    return Scaffold(
      appBar: AppBar(title: const Text('VLSM 规划')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _networkController,
              decoration: const InputDecoration(
                labelText: '母网',
                hintText: '192.168.1.0/24',
                border: OutlineInputBorder(),
              ),
              style: monoTextStyle(context, fontSize: 15),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _hostsController,
              decoration: const InputDecoration(
                labelText: '主机数列表',
                hintText: '50, 20, 10',
                border: OutlineInputBorder(),
              ),
              style: monoTextStyle(context, fontSize: 15),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 48,
              child: FilledButton(
                onPressed: _planning ? null : _planSubnets,
                child: Text(_planning ? '规划中…' : '规划'),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            if (plan != null) ...[
              const SizedBox(height: 16),
              Text('母网 ${plan.network} 拆分结果', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final s in plan.subnets)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${s['name']}', style: theme.textTheme.titleMedium),
                        const SizedBox(height: 4),
                        Text(
                          '${s['network']}/${s['prefix']}',
                          style: monoTextStyle(context, fontSize: 14),
                        ),
                        const SizedBox(height: 4),
                        Text('掩码 ${s['mask']}'),
                        Text('可用主机 ${s['hosts']} 台'),
                        Text('范围 ${s['firstHost']} - ${s['lastHost']}'),
                        Text('广播 ${s['broadcast']}'),
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
