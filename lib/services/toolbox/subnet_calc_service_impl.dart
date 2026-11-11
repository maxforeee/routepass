/// SubnetCalcService 的真实本地实现（规格文档第 4 章 §4.6.1，v3.1 第 16.1 节）。
///
/// 纯位运算，不走 Mock、不走服务器。VLSM 的 planVlsm 已按真实算法实现（T6a）。
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
    // VLSM 真实实现：按需求主机数从大到小排序，依次从母网顺序分配最小满足块。
    // 每块取满足 hosts 台可用主机的最小前缀（加网络地址与广播地址共 hosts + 2 个地址）。
    final parts = network.trim().split('/');
    if (parts.length != 2) {
      throw FormatException('母网格式错误：$network（应为 192.168.1.0/24）');
    }
    final baseOctets = _parseIp(parts[0]);
    final parentPrefix = int.tryParse(parts[1].trim());
    if (parentPrefix == null || parentPrefix < 0 || parentPrefix > 32) {
      throw FormatException('母网前缀错误：$network');
    }
    final needs = hostCounts.where((h) => h > 0).toList()
      ..sort((a, b) => b.compareTo(a));
    if (needs.isEmpty) {
      throw FormatException('主机数列表为空');
    }
    final int base = _toInt(baseOctets) & _mask(parentPrefix);
    final int parentSize = 1 << (32 - parentPrefix);
    var cursor = base;
    final subnets = <Map<String, dynamic>>[];
    for (var i = 0; i < needs.length; i++) {
      final hosts = needs[i];
      final needed = hosts + 2;
      var bits = 0;
      while ((1 << bits) < needed) {
        bits++;
      }
      final prefix = 32 - bits;
      if (prefix < parentPrefix) {
        throw FormatException(
          '需求超出母网容量：$hosts 台主机需要 /$prefix，母网为 /$parentPrefix',
        );
      }
      final size = 1 << bits;
      if (cursor + size > base + parentSize) {
        throw FormatException('需求超出母网容量：剩余地址不足');
      }
      final broadcast = cursor + size - 1;
      final firstHost = prefix == 32 ? cursor : cursor + 1;
      final lastHost = prefix == 32 ? cursor : broadcast - 1;
      final usable = prefix == 32 ? 1 : (prefix == 31 ? 2 : size - 2);
      subnets.add(<String, dynamic>{
        'name': '子网${i + 1}',
        'network': _dotted(cursor),
        'prefix': prefix,
        'mask': _dotted(_mask(prefix)),
        'hosts': usable,
        'firstHost': _dotted(firstHost),
        'lastHost': _dotted(lastHost),
        'broadcast': _dotted(broadcast),
      });
      cursor += size;
    }
    return VlsmPlan(
      network: '${_dotted(base)}/$parentPrefix',
      subnets: subnets,
    );
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

  int _toInt(List<int> octets) {
    return (octets[0] << 24) | (octets[1] << 16) | (octets[2] << 8) | octets[3];
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
