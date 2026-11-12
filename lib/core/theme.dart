/// 主题 token（规格文档第 3 章 §22.3）。
///
/// 颜色一律用这里的 token，页面内不许写死色值。动态色：Android 12+ 可启用
/// 系统动态色，不支持或用户关闭时回退品牌种子色——现阶段直接用品牌色
/// （未引入 dynamic_color 依赖），以后接动态色时只改这里。
library;

import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  /// 成功色（light / dark）。
  static const Color successLight = Color(0xFF16A34A);
  static const Color successDark = Color(0xFF4ADE80);

  /// 警告色（light / dark）。
  static const Color warningLight = Color(0xFFD97706);
  static const Color warningDark = Color(0xFFFBBF24);

  /// G-02 soft 条背景（文档只定 warningContainer，未给色值；由 warning 派生的浅底）。
  static const Color warningContainerLight = Color(0xFFFEF3C7);
  static const Color warningContainerDark = Color(0xFF451A03);

  /// 品牌页固定色（启动页、Logo 等，不随深浅色模式变化，与 mockup 一致）。
  /// 深色模式下品牌页仍用浅底深字，保证品牌观感统一。
  static const Color pageBackgroundLight = Color(0xFFF8FAFC);
  static const Color brandPrimary = Color(0xFF2563EB);
  static const Color brandOnPrimary = Color(0xFFFFFFFF);
  static const Color brandTitle = Color(0xFF0F172A);
  static const Color brandCaption = Color(0xFF94A3B8);

  static Color success(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? successDark
        : successLight;
  }

  static Color warning(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? warningDark
        : warningLight;
  }

  static Color warningContainer(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? warningContainerDark
        : warningContainerLight;
  }
}

class AppTheme {
  AppTheme._();

  /// 等宽字体族（IP、命令、数字用等宽字体，§22.3.2）。
  static const String monoFontFamily = 'monospace';

  /// 品牌页标题（启动页“路由通”，28 粗体）。
  static const TextStyle brandTitleStyle = TextStyle(
    fontSize: 28,
    height: 1.4,
    fontWeight: FontWeight.w700,
    color: AppColors.brandTitle,
  );

  /// 品牌页副标（“ROUTEPASS”字样，14 常规、宽字距；mockup 未给确切字距，取 4）。
  static const TextStyle brandCaptionStyle = TextStyle(
    fontSize: 14,
    height: 1.4,
    fontWeight: FontWeight.w400,
    letterSpacing: 4,
    color: AppColors.brandCaption,
  );

  static ThemeData get light {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: Color(0xFF2563EB),
      onPrimary: Color(0xFFFFFFFF),
      primaryContainer: Color(0xFFDBEAFE),
      onPrimaryContainer: Color(0xFF1E3A8A),
      secondary: Color(0xFF0EA5E9),
      onSecondary: Color(0xFFFFFFFF),
      secondaryContainer: Color(0xFFE0F2FE),
      onSecondaryContainer: Color(0xFF0C4A6E),
      tertiary: Color(0xFF0EA5E9),
      onTertiary: Color(0xFFFFFFFF),
      error: Color(0xFFDC2626),
      onError: Color(0xFFFFFFFF),
      errorContainer: Color(0xFFFEE2E2),
      onErrorContainer: Color(0xFF7F1D1D),
      surface: Color(0xFFFFFFFF),
      onSurface: Color(0xFF0F172A),
      surfaceContainerHighest: Color(0xFFF1F5F9),
      onSurfaceVariant: Color(0xFF475569),
      outline: Color(0xFFCBD5E1),
      outlineVariant: Color(0xFFE2E8F0),
      shadow: Color(0xFF000000),
      scrim: Color(0xFF000000),
      inverseSurface: Color(0xFF0F172A),
      onInverseSurface: Color(0xFFF1F5F9),
      inversePrimary: Color(0xFF93C5FD),
      surfaceTint: Color(0xFF2563EB),
    );
    return _base(scheme);
  }

  static ThemeData get dark {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xFF93C5FD),
      onPrimary: Color(0xFF0B1220),
      primaryContainer: Color(0xFF1E3A8A),
      onPrimaryContainer: Color(0xFFDBEAFE),
      secondary: Color(0xFF7DD3FC),
      onSecondary: Color(0xFF0B1220),
      secondaryContainer: Color(0xFF0C4A6E),
      onSecondaryContainer: Color(0xFFE0F2FE),
      tertiary: Color(0xFF7DD3FC),
      onTertiary: Color(0xFF0B1220),
      error: Color(0xFFF87171),
      onError: Color(0xFF0B1220),
      errorContainer: Color(0xFF7F1D1D),
      onErrorContainer: Color(0xFFFEE2E2),
      surface: Color(0xFF0F172A),
      onSurface: Color(0xFFF1F5F9),
      surfaceContainerHighest: Color(0xFF1E293B),
      onSurfaceVariant: Color(0xFF94A3B8),
      outline: Color(0xFF475569),
      outlineVariant: Color(0xFF334155),
      shadow: Color(0xFF000000),
      scrim: Color(0xFF000000),
      inverseSurface: Color(0xFFF1F5F9),
      onInverseSurface: Color(0xFF0F172A),
      inversePrimary: Color(0xFF2563EB),
      surfaceTint: Color(0xFF93C5FD),
    );
    return _base(scheme);
  }

  static ThemeData _base(ColorScheme scheme) {
    final bool isDark = scheme.brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark
          ? const Color(0xFF0B1220)
          : const Color(0xFFF7F8FA),
      textTheme: TextTheme(
        headlineLarge: TextStyle(
          fontSize: 24,
          height: 1.4,
          color: scheme.onSurface,
        ),
        headlineMedium: TextStyle(
          fontSize: 22,
          height: 1.4,
          color: scheme.onSurface,
        ),
        titleLarge: TextStyle(
          fontSize: 22,
          height: 1.4,
          color: scheme.onSurface,
        ),
        titleMedium: TextStyle(
          fontSize: 18,
          height: 1.4,
          color: scheme.onSurface,
        ),
        titleSmall: TextStyle(
          fontSize: 16,
          height: 1.5,
          color: scheme.onSurface,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          height: 1.5,
          color: scheme.onSurface,
        ),
        bodyMedium: TextStyle(
          fontSize: 16,
          height: 1.5,
          color: scheme.onSurface,
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          height: 1.5,
          color: scheme.onSurfaceVariant,
        ),
        labelLarge: TextStyle(
          fontSize: 14,
          height: 1.4,
          color: scheme.onSurface,
        ),
        labelMedium: TextStyle(
          fontSize: 12,
          height: 1.4,
          color: scheme.onSurface,
        ),
        labelSmall: TextStyle(
          fontSize: 11,
          height: 1.4,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: EdgeInsets.zero,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}

/// 等宽文本样式（IP、命令、数字用等宽字体，§22.3.2）。
TextStyle monoTextStyle(BuildContext context, {double fontSize = 16}) {
  return TextStyle(
    fontFamily: AppTheme.monoFontFamily,
    fontSize: fontSize,
    height: 1.5,
    color: Theme.of(context).colorScheme.onSurface,
  );
}
