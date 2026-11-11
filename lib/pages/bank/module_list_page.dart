import 'package:flutter/material.dart';

import '../../widgets/coming_soon_view.dart';

class BankModuleListPage extends StatelessWidget {
  const BankModuleListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('题库')),
      body: const ComingSoonView(
        title: '题库',
        subtitle: 'V2 题库模块即将上线',
      ),
    );
  }
}
