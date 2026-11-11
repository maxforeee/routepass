import 'package:flutter/material.dart';

import '../../widgets/coming_soon_view.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: const ComingSoonView(title: '设置', subtitle: 'V1 设置功能即将上线'),
    );
  }
}
