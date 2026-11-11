/// 全局 Snackbar（G-04，第 3 章 §22.2.2）。
///
/// 高 48、圆角 12、inverseSurface、4 秒自动消失、可带 1 个动作、底栏上 16。
library;

import 'package:flutter/material.dart';

void showAppSnackBar(
  BuildContext context,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
  bool aboveNav = true,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.fromLTRB(16, 0, 16, aboveNav ? 92 : 16),
        action: actionLabel == null
            ? null
            : SnackBarAction(label: actionLabel, onPressed: onAction ?? () {}),
      ),
    );
}
