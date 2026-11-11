import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_snackbar.dart';
import '../../core/theme.dart';

/// 工具结果行：左标签 + 等宽值 + 右复制按钮（点按复制 + “已复制”提示）。
/// 子网计算器、IP/进制转换、CIDR↔掩码等页共用。
class ToolResultRow extends StatelessWidget {
  const ToolResultRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

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
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
              showAppSnackBar(context, '已复制');
            },
            tooltip: '复制',
          ),
        ],
      ),
    );
  }
}
