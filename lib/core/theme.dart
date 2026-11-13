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

  /// 页面底色（知识库页等，随深浅色模式变化）。
  static const Color pageBackgroundDark = Color(0xFF0B1220);

  /// 页面底色：浅色 #F8FAFC，深色回退深底。
  static Color pageBackground(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? pageBackgroundDark
        : pageBackgroundLight;
  }

  static const Color brandPrimary = Color(0xFF2563EB);
  static const Color brandOnPrimary = Color(0xFFFFFFFF);
  static const Color brandTitle = Color(0xFF0F172A);
  static const Color brandCaption = Color(0xFF94A3B8);
  static const Color brandSecondaryText = Color(0xFF64748B);
  static const Color brandSurface = Color(0xFFFFFFFF);
  static const Color brandBorder = Color(0xFFE2E8F0);
  static const Color brandLabel = Color(0xFF334155);
  static const Color brandTransparent = Color(0x00000000);

  /// 阴影色（胶囊导航：Colors.black 8% 不透明度）。
  static const Color shadow = Color(0x14000000);

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

  /// 页面次级标签色（浅色 #334155，深色浅灰保证可读）。
  static Color label(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF94A3B8)
        : brandLabel;
  }

  /// 页面主标题色（浅色 brandTitle #0F172A，深色 #F1F5F9 保证可读）。
  static Color title(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFF1F5F9)
        : brandTitle;
  }
}

/// 品牌页间距（逻辑像素）。
class AppSpacing {
  AppSpacing._();

  static const double xxxs = 2;
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 40;
  static const double pageTop = 60;
  static const double pageHorizontal = 24;
  static const double pageBottom = 24;
  static const double formBlock = 24;
  static const double fieldLabelGap = 8;
  static const double fieldHorizontal = 16;
  static const double fieldVertical = 14;

  /// 题库页卡片/入口行之间的间距（逻辑像素）。
  static const double cardGap = 14;

  /// 套卷详情页模块行之间的间距（逻辑像素）。
  static const double setDetailModuleGap = 20;

  /// 知识库页章卡片 / 知识点行之间的间距（逻辑像素）。
  static const double chapterGap = 10;

  /// 启动页 Logo 与应用名之间的间距（逻辑像素）。
  static const double splashLogoGap = 28;

  /// 启动页应用名与英文名之间的间距（逻辑像素）。
  static const double splashNameGap = 14;
}

/// 品牌页尺寸（逻辑像素）。
class AppSizes {
  AppSizes._();

  static const double contentMaxWidth = 410;
  static const double logo = 56;
  static const double buttonHeight = 52;
  static const double borderWidth = 1;
  static const double focusedBorderWidth = 1.5;
  static const double icon = 20;
  static const double avatarRadius = 20;
  static const double progressRing = 40;

  /// 知识库页搜索栏高度（逻辑像素）。
  static const double searchBarHeight = 44;

  /// 题库页搜索栏高度（逻辑像素）。
  static const double bankSearchBarHeight = 48;

  /// 题库页搜索栏搜索按钮直径（逻辑像素）。
  static const double bankSearchButtonSize = 40;

  /// 知识库页章卡片高度（逻辑像素）。
  static const double chapterCardHeight = 56;

  /// 知识库页知识点行高度（逻辑像素）。
  static const double pointRowHeight = 44;

  /// 题库页套卷卡高度（逻辑像素）。
  static const double setCardHeight = 104;

  /// 题库页错题本/收藏入口行高度（逻辑像素）。
  static const double entryRowHeight = 64;

  /// 题库页套卷卡小进度环直径（逻辑像素，半径约 16）。
  static const double setProgressRing = 32;

  /// 题库页套卷卡“开始”按钮宽（逻辑像素）。
  static const double setStartButtonWidth = 76;

  /// 题库页套卷卡“开始”按钮高（逻辑像素）。
  static const double setStartButtonHeight = 36;

