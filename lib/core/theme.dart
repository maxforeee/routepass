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
  static const Color brandSurface = Color(0xFFFFFFFF);
  static const Color brandBorder = Color(0xFFE2E8F0);
  static const Color brandLabel = Color(0xFF334155);
  static const Color brandTransparent = Color(0x00000000);

  /// 错题本 / 收藏预览卡入口图标：错题本红底红图标、收藏琥珀底琥珀图标。
  /// 深色模式用对应的 error / warning 容器色，保证图标在深底上可读。
  static const Color wrongIconBackgroundLight = Color(0xFFFEE2E2);
  static const Color wrongIconForegroundLight = Color(0xFFDC2626);
  static const Color favoriteIconBackgroundLight = Color(0xFFFEF3C7);
  static const Color favoriteIconForegroundLight = Color(0xFFD97706);

  /// 每日一练选项：正确条浅绿底 / 深绿字，错误条深红字（底色复用
  /// wrongIconBackground、边框复用 wrongIconForeground），字母圈浅灰底。
  /// Light 常量为浅色模式取值；深色模式由下面的 context 取色函数切到深色变体。
  static const Color dailyCorrectBackgroundLight = Color(0xFFDCFCE7);
  static const Color dailyCorrectBackgroundDark = Color(0xFF14532D);
  static const Color dailyCorrectTextLight = Color(0xFF14532D);
  static const Color dailyWrongTextLight = Color(0xFF7F1D1D);
  static const Color dailyLetterBackgroundLight = Color(0xFFF1F5F9);
  static const Color dailyLetterTextLight = Color(0xFF475569);

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

  /// 卡片底色：跟随当前模式（浅色白 / 深色深 surface）。
  static Color cardSurface(BuildContext context) {
    return Theme.of(context).colorScheme.surface;
  }

  /// 卡片边框：跟随当前模式（浅色浅灰 / 深色深描边）。
  static Color cardBorder(BuildContext context) {
    return Theme.of(context).colorScheme.outlineVariant;
  }

  /// 卡片主文字：跟随当前模式（与卡片底色成对比）。
  static Color cardTitle(BuildContext context) {
    return Theme.of(context).colorScheme.onSurface;
  }

  /// 卡片次级文字：跟随当前模式。
  static Color cardSecondary(BuildContext context) {
    return Theme.of(context).colorScheme.onSurfaceVariant;
  }

  /// 卡片弱提示色（浅色 brandCaption，深色浅灰）。
  static Color cardCaption(BuildContext context) {
    return _isDark(context)
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : brandCaption;
  }

  static bool _isDark(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark;
  }

  /// 错题本入口图标底色（浅色浅红 / 深色 error 容器）。
  static Color wrongIconBackground(BuildContext context) {
    return _isDark(context)
        ? Theme.of(context).colorScheme.errorContainer
        : wrongIconBackgroundLight;
  }

  /// 错题本入口图标前景色（浅色深红 / 深色 error 容器上的浅字）。
  static Color wrongIconForeground(BuildContext context) {
    return _isDark(context)
        ? Theme.of(context).colorScheme.onErrorContainer
        : wrongIconForegroundLight;
  }

  /// 收藏入口图标底色（浅色浅琥珀 / 深色 warning 容器）。
  static Color favoriteIconBackground(BuildContext context) {
    return _isDark(context)
        ? warningContainerDark
        : favoriteIconBackgroundLight;
  }

  /// 收藏入口图标前景色（浅色琥珀 / 深色亮琥珀）。
  static Color favoriteIconForeground(BuildContext context) {
    return _isDark(context) ? warningDark : favoriteIconForegroundLight;
  }

  /// 每日一练正确选项底色（深色用深绿容器）。
  static Color dailyCorrectBackground(BuildContext context) {
    return _isDark(context)
        ? dailyCorrectBackgroundDark
        : dailyCorrectBackgroundLight;
  }

  /// 每日一练未作答选项底色（浅色白 / 深色抬升层，保证与透明卡面可分）。
  static Color dailyOptionIdleBackground(BuildContext context) {
    return _isDark(context)
        ? Theme.of(context).colorScheme.surfaceContainerHighest
        : brandSurface;
  }

  /// 每日一练正确选项文字色。
  static Color dailyCorrectText(BuildContext context) {
    return _isDark(context) ? successDark : dailyCorrectTextLight;
  }

  /// 每日一练错误选项文字色（深色用 error 容器上的浅字）。
  static Color dailyWrongText(BuildContext context) {
    return _isDark(context)
        ? Theme.of(context).colorScheme.onErrorContainer
        : dailyWrongTextLight;
  }

  /// 每日一练选项字母圈底色。
  static Color dailyLetterBackground(BuildContext context) {
    return _isDark(context)
        ? Theme.of(context).colorScheme.surface
        : dailyLetterBackgroundLight;
  }

  /// 每日一练选项字母文字色。
  static Color dailyLetterText(BuildContext context) {
    return _isDark(context)
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : dailyLetterTextLight;
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

  /// 标题以下内容元素每侧额外内缩（逻辑像素）：页面内边距 md(16) 之上再叠
  /// 15，内容离屏幕边 31；页头 / 标题 / 首页问候区与头像不加这层内缩。
  static const double contentInset = 15;

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

  /// 题库页练习/考试切换行内边距（上 12 / 下 18）。
  static const double bankTabsPaddingTop = 12;
  static const double bankTabsPaddingBottom = 18;

  /// 题库页两个切换 tab 之间的距离（逻辑像素）。
  static const double bankTabGap = 72;

  /// 首页错题本 / 收藏预览卡的上下内边距（逻辑像素，左右用 md）。
  static const double previewCardPadV = 14;

  /// 预览项圆点与题干之间的间距（逻辑像素）。
  static const double previewItemGap = 8;

  /// 首页每日一练卡片上内边距（逻辑像素，留出骑在边框上的标题）。
  static const double dailyCardPadTop = 26;

  /// 首页每日一练标题向上压边框的偏移量（逻辑像素）。
  static const double dailyTitleOverhang = 11;

  /// 首页每日一练标题距卡片左边缘（逻辑像素）。
  static const double dailyTitleLeft = 20;

  /// 首页每日一练标题左右内边距（逻辑像素，顶部边框在此处留出缺口）。
  static const double dailyTitlePadH = 10;

  /// 首页每日一练题干与选项之间的间距（逻辑像素）。
  static const double dailyQuestionGap = 14;

  /// 首页每日一练选项条之间的间距（逻辑像素）。
  static const double dailyOptionGap = 10;

  /// 首页每日一练选项条上下内边距（逻辑像素）。
  static const double dailyOptionPadV = 13;

  /// 首页每日一练选项条左右内边距（逻辑像素）。
  static const double dailyOptionPadH = 16;
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

  /// 题库页切换 tab 虚线指示线高（逻辑像素）。
  static const double bankTabLineHeight = 2;

  /// 题库页切换 tab 指示线比标签每侧多出的长度（逻辑像素）。
  static const double bankTabLineOverhang = 10;

  /// 题库页切换 tab 标签与指示线之间的间距（逻辑像素）。
  static const double bankTabLineGap = 7;

  /// 题库页切换 tab 虚线段长（逻辑像素）。
  static const double bankTabDash = 6;

  /// 题库页切换 tab 虚线间隔（逻辑像素）。
  static const double bankTabDashGap = 5;

  /// 题库页切换 tab 标签行高（倍数，与 canva 参考 1.2 一致）。
  static const double bankTabLabelHeight = 1.2;

  /// 题库页未选中 tab 指示线不透明度（canva 参考 .45）。
  static const double bankTabLineInactiveOpacity = 0.45;

  /// 首页错题本 / 收藏预览卡入口图标尺寸（逻辑像素，圆角方底）。
  static const double previewIconSize = 44;

  /// 首页每日一练选项字母圈直径（逻辑像素）。
  static const double dailyLetterSize = 26;
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

  /// 首页预览卡入口图标圆角（逻辑像素）。
  static const double previewIcon = 12;

  /// 首页每日一练选项条圆角（逻辑像素）。
  static const double dailyOption = 14;
}

