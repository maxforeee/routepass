/// 底部胶囊导航（G-01，第 3 章 §22.2.2，R3b 按 mockup 调整外观）。
///
/// 白色背景、圆角约 999、阴影；4 等分：首页 house、题库 bookshelf、
/// 知识 open book、工具 wrench。未选中：灰图标 + 12px 灰字；选中：
/// 浅蓝椭圆底（primaryContainer）、深蓝图标、加粗文字。
///
/// F20：激活/失活动画按动画规范 v1.0 §2（Icon + Label Active/Inactive）
/// 绑定 AppDurations/AppDurations 曲线 token，见 [_CapsuleNavItemState]。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';

/// 胶囊底失活端 ScaleX（规范 §2：ScaleX 0.5 ↔ 1.0）。
const double _capsuleInactiveScaleX = 0.5;

/// 激活图标过冲峰值（规范 §2：Scale 1.0 → 1.15 → 1.0）。
const double _iconActiveOvershoot = 1.15;

/// 标签失活端透明度（规范 §2：Alpha 0.7 ↔ 1.0）。
const double _labelInactiveOpacity = 0.7;

class CapsuleNavBar extends StatelessWidget {
  const CapsuleNavBar({
    super.key,
    required this.currentIndex,
    required this.onSelect,
  });

  final int currentIndex;
  final void Function(int index) onSelect;

  static const List<({IconData icon, IconData selectedIcon, String label})>
  _destinations = [
    (icon: Icons.home_outlined, selectedIcon: Icons.home, label: '首页'),
    (
      icon: Icons.auto_stories_outlined,
      selectedIcon: Icons.auto_stories,
      label: '题库',
    ),
    (
      icon: Icons.menu_book_outlined,
      selectedIcon: Icons.menu_book,
      label: '知识',
    ),
    (icon: Icons.build_outlined, selectedIcon: Icons.build, label: '工具'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.sm + MediaQuery.of(context).padding.bottom,
      ),
      child: Container(
        height: AppSizes.navBarHeight,
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(AppRadii.navCapsule),
          boxShadow: [
            BoxShadow(
              offset: const Offset(0, AppSizes.navShadowOffsetY),
              blurRadius: AppSizes.navShadowBlur,
              color: AppColors.shadow,
            ),
          ],
        ),
        child: Row(
          children: [
            for (var i = 0; i < _destinations.length; i++)
              Expanded(
                child: _CapsuleNavItem(
                  destination: _destinations[i],
                  selected: i == currentIndex,
                  onTap: () {
                    if (i == currentIndex) return;
                    HapticFeedback.selectionClick();
                    onSelect(i);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CapsuleNavItem extends StatefulWidget {
  const _CapsuleNavItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final ({IconData icon, IconData selectedIcon, String label}) destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_CapsuleNavItem> createState() => _CapsuleNavItemState();
}

/// 激活/失活动画（动画规范 v1.0 §2 Icon + Label）：
/// 激活 M(200ms) + decelerate，失活 S(150ms) + accelerate。
/// 胶囊底 ScaleX 0.5 ↔ 1.0、Alpha 0 ↔ 1；标签 Alpha 0.7 ↔ 1.0、
/// TranslationY +2dp ↔ 0；图标仅激活时 1.0 → 1.15 → 1.0 过冲，
/// 失活时保持 1.0（用独立控制器，避免反向重放过冲）。
class _CapsuleNavItemState extends State<_CapsuleNavItem>
    with TickerProviderStateMixin {
  late final AnimationController _stateController;
  late final CurvedAnimation _state;
  late final AnimationController _iconController;
  late final CurvedAnimation _iconCurve;
  late final Animation<double> _iconScale;
  late final Animation<double> _labelOpacity;

  @override
  void initState() {
    super.initState();
    _stateController = AnimationController(
      vsync: this,
      duration: AppDurations.m,
      reverseDuration: AppDurations.s,
      value: widget.selected ? 1.0 : 0.0,
    );
    _state = CurvedAnimation(
      parent: _stateController,
      curve: AppDurations.enter,
      reverseCurve: AppDurations.exit,
    );
    _iconController = AnimationController(
      vsync: this,
      duration: AppDurations.m,
    );
    _iconCurve = CurvedAnimation(
      parent: _iconController,
      curve: AppDurations.enter,
    );
    _iconScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: _iconActiveOvershoot),
        weight: 1,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: _iconActiveOvershoot, end: 1.0),
        weight: 1,
      ),
    ]).animate(_iconCurve);
    _labelOpacity = Tween<double>(
      begin: _labelInactiveOpacity,
      end: 1.0,
    ).animate(_state);
  }

  @override
  void didUpdateWidget(_CapsuleNavItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected == widget.selected) return;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (widget.selected) {
      if (reduceMotion) {
        _stateController.value = 1.0;
        _iconController.value = 0.0;
      } else {
        _stateController.forward();
        _iconController.forward(from: 0.0);
      }
    } else {
      if (reduceMotion) {
        _stateController.value = 0.0;
      } else {
        _stateController.reverse();
      }
      // 失活图标不缩放：序列起点即 1.0，直接归位不重放过冲。
      _iconController.value = 0.0;
    }
  }

  @override
  void dispose() {
    _state.dispose();
    _iconCurve.dispose();
    _stateController.dispose();
    _iconController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selected = widget.selected;
    final destination = widget.destination;
    return Semantics(
      label: '${destination.label}${selected ? '，已选中' : ''}',
      selected: selected,
      button: true,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(AppRadii.navCapsule),
        child: SizedBox(
          height: AppSizes.navBarHeight,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  FadeTransition(
                    opacity: _state,
                    child: AnimatedBuilder(
                      animation: _state,
                      builder: (context, child) => Transform.scale(
                        scaleX:
                            _capsuleInactiveScaleX +
                            (1.0 - _capsuleInactiveScaleX) * _state.value,
                        child: child,
                      ),
                      child: Container(
                        width: AppSizes.navSelectedWidth,
                        height: AppSizes.navSelectedHeight,
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          borderRadius: BorderRadius.circular(AppRadii.card),
                        ),
                      ),
                    ),
                  ),
                  ScaleTransition(
                    scale: _iconScale,
                    child: Icon(
                      selected ? destination.selectedIcon : destination.icon,
                      size: AppSizes.iconLarge,
                      color: selected
                          ? scheme.onPrimaryContainer
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxxs),
              AnimatedBuilder(
                animation: _state,
                builder: (context, child) => Transform.translate(
                  offset: Offset(0, AppSpacing.xxxs * (1.0 - _state.value)),
                  child: child,
                ),
                child: FadeTransition(
                  opacity: _labelOpacity,
                  child: Text(
                    destination.label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: selected
                          ? scheme.onSurface
                          : scheme.onSurfaceVariant,
                      fontWeight: selected
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