  /// 套卷详情页模块进度条高（逻辑像素）。
  static const double setDetailProgressBarHeight = 6;

  /// 套卷详情页预留容器高（逻辑像素）。
  static const double setDetailReservedSlotHeight = 64;

  /// 套卷详情页答题说明卡高（逻辑像素）。
  static const double setDetailInstructionsHeight = 108;

  /// 工具箱页工具卡高度（逻辑像素）。
  static const double toolboxCardHeight = 104;

  /// 工具箱页工具卡图标尺寸（逻辑像素）。
  static const double toolIconSize = 22;

  /// 小图标尺寸（逻辑像素）。
  static const double iconSmall = 16;

  /// 大图标尺寸（逻辑像素）。
  static const double iconLarge = 24;

  /// 分隔线高度（逻辑像素）。
  static const double divider = 1;

  /// 启动页 Logo 尺寸（逻辑像素）。
  static const double splashLogo = 72;

  /// 大图标尺寸（逻辑像素）。
  static const double iconXLarge = 32;

  /// 首页问候区顶部预留高度（逻辑像素，为钉住头像留空）。
  static const double homeTopPad = 68;

  /// 首页及各 tab 滚动内容底部预留高度（逻辑像素，防止内容被浮动胶囊遮住）。
  static const double homeBottomPad = 100;

  /// 首页工具箱网格图标尺寸（逻辑像素）。
  static const double toolGridIconSize = 30;

  /// 套卷行卡片最小高度（逻辑像素）。
  static const double setRowMinHeight = 76;

  /// 首页横幅“开始”按钮宽（逻辑像素）。
  static const double bannerButtonWidth = 64;

  /// 首页横幅“开始”按钮高（逻辑像素）。
  static const double bannerButtonHeight = 36;

  /// 首页同步 chip 高（逻辑像素）。
  static const double syncChipHeight = 28;

  /// 同步诊断 sheet 内按钮高（逻辑像素）。
  static const double sheetButtonHeight = 48;

  /// 同步诊断行标签列宽（逻辑像素）。
  static const double syncLabelWidth = 88;

  /// 空态图标尺寸（逻辑像素）。
  static const double emptyStateIcon = 48;

  /// 空态顶部间距（逻辑像素）。
  static const double emptyStateTop = 48;

  /// 胶囊导航高（逻辑像素）。
  static const double navBarHeight = 64;

  /// 胶囊导航最大宽度（逻辑像素：胶囊体 254 + 两侧留白，匹配 410 宽 mockup）。
  static const double navBarMaxWidth = 286;

  /// 胶囊导航选中椭圆底宽（逻辑像素）。
  static const double navSelectedWidth = 56;

  /// 胶囊导航选中椭圆底高（逻辑像素）。
  static const double navSelectedHeight = 32;

  /// 胶囊导航阴影 Y 偏移（逻辑像素）。
  static const double navShadowOffsetY = 8;

  /// 胶囊导航阴影模糊半径（逻辑像素）。
  static const double navShadowBlur = 24;

  /// 进度环描边宽（逻辑像素）。
  static const double ringStroke = 3;
}

/// 品牌页圆角（逻辑像素）。
class AppRadii {
  AppRadii._();

  static const double input = 14;
  static const double button = 14;
  static const double card = 16;

  /// 知识库页搜索栏圆角（约 22 = 半胶囊形）。
  static const double search = 22;

  /// 题库页搜索栏圆角（999 = 全胶囊形）。
  static const double searchPill = 999;

  /// 知识库页章卡片圆角（逻辑像素）。
  static const double chapterCard = 14;

  /// 知识库页知识点行圆角（逻辑像素）。
  static const double pointRow = 12;

  /// 题库页套卷卡“开始”按钮圆角（逻辑像素）。
  static const double setStartButton = 18;

  /// 套卷详情页“开始答题”按钮圆角（逻辑像素）。
  static const double setDetailStartButton = 13;

