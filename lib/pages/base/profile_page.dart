import 'package:flutter/material.dart';

import '../../widgets/coming_soon_view.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('个人中心')),
      body: const ComingSoonView(
        title: '个人中心',
        subtitle: 'V1 账号功能即将上线',
      ),
    );
  }
}
