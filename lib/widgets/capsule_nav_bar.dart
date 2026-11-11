/// 底部胶囊导航（G-01，第 3 章 §22.2.2）。
///
/// 高 64；左右外距 16；底距 12 + safe；圆角 32；BackdropFilter blur 18；
/// 背景 light surface@72% / dark surface@62%；描边 1dp outlineVariant@40%；
/// 阴影 0 8 24 #000@8%；4 等分，单项热区 ≥48；图标 24；标签 11sp；
/// 选中 pill 56×32 圆角 16 primaryContainer。切 tab 时给 selectionClick 触感反馈。
///
/// 注意：低性能设备回退静态表面（不用磨砂）的分支本次未做——没有设备性能
/// 信号来源；磨砂只用于导航胶囊这一小面积，后续有信号来源时再补。
library;

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    (icon: Icons.quiz_outlined, selectedIcon: Icons.quiz, label: '题库'),
    (
      icon: Icons.menu_book_outlined,
      selectedIcon: Icons.menu_book,
      label: '知识库',
    ),
    (icon: Icons.build_outlined, selectedIcon: Icons.build, label: '工具箱'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            height: 64,
            decoration: BoxDecoration(
              color: scheme.surface.withValues(alpha: isDark ? 0.62 : 0.72),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.4),
              ),
              boxShadow: [
                BoxShadow(
                  offset: const Offset(0, 8),
                  blurRadius: 24,
                  color: Colors.black.withValues(alpha: 0.08),
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
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: '${destination.label}${selected ? '，已选中' : ''}',
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(32),
        child: SizedBox(
          height: 64,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: selected ? 56 : 0,
                    height: 32,
                    decoration: BoxDecoration(
                      color: selected
                          ? scheme.primaryContainer
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  Icon(
                    selected ? destination.selectedIcon : destination.icon,
                    size: 24,
                    color: selected
                        ? scheme.onPrimaryContainer
                        : scheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                destination.label,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.4,
                  color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
