/// 统一搜索条：知识库页与题库页共用（用户 2026-11-14 反馈：两页搜索框样式
/// 要一致）。高 44、圆角 22、浅灰填充、左侧放大镜、有内容时右侧清除按钮；
/// 输入即回调，提交回调由页面决定。
library;

import 'package:flutter/material.dart';

import '../core/theme.dart';

class AppSearchBar extends StatefulWidget {
  const AppSearchBar({
    super.key,
    required this.controller,
    required this.hintText,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<AppSearchBar> createState() => _AppSearchBarState();
}

class _AppSearchBarState extends State<AppSearchBar> {
  @override
  void initState() {
    super.initState();
    // 清除按钮的显隐跟随文本内容；页面自身的过滤状态仍由 onChanged 驱动。
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  void _clear() {
    widget.controller.clear();
    widget.onChanged?.call('');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SizedBox(
      height: AppSizes.searchBarHeight,
      child: TextField(
        controller: widget.controller,
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
        decoration: InputDecoration(
          hintText: widget.hintText,
          hintStyle: theme.textTheme.labelLarge?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
          prefixIcon: Icon(
            Icons.search,
            size: AppSizes.icon,
            color: scheme.onSurfaceVariant,
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: AppSizes.searchBarHeight,
            minHeight: AppSizes.searchBarHeight,
          ),
          suffixIcon: widget.controller.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear, size: AppSizes.icon),
                  onPressed: _clear,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: AppSizes.searchBarHeight,
                    minHeight: AppSizes.searchBarHeight,
                  ),
                ),
          isDense: true,
          filled: true,
          fillColor: scheme.surfaceContainerHighest,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadii.search),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        ),
      ),
    );
  }
}
