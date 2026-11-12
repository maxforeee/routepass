/// 底部胶囊导航（G-01，第 3 章 §22.2.2，R3b 按 mockup 调整外观）。
///
/// 白色背景、圆角约 999、阴影；4 等分：首页 house、题库 bookshelf、
/// 知识 open book、工具 wrench。未选中：灰图标 + 12px 灰字；选中：
/// 浅蓝椭圆底（primaryContainer）、深蓝图标、加粗文字。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';

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

class _CapsuleNavItem extends StatelessWidget {
  const _CapsuleNavItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final ({IconData icon, IconData selectedIcon, String label}) destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      label: '${destination.label}${selected ? '，已选中' : ''}',
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.navCapsule),
        child: SizedBox(
          height: AppSizes.navBarHeight,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedContainer(
                    duration: AppDurations.navFade,
                    width: selected ? AppSizes.navSelectedWidth : 0,
                    height: AppSizes.navSelectedHeight,
                    decoration: BoxDecoration(
                      color: selected
                          ? scheme.primaryContainer
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(AppRadii.card),
                    ),
                  ),
                  Icon(
                    selected ? destination.selectedIcon : destination.icon,
                    size: AppSizes.iconLarge,
                    color: selected
                        ? scheme.onPrimaryContainer
                        : scheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxxs),
              Text(
                destination.label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
