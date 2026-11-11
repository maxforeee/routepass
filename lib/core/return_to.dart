/// V2↔V3 跳转 returnTo 约定（第 3 章 §22.2.4）。
///
/// 跨模块用 root Navigator.push，不切 tab 高亮；返回时 pop 到原点，
/// 恢复题号 / 滚动位置 / 已选答案（恢复作答现场是答题页的职责，
/// 本文件只负责携带约定数据）。
library;

import 'package:flutter/material.dart';

/// 跳转 payload：{tab, route, anchor: {sessionId, qIndex, scrollOffset, selectedOptions}}。
class ReturnTo {
  const ReturnTo({
    required this.tab,
    required this.route,
    this.sessionId,
    this.qIndex,
    this.scrollOffset,
    this.selectedOptions,
  });

  /// 来源 tab：'quiz' | 'knowledge' | 'home' | 'toolbox'。
  final String tab;

  /// 来源路由，如 '/bank/quiz'。
  final String route;

  /// 作答现场锚点。
  final String? sessionId;
  final int? qIndex;
  final double? scrollOffset;
  final List<String>? selectedOptions;

  Map<String, dynamic> toArgs() {
    return <String, dynamic>{
      'tab': tab,
      'route': route,
      if (sessionId != null) 'sessionId': sessionId,
      if (qIndex != null) 'qIndex': qIndex,
      if (scrollOffset != null) 'scrollOffset': scrollOffset,
      if (selectedOptions != null) 'selectedOptions': selectedOptions,
    };
  }

  static ReturnTo? fromArgs(Object? args) {
    if (args is! Map<String, dynamic>) return null;
    final raw = args['returnTo'];
    if (raw is! Map<String, dynamic>) return null;
    return ReturnTo(
      tab: raw['tab'] as String? ?? 'home',
      route: raw['route'] as String? ?? '/home',
      sessionId: raw['sessionId'] as String?,
      qIndex: raw['qIndex'] as int?,
      scrollOffset: (raw['scrollOffset'] as num?)?.toDouble(),
      selectedOptions: (raw['selectedOptions'] as List<dynamic>?)
          ?.cast<String>(),
    );
  }
}

/// 返回键文案随来源：返回作答 / 返回首页 / 返回知识库（§22.2.4）。
String backLabelFor(ReturnTo? returnTo) {
  return switch (returnTo?.tab) {
    'quiz' => '返回作答',
    'knowledge' => '返回知识库',
    'toolbox' => '返回工具箱',
    _ => '返回首页',
  };
}

/// 跨模块跳转：用 root Navigator.push，不切 tab 高亮。
Future<T?> pushCrossModule<T extends Object?>(
  BuildContext context,
  String route, {
  required ReturnTo returnTo,
  Map<String, dynamic>? extraArgs,
}) {
  return Navigator.of(context, rootNavigator: true).pushNamed<T>(
    route,
    arguments: <String, dynamic>{
      'returnTo': returnTo.toArgs(),
      ...?extraArgs,
    },
  );
}
