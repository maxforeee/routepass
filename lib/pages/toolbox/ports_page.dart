import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'toolbox_tools.dart';

/// 常用端口速查条目（静态本地内容）。
class _PortEntry {
  const _PortEntry({
    required this.port,
    required this.service,
    required this.desc,
  });

  final int port;
  final String service;
  final String desc;
}

const _ports = <_PortEntry>[
  _PortEntry(port: 20, service: 'FTP 数据', desc: 'FTP 数据传输'),
  _PortEntry(port: 21, service: 'FTP 控制', desc: 'FTP 控制连接'),
  _PortEntry(port: 22, service: 'SSH', desc: '安全远程登录'),
  _PortEntry(port: 23, service: 'Telnet', desc: '远程登录（明文）'),
  _PortEntry(port: 25, service: 'SMTP', desc: '发送邮件'),
  _PortEntry(port: 53, service: 'DNS', desc: '域名解析'),
  _PortEntry(port: 67, service: 'DHCP 服务器', desc: '分配 IP 地址'),
  _PortEntry(port: 68, service: 'DHCP 客户端', desc: '请求 IP 地址'),
  _PortEntry(port: 69, service: 'TFTP', desc: '简单文件传输'),
  _PortEntry(port: 80, service: 'HTTP', desc: '网页访问'),
  _PortEntry(port: 110, service: 'POP3', desc: '接收邮件'),
  _PortEntry(port: 123, service: 'NTP', desc: '时间同步'),
  _PortEntry(port: 143, service: 'IMAP', desc: '接收邮件'),
  _PortEntry(port: 161, service: 'SNMP', desc: '网络管理'),
  _PortEntry(port: 443, service: 'HTTPS', desc: '加密网页访问'),
  _PortEntry(port: 445, service: 'SMB', desc: '文件共享'),
  _PortEntry(port: 993, service: 'IMAPS', desc: '加密接收邮件'),
  _PortEntry(port: 995, service: 'POP3S', desc: '加密接收邮件'),
  _PortEntry(port: 1723, service: 'PPTP', desc: 'VPN 隧道'),
  _PortEntry(port: 3306, service: 'MySQL', desc: 'MySQL 数据库'),
  _PortEntry(port: 3389, service: 'RDP', desc: 'Windows 远程桌面'),
  _PortEntry(port: 5432, service: 'PostgreSQL', desc: 'PostgreSQL 数据库'),
  _PortEntry(port: 8080, service: 'HTTP 代理', desc: '备用网页端口'),
];

class PortsPage extends StatefulWidget {
  const PortsPage({super.key});

  @override
  State<PortsPage> createState() => _PortsPageState();
}

class _PortsPageState extends State<PortsPage> {
  String _query = '';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    recordRecentTool('ports');
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<_PortEntry> get _filtered {
    if (_query.isEmpty) return _ports;
    final q = _query.toLowerCase();
    return _ports.where((p) {
      return '${p.port}'.contains(q) ||
          p.service.toLowerCase().contains(q) ||
          p.desc.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Scaffold(
      appBar: AppBar(title: const Text('端口速查')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: '搜索端口号或服务，如 443',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
              ),
              onChanged: (v) => setState(() => _query = v.trim()),
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? const Center(child: Text('没有找到相关端口'))
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final entry = filtered[index];
                      return ListTile(
                        leading: SizedBox(
                          width: 56,
                          child: Text(
                            '${entry.port}',
                            style: monoTextStyle(context, fontSize: 15),
                          ),
                        ),
                        title: Text(entry.service),
                        subtitle: Text(entry.desc),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
