/// SubnetCalcService 的真实本地实现（规格文档第 4 章 §4.6.1，v3.1 第 16.1 节）。
///
/// 纯位运算，不走 Mock、不走服务器。VLSM 的 planVlsm 现在返回 null（“暂不支持”占位），
/// 以后在 Service 内补算法，页面不动。
library;

import '../../models/toolbox.dart';
import 'subnet_calc_service.dart';

class LocalSubnetCalcService implements SubnetCalcService {
  @override
  Future<SubnetResult> calculate({
    required String ip,
    required int prefix,
  }) async {
    final octets = _parseIp(ip);
    if (prefix < 0 || prefix > 32) {
      throw FormatException('prefix 超出范围：$prefix');
    }
    final int ipInt =
        (octets[0] << 24) | (octets[1] << 16) | (octets[2] << 8) | octets[3];
    final int mask = _mask(prefix);
    final int network = ipInt & mask;
    final int broadcast = network | (~mask & 0xFFFFFFFF);
    final int hostBits = 32 - prefix;
    final int hostCount;
    final int firstHost;
    final int lastHost;
    if (prefix == 32) {
      hostCount = 1;
      firstHost = network;
      lastHost = network;
    } else if (prefix == 31) {
      hostCount = 2;
      firstHost = network;
      lastHost = broadcast;
    } else {
      hostCount = (1 << hostBits) - 2;
      firstHost = network + 1;
      lastHost = broadcast - 1;
    }
    return SubnetResult(
      network: _dotted(network),
      broadcast: _dotted(broadcast),
      firstHost: _dotted(firstHost),
      lastHost: _dotted(lastHost),
      hostCount: hostCount,
      netmask: _dotted(mask),
      wildcard: _dotted(~mask & 0xFFFFFFFF),
      binaryNetwork: _binary(network),
      binaryNetmask: _binary(mask),
    );
  }

  @override
  Future<VlsmPlan?> planVlsm({
    required String network,
    required List<int> hostCounts,
  }) async {
    // VLSM 暂不支持占位：以后在 Service 内补算法，页面不动。
    return null;
  }

  List<int> _parseIp(String ip) {
    final parts = ip.trim().split('.');
    if (parts.length != 4) {
      throw FormatException('IP 格式错误：$ip');
    }
    return parts.map((p) {
      final v = int.tryParse(p);
      if (v == null || v < 0 || v > 255) {
        throw FormatException('IP 格式错误：$ip');
      }
      return v;
    }).toList();
  }

  int _mask(int prefix) {
    if (prefix == 0) return 0;
    return (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF;
  }

  String _dotted(int value) {
    return '${(value >> 24) & 0xFF}.${(value >> 16) & 0xFF}.${(value >> 8) & 0xFF}.${value & 0xFF}';
  }

  String _binary(int value) {
    final parts = <String>[];
    for (var i = 3; i >= 0; i--) {
      final octet = (value >> (i * 8)) & 0xFF;
      parts.add(octet.toRadixString(2).padLeft(8, '0'));
    }
    return parts.join('.');
  }
}