  /// 套卷详情页模块进度条圆角（逻辑像素）。
  static const double setDetailProgressBar = 3;

  /// 胶囊导航整体圆角（约 999 = 全胶囊形）。
  static const double navCapsule = 999;

  /// 同步 chip 圆角（逻辑像素）。
  static const double syncChip = 14;

  /// 底部 sheet 顶部圆角（逻辑像素）。
  static const double bottomSheet = 24;
}

/// 品牌页字号（逻辑像素）。textTheme 未覆盖的少量字号在这里定义。
class AppFontSizes {
  AppFontSizes._();

  /// 页头副标题（题库页“H3CNE 300 道 · 每套含解析”）。
  static const double pageSubtitle = 13;

  /// 套卷卡模块小标签。
  static const double setCardTag = 10;

  /// 错题本/收藏入口行标题。
  static const double entryTitle = 15;

  /// 工具箱页工具卡标题。
  static const double toolCardTitle = 15;

  /// 套卷详情页大标题。
  static const double detailTitle = 28;

  /// 套卷详情页小节标题。
  static const double detailSectionTitle = 20;

  /// 套卷详情页正文。
  static const double detailBody = 14;

  /// 套卷详情页统计/说明文字。
  static const double detailStat = 13;

  /// 套卷详情页“开始答题”按钮文字。
  static const double detailButton = 16;

  /// 首页问候区昵称字号（逻辑像素，28 特粗）。
  static const double homeGreetingName = 28;
}

/// 品牌动画时长。
class AppDurations {
  AppDurations._();

  /// 胶囊导航选中态淡入淡出（毫秒）。
  static const Duration navFade = Duration(milliseconds: 200);
}

/// 工具箱工具卡图标色调（蓝/绿/橙，见 §4.10 T-B 卡片）。
enum ToolIconTone { blue, green, orange }

/// 工具箱工具卡图标色：蓝用主色，绿用成功色，橙用警告色（均随深浅色模式）。
Color toolIconColor(ToolIconTone tone, BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return switch (tone) {
    ToolIconTone.blue => scheme.primary,
    ToolIconTone.green => AppColors.success(context),
    ToolIconTone.orange => AppColors.warning(context),
  };
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

  /// 品牌页说明文字（登录页副标题、辅助文案）。
  static const TextStyle brandSubtitleStyle = TextStyle(
    fontSize: 14,
    height: 1.5,
    fontWeight: FontWeight.w400,
    color: AppColors.brandCaption,
  );

  /// 表单标签（输入框上方）。
  static const TextStyle brandFieldLabelStyle = TextStyle(
    fontSize: 14,
    height: 1.4,
    fontWeight: FontWeight.w500,
    color: AppColors.brandLabel,
  );

  /// 表单输入文字。
  static const TextStyle brandFieldTextStyle = TextStyle(
    fontSize: 16,
    height: 1.5,
    color: AppColors.brandTitle,
  );

  /// 表单占位文字。
  static const TextStyle brandFieldHintStyle = TextStyle(
    fontSize: 16,
    height: 1.5,
    fontWeight: FontWeight.w400,
    color: AppColors.brandCaption,
  );

  /// 品牌主按钮文字。
  static const TextStyle brandButtonStyle = TextStyle(
    fontSize: 16,
    height: 1.4,
    fontWeight: FontWeight.w600,
    color: AppColors.brandOnPrimary,
  );

  /// 品牌页蓝色文字链接。
  static const TextStyle brandLinkStyle = TextStyle(
    fontSize: 14,
    height: 1.4,
    fontWeight: FontWeight.w500,
    color: AppColors.brandPrimary,
  );

  /// 用于保留语义标签但不显示的内嵌标签样式。
  static const TextStyle hiddenFieldLabelStyle = TextStyle(
    fontSize: 0,
    height: 0,
    color: AppColors.brandTransparent,
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
          ? AppColors.pageBackgroundDark
          : AppColors.pageBackgroundLight,
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
