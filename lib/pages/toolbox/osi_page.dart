import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'toolbox_tools.dart';

/// OSI 七层模型对照条目（静态本地内容）。
class _OsiLayer {
  const _OsiLayer({
    required this.level,
    required this.name,
    required this.protocols,
    required this.function,
  });

  final int level;
  final String name;
  final String protocols;
  final String function;
}

const _layers = <_OsiLayer>[
  _OsiLayer(
    level: 7,
    name: '应用层',
    protocols: 'HTTP、DNS、FTP、SMTP、POP3、DHCP',
    function: '为应用程序提供网络服务',
  ),
  _OsiLayer(
    level: 6,
    name: '表示层',
    protocols: 'SSL/TLS、JPEG、ASCII',
    function: '数据格式转换、加密解密',
  ),
  _OsiLayer(
    level: 5,
    name: '会话层',
    protocols: 'NetBIOS、RPC',
    function: '建立、管理、终止会话',
  ),
  _OsiLayer(
    level: 4,
    name: '传输层',
    protocols: 'TCP、UDP',
    function: '端到端传输、端口寻址',
  ),
  _OsiLayer(
    level: 3,
    name: '网络层',
    protocols: 'IP、ICMP、OSPF、BGP',
    function: '逻辑寻址、路由选择',
  ),
  _OsiLayer(
    level: 2,
    name: '数据链路层',
    protocols: 'Ethernet、ARP、PPP、VLAN',
    function: '成帧、MAC 寻址、差错检测',
  ),
  _OsiLayer(
    level: 1,
    name: '物理层',
    protocols: 'RS-232、RJ45、光纤',
    function: '比特流传输',
  ),
];

/// TCP/IP 四层到 OSI 的映射（静态本地内容）。
const _tcpipMapping = <(String, String)>[
  ('应用层', 'OSI 第 7 / 6 / 5 层'),
  ('传输层', 'OSI 第 4 层'),
  ('网际层', 'OSI 第 3 层'),
  ('网络接口层', 'OSI 第 2 / 1 层'),
];

class OsiPage extends StatefulWidget {
  const OsiPage({super.key});

  @override
  State<OsiPage> createState() => _OsiPageState();
}

class _OsiPageState extends State<OsiPage> {
  String _query = '';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    recordRecentTool('osi');
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<_OsiLayer> get _filtered {
    if (_query.isEmpty) return _layers;
    final q = _query.toLowerCase();
    return _layers.where((l) {
      return l.name.toLowerCase().contains(q) ||
          l.protocols.toLowerCase().contains(q) ||
          l.function.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _filtered;
    return Scaffold(
      appBar: AppBar(title: const Text('OSI/TCP-IP 对照')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              hintText: '搜索层名或协议，如 TCP',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
            ),
            onChanged: (v) => setState(() => _query = v.trim()),
          ),
          const SizedBox(height: 16),
          Text('OSI 七层模型', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (filtered.isEmpty)
            const Center(child: Text('没有找到相关内容'))
          else
            for (final layer in filtered)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '第 ${layer.level} 层 · ${layer.name}',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text('协议：${layer.protocols}'),
                      Text('功能：${layer.function}'),
                    ],
                  ),
                ),
              ),
          const SizedBox(height: 16),
          Text('TCP/IP 四层映射', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                for (final (name, osi) in _tcpipMapping)
                  ListTile(
                    title: Text(name),
                    subtitle: Text(osi, style: monoTextStyle(context, fontSize: 13)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
