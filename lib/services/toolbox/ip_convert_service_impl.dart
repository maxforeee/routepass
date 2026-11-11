/// IpConvertService 的真实本地实现（规格文档第 4 章 §4.6.2）。
///
/// 纯本地计算，永不走服务器。识别顺序：纯前缀（/24）→ 地址/前缀（192.168.1.0/24）→
/// 点分十进制（IP 或掩码）→ 纯十进制整数；无法识别时各字段留 null。
library;

import '../../models/toolbox.dart';
import 'ip_convert_service.dart';

class LocalIpConvertService implements IpConvertService {
  @override
  Future<IpConvertResult> convert(String input) async {
    final text = input.trim();
    // 1) 纯前缀，如 /24。
    if (text.startsWith('/')) {
      final prefix = int.tryParse(text.substring(1));
      if (prefix != null && prefix >= 0 && prefix <= 32) {
        return IpConvertResult(
          input: input,
          cidr: '/$prefix',
          netmask: _dotted(_mask(prefix)),
        );
      }
      return IpConvertResult(input: input);
    }
    // 2) 带 / 前缀的地址，如 192.168.1.0/24。
    if (text.contains('/')) {
      final parts = text.split('/');
      if (parts.length == 2) {
        final prefix = int.tryParse(parts[1].trim());
        final octets = _tryParseIp(parts[0].trim());
        if (prefix != null && prefix >= 0 && prefix <= 32 && octets != null) {
          final ipInt = _toInt(octets);
          return IpConvertResult(
            input: input,
            decimal: '$ipInt',
            hex: _hex(ipInt),
            binary: _binary(ipInt),
            cidr: '/$prefix',
            netmask: _dotted(_mask(prefix)),
          );
        }
      }
      return IpConvertResult(input: input);
    }
    // 3) 点分十进制 IP 或掩码。
    final octets = _tryParseIp(text);
    if (octets != null) {
      final ipInt = _toInt(octets);
      final prefix = _maskToPrefix(ipInt);
      return IpConvertResult(
        input: input,
        decimal: '$ipInt',
        hex: _hex(ipInt),
        binary: _binary(ipInt),
        cidr: prefix == null ? null : '/$prefix',
        netmask: prefix == null ? null : _dotted(ipInt),
      );
    }
    // 4) 纯十进制整数。
    final asInt = int.tryParse(text);
    if (asInt != null && asInt >= 0 && asInt <= 0xFFFFFFFF) {
      return IpConvertResult(
        input: input,
        decimal: '$asInt',
        hex: _hex(asInt),
        binary: _binary(asInt),
      );
    }
    // 无法识别：各字段留 null。
    return IpConvertResult(input: input);
  }

  List<int>? _tryParseIp(String text) {
    final parts = text.split('.');
    if (parts.length != 4) return null;
    final octets = <int>[];
    for (final p in parts) {
      final v = int.tryParse(p);
      if (v == null || v < 0 || v > 255) return null;
      octets.add(v);
    }
    return octets;
  }

  int _toInt(List<int> octets) {
    return (octets[0] << 24) |
        (octets[1] << 16) |
        (octets[2] << 8) |
        octets[3];
  }

  int _mask(int prefix) {
    if (prefix == 0) return 0;
    return (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF;
  }

  /// 掩码形状（前 1 后 0）时返回前缀长度，否则返回 null。
  int? _maskToPrefix(int value) {
    for (var p = 0; p <= 32; p++) {
      if (value == _mask(p)) return p;
    }
    return null;
  }

  String _dotted(int value) {
    return '${(value >> 24) & 0xFF}.${(value >> 16) & 0xFF}.${(value >> 8) & 0xFF}.${value & 0xFF}';
  }

  String _hex(int value) {
    return '0x${value.toRadixString(16).toUpperCase().padLeft(8, '0')}';
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
