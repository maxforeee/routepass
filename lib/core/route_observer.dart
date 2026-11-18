import 'package:flutter/material.dart';

/// F33：答题页「被盖住暂停 / 重新露出续计」用的路由观察者。
///
/// 一个 [NavigatorObserver] 同一时刻只能挂在一个 Navigator 上（框架挂载时
/// 断言 `observer.navigator == null`），所以每个 Navigator 必须各持一个
/// 实例：外壳为每个 tab 的内层 Navigator 各建一个（app_shell），答题页从
/// 自己所在 Navigator 的 observers 列表里解析出实例再订阅（quiz_page）。
///
/// 这个全局实例只供单 Navigator 的测试宿主使用（f33 测试把它注册进自己的
/// MaterialApp）；应用代码绝不可把同一个实例共享给多个 Navigator。
final RouteObserver<PageRoute<dynamic>> appRouteObserver =
    RouteObserver<PageRoute<dynamic>>();
