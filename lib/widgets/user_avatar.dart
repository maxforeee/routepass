import 'package:flutter/material.dart';

import '../core/theme.dart';

/// 用户头像：蓝色圆底 + 用户名首字母，点按触发 [onTap]（打开账户 sheet）。
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.username,
    this.radius = AppSizes.avatarRadius,
    this.onTap,
  });

  /// 登录用户名；取其首字母显示。
  final String username;

  /// 圆形头像半径（逻辑像素）。
  final double radius;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = username.isEmpty
        ? '?'
        : username.substring(0, 1).toUpperCase();
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: CircleAvatar(
        radius: radius,
        backgroundColor: theme.colorScheme.primary,
        child: Text(
          initial,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.onPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
