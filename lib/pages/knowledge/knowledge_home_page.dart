import 'package:flutter/material.dart';

import '../../widgets/coming_soon_view.dart';

class KnowledgeHomePage extends StatelessWidget {
  const KnowledgeHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('知识库')),
      body: const ComingSoonView(
        title: '知识库',
        subtitle: 'V3 知识库模块即将上线',
      ),
    );
  }
}
