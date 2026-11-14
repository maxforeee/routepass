/// 统一搜索条：知识库页与题库页共用（用户 2026-11-14 反馈：两页搜索框样式
/// 要一致）。高 44、圆角 22、浅灰填充、左侧放大镜、有内容时右侧清除按钮；
/// 输入即回调，提交回调由页面决定。
///
/// F20 动画规范 §4：点击放大镜或输入框获焦即展开（容器 ScaleX 0.85 → 1.0，
/// 250ms），失焦且文本清空即收起（200ms）；建议层随展开淡入并上移 12dp。
/// §5：放大镜与清除按钮按压缩到 0.92、释放回 1.0。
/// §6：获焦底部指示线 ScaleX 0 → 1（200ms）、失焦收回（150ms）；清除按钮
/// 随文本非空淡入放大出现、清空时淡出缩小收起（均 150ms）。本输入用 hint
/// 而非 label，无标签可浮；TextField 自带标签浮动（SDK 固定 167ms）无 token
/// 绑定入口，按规范说明不重建 TextField。
library;

import 'package:flutter/material.dart';

import '../core/app_animations.dart';
import '../core/theme.dart';

class AppSearchBar extends StatefulWidget {
  const AppSearchBar({
    super.key,
    required this.controller,
    required this.hintText,
    this.onChanged,
    this.onSubmitted,
    this.suggestions,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// 搜索建议层（规范 §4）：展开时 Alpha 0 → 1、TranslationY -12dp → 0，
  /// 收起时反向；为 null 时不占位，搜索条仍是单行 44 高。
  final Widget? suggestions;

  @override
  State<AppSearchBar> createState() => _AppSearchBarState();
}

class _AppSearchBarState extends State<AppSearchBar> {
  final FocusNode _focusNode = FocusNode();

  /// 规范 §6：清除按钮退出动画播完后才把 suffix 移出树，避免收起动画被截断。
  bool _clearExited = true;

  @override
  void initState() {
    super.initState();
    // 清除按钮的显隐跟随文本内容；页面自身的过滤状态仍由 onChanged 驱动。
    _clearExited = widget.controller.text.isEmpty;
    widget.controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (!mounted) return;
    setState(() {
      if (widget.controller.text.isNotEmpty) _clearExited = false;
    });
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  /// 规范 §4：点击搜索图标或入口框即展开；取消搜索（失焦且清空）即收起。
  bool get _expanded =>
      _focusNode.hasFocus || widget.controller.text.isNotEmpty;

  void _clear() {
    widget.controller.clear();
    widget.onChanged?.call('');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bool hasText = widget.controller.text.isNotEmpty;
    return SearchExpand(
      expanded: _expanded,
      suggestions: widget.suggestions,
      child: SizedBox(
        height: AppSizes.searchBarHeight,
        child: Stack(
          children: [
            TextField(
              controller: widget.controller,
              focusNode: _focusNode,
              onChanged: widget.onChanged,
              onSubmitted: widget.onSubmitted,
              decoration: InputDecoration(
                hintText: widget.hintText,
                hintStyle: theme.textTheme.labelLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                prefixIcon: Pressable(
                  scale: Pressable.iconScale,
                  onTap: _focusNode.requestFocus,
                  child: Icon(
                    Icons.search,
                    size: AppSizes.icon,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                suffixIcon: !hasText && _clearExited
                    ? null
                    : ClearButtonReveal(
                        visible: hasText,
                        onExited: () {
                          if (mounted) setState(() => _clearExited = true);
                        },
                        child: Pressable(
                          scale: Pressable.iconScale,
                          child: IconButton(
                            icon: const Icon(Icons.clear, size: AppSizes.icon),
                            onPressed: _clear,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: AppSizes.searchBarHeight,
                              minHeight: AppSizes.searchBarHeight,
                            ),
                          ),
                        ),
                      ),
                isDense: true,
                filled: true,
                fillColor: scheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadii.search),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                ),
              ),
            ),
            // 规范 §6 获焦指示线：叠在搜索条底边直线段内（左右各让开半高
            // 圆角），不改变 44 高。
            Positioned(
              left: AppRadii.search,
              right: AppRadii.search,
              bottom: 0,
              child: FocusIndicator(
                focused: _focusNode.hasFocus,
                color: scheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