/// 品牌页字号（逻辑像素）。textTheme 未覆盖的少量字号在这里定义。
class AppFontSizes {
  AppFontSizes._();

  /// 页头副标题（PageHeader 统一字号，如题库页「练习考试」）。
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

  /// 首页问候语字号（逻辑像素，28 粗体，小于昵称字号保持层级）。
  static const double homeGreetingHi = 28;

  /// 首页问候区昵称字号（逻辑像素，32 特粗）。
  static const double homeGreetingName = 32;

  /// 题库页练习/考试切换标签字号（逻辑像素）。
  static const double bankTabLabel = 20;

  /// 首页预览卡“今日新增 N 道”计数字号（逻辑像素）。
  static const double previewCount = 12;

  /// 首页预览卡条目（题干一行）字号（逻辑像素）。
  static const double previewItem = 13;

  /// 首页每日一练标题字号（逻辑像素）。
  static const double dailyTitle = 17;

  /// 首页每日一练题干字号（逻辑像素）。
  static const double dailyQuestion = 15;

  /// 首页每日一练选项文字字号（逻辑像素）。
  static const double dailyOption = 15;

  /// 首页每日一练选项字母字号（逻辑像素）。
  static const double dailyLetter = 13;

  /// 首页每日一练锁定提示字号（逻辑像素）。
  static const double dailyLockHint = 12;
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
