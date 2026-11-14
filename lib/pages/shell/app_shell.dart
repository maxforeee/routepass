/// 全局外壳（规格文档第 3 章 §22.2，G-01/G-02）。
///
/// 4 个目的地各走独立 Navigator + 保栈；底栏按 §22.2.3 显示/隐藏；
/// 键盘弹起时隐藏；ui.lastTab 存 KvStore 下次启动恢复。
/// 模块未装配时（Flags 全为 false），对应 tab 显示“暂未开放”占位，点按不进路由。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/flags.dart';
import '../../core/kv_store.dart';
import '../../core/page_transition.dart';
import '../../core/service_locator.dart';
import '../../core/theme.dart';
import '../../router/app_router.dart';
import '../../widgets/capsule_nav_bar.dart';
import '../../widgets/coming_soon_view.dart';
import '../../widgets/version_banner.dart';
import '../bank/answer_page.dart';
import '../bank/favorites_page.dart';
import '../bank/module_list_page.dart';
import '../bank/quiz_page.dart';
import '../bank/set_detail_page.dart';
import '../bank/stats_page.dart';
import '../bank/wrong_page.dart';
import '../home/home_content.dart';
import '../knowledge/knowledge_detail_page.dart';
import '../knowledge/knowledge_home_page.dart';
import '../knowledge/knowledge_search_page.dart';
import '../toolbox/cidr_page.dart';
import '../toolbox/cli_page.dart';
import '../toolbox/ip_convert_page.dart';
import '../toolbox/osi_page.dart';
import '../toolbox/ping_page.dart';
import '../toolbox/ports_page.dart';
import '../toolbox/portscan_page.dart';
import '../toolbox/subnet_page.dart';
import '../toolbox/toolbox_home_page.dart';
import '../toolbox/units_page.dart';
import '../toolbox/vlsm_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, this.initialTab});

  /// 可选初始 tab 下标（0–3）。登录页“先看看知识库 / 打开工具箱”等入口
  /// 指定后优先于 kv `ui.lastTab` 恢复。
  final int? initialTab;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const List<String> _tabNames = <String>[
    'home',
    'quiz',
    'knowledge',
    'toolbox',
  ];

  final List<GlobalKey<NavigatorState>> _navigatorKeys =
      List<GlobalKey<NavigatorState>>.generate(
        4,
        (_) => GlobalKey<NavigatorState>(),
      );

  /// 三个 tab 首页的状态 key（tab 切回时调 refresh）。
  final GlobalKey<HomeContentPageState> _homeKey =
      GlobalKey<HomeContentPageState>();
  final GlobalKey<BankModuleListPageState> _bankKey =
      GlobalKey<BankModuleListPageState>();
  final GlobalKey<ToolboxHomePageState> _toolboxKey =
      GlobalKey<ToolboxHomePageState>();

  int _currentIndex = 0;
  bool _navVisible = true;
  double _tabOpacity = 1.0;

  @override
  void initState() {
    super.initState();
    final initialTab = widget.initialTab;
    if (initialTab != null &&
        initialTab >= 0 &&
        initialTab < _tabNames.length) {
      _currentIndex = initialTab;
      return;
    }
    final lastTab = ServiceLocator.kvStore.getString(KvStore.keyUiLastTab);
    final index = _tabNames.indexOf(lastTab ?? '');
    if (index >= 0) _currentIndex = index;
  }

  String _initialRouteFor(int index) {
    return switch (index) {
      0 => AppRoutes.home,
      1 => AppRoutes.bankModules,
      2 => AppRoutes.knowledge,
      _ => AppRoutes.toolbox,
    };
  }

  bool _moduleReady(int index) {
    return switch (index) {
      1 => Flags.MODULE_BANK,
      2 => Flags.MODULE_KNOWLEDGE,
      3 => Flags.MODULE_TOOLBOX,
      _ => true,
    };
  }

  void _selectTab(int index) {
    // 切 tab / 回栈底时收起键盘：IndexedStack 保栈，被隐藏页面上的搜索框
    // 不会自己失焦，切回来会带着焦点和键盘（用户 2026-11-14 反馈）。
    FocusManager.instance.primaryFocus?.unfocus();
    if (index == _currentIndex) {
      // 点当前 tab：回到该 tab 栈底。
      _navigatorKeys[index].currentState?.popUntil((route) => route.isFirst);
      _refreshTab(index);
      return;
    }
    HapticFeedback.selectionClick();
    setState(() {
      _currentIndex = index;
      _navVisible = true;
      // tab 切换淡入淡出（200ms）：IndexedStack 本身不换 key（保栈），
      // 只做透明度起伏。减少动效时直接切，不做动画。
      _tabOpacity = MediaQuery.of(context).disableAnimations ? 1.0 : 0.0;
    });
    if (!MediaQuery.of(context).disableAnimations) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _tabOpacity = 1.0);
      });
    }
    ServiceLocator.kvStore.setString(KvStore.keyUiLastTab, _tabNames[index]);
    _refreshTab(index);
  }

  /// tab 切回时让新 tab 刷新（首页/题库重拉，工具箱重读最近使用）。
  void _refreshTab(int index) {
    switch (index) {
      case 0:
        _homeKey.currentState?.refresh();
      case 1:
        _bankKey.currentState?.refresh();
      case 3:
        _toolboxKey.currentState?.refresh();
    }
  }

  void _onTabRouteChanged(Route<dynamic>? route) {
    final shouldShow = !_shouldHideNav(route);
    if (shouldShow == _navVisible) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _navVisible = shouldShow);
    });
  }

  /// 按第 3 章 §22.2.3：作答页、交卷结果、工具全屏 sheet 隐藏底栏，其余显示。
  /// 套卷详情页是做题前置页，同属做题流程（v0.2.3 Q1），一并隐藏。
  /// 知识详情页按 v0.2.4 用户反馈也隐藏底栏（覆盖文档“显示底栏”的旧规则）。
  /// 任意 PopupRoute（底部账户面板 / 弹窗）打开时同样隐藏，避免面板被胶囊挡住。
  bool _shouldHideNav(Route<dynamic>? route) {
    if (route is PopupRoute) return true;
    return switch (route?.settings.name) {
      AppRoutes.bankSetDetail ||
      AppRoutes.bankQuiz ||
      AppRoutes.bankAnswer ||
      AppRoutes.bankExam ||
      AppRoutes.bankExamResult ||
      AppRoutes.knowledgePoint ||
      AppRoutes.toolboxSubnet ||
      AppRoutes.toolboxIpConvert ||
      AppRoutes.toolboxCidr ||
      AppRoutes.toolboxVlsm ||
      AppRoutes.toolboxUnits ||
      AppRoutes.toolboxOsi ||
      AppRoutes.toolboxPorts ||
      AppRoutes.toolboxPing ||
      AppRoutes.toolboxPortscan ||
      AppRoutes.toolboxCli => true,
      _ => false,
    };
  }

  /// 返回键：先 pop 当前 tab 的栈；tab 已在栈底且不在首页时回首页；
  /// 已在首页栈底时返回 true（由调用方退出 App）。
  Future<bool> _handleBack() async {
    final nav = _navigatorKeys[_currentIndex].currentState;
    if (nav != null && nav.canPop()) {
      nav.pop();
      return false;
    }
    if (_currentIndex != 0) {
      _selectTab(0);
      return false;
    }
    return true;
  }

  Widget _buildTab(int index) {
    if (!_moduleReady(index)) {
      return _comingSoonFor(index);
    }
    return Navigator(
      key: _navigatorKeys[index],
      initialRoute: _initialRouteFor(index),
      onGenerateRoute: (settings) => _tabRoute(index, settings),
      observers: <NavigatorObserver>[_TabObserver(_onTabRouteChanged)],
    );
  }

  Widget _comingSoonFor(int index) {
    return switch (index) {
      1 => const Scaffold(
        body: ComingSoonView(title: '题库', subtitle: 'V2 题库模块暂未开放'),
      ),
      2 => const Scaffold(
        body: ComingSoonView(title: '知识库', subtitle: 'V3 知识库模块暂未开放'),
      ),
      _ => const Scaffold(
        body: ComingSoonView(title: '工具箱', subtitle: 'V4 工具箱模块暂未开放'),
      ),
    };
  }

  /// 从 RouteSettings.arguments 取 AnswerPage 的 `Map<String, Object?>` 参数；没有或类型不对返回空 Map。
  Map<String, Object?> _routeArgs(RouteSettings settings) {
    final args = settings.arguments;
    if (args is Map<String, Object?>) return args;
    return const <String, Object?>{};
  }

  Route<void>? _tabRoute(int index, RouteSettings settings) {
    final Widget page;
    switch (settings.name) {
      case AppRoutes.home:
        page = HomeContentPage(
          key: index == 0 ? _homeKey : null,
          onSelectTab: _selectTab,
        );
      case AppRoutes.bankModules:
        page = BankModuleListPage(key: index == 1 ? _bankKey : null);
      case AppRoutes.bankQuiz:
        page = AnswerPage(args: _routeArgs(settings));
      case AppRoutes.bankAnswer:
        page = QuizPage(args: _routeArgs(settings));
      case AppRoutes.bankSetDetail:
        page = SetDetailPage(args: _routeArgs(settings));
      case AppRoutes.bankExam:
        page = AnswerPage(args: _routeArgs(settings));
      case AppRoutes.bankDaily:
        page = AnswerPage(
          args: <String, Object?>{
            'mode': 'daily',
            'drawCount': 10,
            ..._routeArgs(settings),
          },
        );
      case AppRoutes.bankWrong:
        page = const WrongPage();
      case AppRoutes.bankFavorites:
        page = const FavoritesPage();
      case AppRoutes.bankStats:
        page = const StatsPage();
      case AppRoutes.knowledge:
        page = const KnowledgeHomePage();
      case AppRoutes.knowledgeList:
        page = const KnowledgeHomePage();
      case AppRoutes.knowledgePoint:
        page = KnowledgeDetailPage(args: _routeArgs(settings));
      case AppRoutes.knowledgeSearch:
        page = KnowledgeSearchPage(args: _routeArgs(settings));
      case AppRoutes.toolbox:
        page = ToolboxHomePage(key: index == 3 ? _toolboxKey : null);
      case AppRoutes.toolboxSubnet:
        page = const SubnetPage();
      case AppRoutes.toolboxIpConvert:
        page = const IpConvertPage();
      case AppRoutes.toolboxCidr:
        page = const CidrPage();
      case AppRoutes.toolboxVlsm:
        page = const VlsmPage();
      case AppRoutes.toolboxUnits:
        page = const UnitsPage();
      case AppRoutes.toolboxOsi:
        page = const OsiPage();
      case AppRoutes.toolboxPorts:
        page = const PortsPage();
      case AppRoutes.toolboxPing:
        page = const PingPage();
      case AppRoutes.toolboxPortscan:
        page = const PortScanPage();
      case AppRoutes.toolboxCli:
        page = const CliPage();
      default:
        page = _tabHome(index);
    }
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return SharedAxisPageRoute<void>(
      builder: (_) => page,
      settings: settings,
      transitionDuration: reduceMotion ? Duration.zero : AppDurations.xl,
      reverseTransitionDuration: reduceMotion ? Duration.zero : AppDurations.l,
    );
  }

  Widget _tabHome(int index) {
    return switch (index) {
      0 => HomeContentPage(onSelectTab: _selectTab),
      1 => const BankModuleListPage(),
      2 => const KnowledgeHomePage(),
      _ => const ToolboxHomePage(),
    };
  }

  @override
  Widget build(BuildContext context) {
    // 键盘弹起时隐藏底栏（§22.2.3）。
    final keyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;
    final showNav = _navVisible && !keyboardVisible;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldExit = await _handleBack();
        if (shouldExit && context.mounted) {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        extendBody: true,
        body: Stack(
          children: [
            Column(
              children: [
                const VersionBanner(),
                Expanded(
                  child: AnimatedOpacity(
                    opacity: _tabOpacity,
                    duration: reduceMotion ? Duration.zero : AppDurations.m,
                    curve: AppDurations.standard,
                    child: IndexedStack(
                      index: _currentIndex,
                      children: [
                        _buildTab(0),
                        _buildTab(1),
                        _buildTab(2),
                        _buildTab(3),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Positioned(
              left: 0,
              right: 0,
              // 上移 8px（v0.2.4 用户反馈）。
              bottom: AppSpacing.xs,
              child: _NavBarVisibility(
                visible: showNav,
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: AppSizes.navBarMaxWidth,
                    ),
                    child: CapsuleNavBar(
                      currentIndex: _currentIndex,
                      onSelect: _selectTab,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 底栏显隐动画（动画规范 v1.0 §2 Bar Exit / Bar Enter，F20）：
/// 隐藏（push 子页 / 键盘弹起）S(150ms) + accelerate，向下滑出自身高度
/// 100% 并淡出；重现（pop 回主页）M(200ms) + decelerate，向上滑入并淡入。
/// 退出动画播完后把底栏移出树，保持“隐藏时树中无胶囊”的旧行为；
/// 与 §1 页面转场并行，互不干预。
class _NavBarVisibility extends StatefulWidget {
  const _NavBarVisibility({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  State<_NavBarVisibility> createState() => _NavBarVisibilityState();
}

class _NavBarVisibilityState extends State<_NavBarVisibility>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _animation;
  late bool _showing;

  @override
  void initState() {
    super.initState();
    _showing = widget.visible;
    _controller = AnimationController(
      vsync: this,
      duration: AppDurations.m,
      reverseDuration: AppDurations.s,
      value: widget.visible ? 1.0 : 0.0,
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: AppDurations.enter,
      reverseCurve: AppDurations.exit,
    );
  }

  @override
  void didUpdateWidget(_NavBarVisibility oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible == widget.visible) return;
    if (MediaQuery.of(context).disableAnimations) {
      _controller.value = widget.visible ? 1.0 : 0.0;
      setState(() => _showing = widget.visible);
      return;
    }
    if (widget.visible) {
      setState(() => _showing = true);
      _controller.forward();
    } else {
      // reverse 被打断（重新显示）时 then 不触发，底栏留在树中。
      _controller.reverse().then((_) {
        if (mounted && !widget.visible) {
          setState(() => _showing = false);
        }
      });
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_showing) return const SizedBox.shrink();
    return IgnorePointer(
      ignoring: !widget.visible,
      child: FadeTransition(
        opacity: _animation,
        child: AnimatedBuilder(
          animation: _animation,
          builder: (context, child) => FractionalTranslation(
            translation: Offset(0, 1.0 - _animation.value),
            child: child,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

/// 监听 tab 内路由变化，回报告诉外壳更新底栏显隐。
class _TabObserver extends NavigatorObserver {
  _TabObserver(this.onRouteChanged);

  final void Function(Route<dynamic>? route) onRouteChanged;

  /// 收起键盘：主页面搜索框被点过后一直持有焦点，打开子页时若不主动放弃，
  /// 返回时 Flutter 的路由焦点恢复会把焦点还给它、键盘自动弹出（用户
  /// 2026-11-14 反馈）。push 时立即失焦，返回时就没有可恢复的焦点。
  void _unfocus() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) _unfocus();
    onRouteChanged(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // 返回的这一帧焦点可能刚被恢复，帧后再兜一次底。
    WidgetsBinding.instance.addPostFrameCallback((_) => _unfocus());
    onRouteChanged(previousRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    onRouteChanged(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    onRouteChanged(newRoute);
  }
}
