import 'package:flutter/material.dart';

import '../../widgets/coming_soon_view.dart';

class ToolboxHomePage extends StatelessWidget {
  const ToolboxHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('工具箱')),
      body: const ComingSoonView(
        title: '工具箱',
        subtitle: 'V4 工具箱模块即将上线',
      ),
    );
  }
}
