/// 主题 token（规格文档第 3 章 §22.3）。
///
/// 颜色一律用这里的 token，页面内不许写死色值。动态色：Android 12+ 可启用
/// 系统动态色，不支持或用户关闭时回退品牌种子色——现阶段直接用品牌色
/// （未引入 dynamic_color 依赖），以后接动态色时只改这里。
library;

import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  /// 成功色（light / dark）：F14b 起取登录色板薄荷/水绿家族的深绿与亮绿。
  static const Color successLight = Color(0xFF2E9E75);
  static const Color successDark = Color(0xFF85E085);

  /// 警告色（light / dark）：语义琥珀色，登录色板内无对应色，保持不变。
  static const Color warningLight = Color(0xFFD97706);
  static const Color warningDark = Color(0xFFFBBF24);

  /// G-02 soft 条背景（文档只定 warningContainer，未给色值；由 warning 派生的浅底）。
  static const Color warningContainerLight = Color(0xFFFEF3C7);
  static const Color warningContainerDark = Color(0xFF451A03);

  /// 页面底色（F14b 登录色板）：浅色为薄荷+水绿的极浅 tint，深色近黑。
  static const Color pageBackgroundLight = Color(0xFFF2FCF5);

  /// 页面底色（深色）：登录深色渐变起点 #050505。
  static const Color pageBackgroundDark = Color(0xFF050505);

  /// 页面底色：随深浅色模式取登录色板的浅/深底。
  static Color pageBackground(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? pageBackgroundDark
        : pageBackgroundLight;
  }

  /// 品牌主色（浅色交互紫）：登录紫 #8B5CF6 的 85% 加深，白字对比度 ≥4.5。
  static const Color brandPrimary = Color(0xFF764ED1);

  /// 品牌主色（深色交互蓝）：登录气泡蓝 #1D6FE0。
  static const Color brandPrimaryDark = Color(0xFF1D6FE0);

  /// 强调色随深浅色模式：浅色紫 / 深色蓝（F14b 登录色板）。
  static Color accent(BuildContext context) {
    return _isDark(context) ? brandPrimaryDark : brandPrimary;
  }

  static const Color brandOnPrimary = Color(0xFFFFFFFF);
  static const Color brandTitle = Color(0xFF111111);
  static const Color brandCaption = Color(0xFF6E6E6E);
  static const Color brandSurface = Color(0xFFFFFFFF);
  static const Color brandBorder = Color(0xFFE9E9E9);
  static const Color brandLabel = Color(0xFF2B2B2B);
  static const Color brandTransparent = Color(0x00000000);

  /// F14b：登录页 1:1 参考稿色值（提升自 F14a 私有常量，值不变）。
  static const Color loginInkLight = Color(0xFF111111);
  static const Color loginInkDark = Color(0xFFFFFFFF);
  static const Color loginPillLight = Color(0xFFD2D2D2);
  static const Color loginPillDark = Color(0xFF777777);
  static const Color loginErrorLight = Color(0xFFB91C1C);
  static const Color loginErrorDark = Color(0xFFFCA5A5);
  static const Color loginBlobViolet = Color(0xFF8B5CF6);
  static const Color loginMint = Color(0xFFC6F5C6);
  static const Color loginAqua = Color(0xFFB9E6D6);
  static const Color loginPeriwinkle = Color(0xFFA9C6F2);
  static const Color loginPeriwinkleDeep = Color(0xFF8FB4F2);
  static const Color loginNight = Color(0xFF050505);
  static const Color loginCharcoal = Color(0xFF2B2B2B);
  static const Color loginGray = Color(0xFF6E6E6E);
  static const Color loginBubbleHighlight = Color(0xFFBFE9FF);
  static const Color loginBubbleCyan = Color(0xFF38BDF8);
  static const Color loginBubbleBlue = Color(0xFF1D6FE0);
  static const Color loginBubbleDeep = Color(0xFF0B2F7A);
  static const Color loginBubbleAbyss = Color(0xFF061A4D);
  static const Color loginBubbleShadow = Color(0x59000000);

  /// F15：深色气泡内高光（参考稿 inset 4px 6px 10px rgba(255,255,255,.45)
  /// 与 inset -6px -8px 14px rgba(0,0,40,.55)），用对角渐变叠层近似。
  static const Color loginBubbleGloss = Color(0x73FFFFFF);
  static const Color loginBubbleGlossFade = Color(0x00FFFFFF);
  static const Color loginBubbleInnerShade = Color(0x8C000028);
  static const Color loginBubbleInnerShadeFade = Color(0x00000028);

  /// 登录浅色底渐变色标（CSS 105deg：左上偏绿 → 右下偏蓝）。
  static const List<Color> loginBackgroundLightColors = [
    loginMint,
    loginAqua,
    loginPeriwinkle,
    loginPeriwinkleDeep,
  ];

  /// 登录深色底渐变色标（CSS 90deg：近黑 → 中灰）。
  static const List<Color> loginBackgroundDarkColors = [
    loginNight,
    loginCharcoal,
    loginGray,
  ];

  /// 登录深色气泡 radial 渐变色标（高光 → 深蓝）。
  static const List<Color> loginBubbleColors = [
    loginBubbleHighlight,
    loginBubbleCyan,
    loginBubbleBlue,
    loginBubbleDeep,
    loginBubbleAbyss,
  ];

  /// 错题本 / 收藏预览卡入口图标：错题本红底红图标、收藏琥珀底琥珀图标。
  /// 深色模式用对应的 error / warning 容器色，保证图标在深底上可读。
  static const Color wrongIconBackgroundLight = Color(0xFFF5DDDD);
  static const Color wrongIconForegroundLight = Color(0xFFB91C1C);
  static const Color favoriteIconBackgroundLight = Color(0xFFFEF3C7);
  static const Color favoriteIconForegroundLight = Color(0xFFD97706);

  /// 每日一练选项：正确条浅绿底 / 深绿字，错误条深红字（底色复用
  /// wrongIconBackground、边框复用 wrongIconForeground），字母圈浅灰底。
  /// Light 常量为浅色模式取值；深色模式由下面的 context 取色函数切到深色变体。
  static const Color dailyCorrectBackgroundLight = Color(0xFFE2FAE2);
  static const Color dailyCorrectBackgroundDark = Color(0xFF1C4A1C);
  static const Color dailyCorrectTextLight = Color(0xFF1C4A1C);
  static const Color dailyWrongTextLight = Color(0xFF781212);
  static const Color dailyLetterBackgroundLight = Color(0xFFEDEDED);
  static const Color dailyLetterTextLight = Color(0xFF4D4D4D);

  /// 阴影色（胶囊导航：纯黑 8% 不透明度）。
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

  /// 页面次级标签色（浅色 #2B2B2B，深色浅灰保证可读）。
  static Color label(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFD2D2D2)
        : brandLabel;
  }

  /// 页面主标题色（浅色 brandTitle #111111，深色纯白保证可读）。
  static Color title(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFFFFFFF)
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

  /// 搜索条高度（逻辑像素）：知识库与题库共用。
  static const double searchBarHeight = 44;

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

  /// 套卷详情页题型标签 pill 高（逻辑像素，F19）。
  static const double typeTagHeight = 26;

  /// 答题记录卡最小高度（逻辑像素，F19）。
  static const double recordsCardMinHeight = 200;

  /// 答题记录卡单行高度（逻辑像素，F19）。
  static const double recordsRowHeight = 56;

  /// 答题记录卡最大高度系数（可视高 × 0.5，F19）。
  static const double recordsCardMaxHeightFactor = 0.5;

  /// 答题页记录卡最大高度系数（可视高 × 0.40，F19）。
  static const double recordsCardMaxHeightFactorQuiz = 0.40;

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

  /// 搜索栏圆角（约 22 = 半胶囊形）：知识库与题库共用。
  static const double search = 22;

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
      primary: Color(0xFF764ED1),
      onPrimary: Color(0xFFFFFFFF),
      primaryContainer: Color(0xFFE8DEFD),
      onPrimaryContainer: Color(0xFF462E7B),
      secondary: Color(0xFF5D759D),
      onSecondary: Color(0xFFFFFFFF),
      secondaryContainer: Color(0xFFD4E3F9),
      onSecondaryContainer: Color(0xFF144E9D),
      tertiary: Color(0xFF5D759D),
      onTertiary: Color(0xFFFFFFFF),
      error: Color(0xFFB91C1C),
      onError: Color(0xFFFFFFFF),
      errorContainer: Color(0xFFF5DDDD),
      onErrorContainer: Color(0xFF781212),
      surface: Color(0xFFFFFFFF),
      onSurface: Color(0xFF111111),
      surfaceContainerHighest: Color(0xFFEEFCEE),
      onSurfaceVariant: Color(0xFF4D4D4D),
      outline: Color(0xFF777777),
      outlineVariant: Color(0xFFE9E9E9),
      shadow: Color(0xFF000000),
      scrim: Color(0xFF000000),
      inverseSurface: Color(0xFF2B2B2B),
      onInverseSurface: Color(0xFFFFFFFF),
      inversePrimary: Color(0xFF1D6FE0),
      surfaceTint: Color(0xFF764ED1),
    );
    return _base(scheme);
  }

  static ThemeData get dark {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xFF1D6FE0),
      onPrimary: Color(0xFFFFFFFF),
      primaryContainer: Color(0xFF0B2F7A),
      onPrimaryContainer: Color(0xFFBFE9FF),
      secondary: Color(0xFF38BDF8),
      onSecondary: Color(0xFF050505),
      secondaryContainer: Color(0xFF061A4D),
      onSecondaryContainer: Color(0xFFBFE9FF),
      tertiary: Color(0xFF38BDF8),
      onTertiary: Color(0xFF050505),
      error: Color(0xFFFCA5A5),
      onError: Color(0xFF410A0A),
      errorContainer: Color(0xFF5C0E0E),
      onErrorContainer: Color(0xFFFCA5A5),
      surface: Color(0xFF2B2B2B),
      onSurface: Color(0xFFFFFFFF),
      surfaceContainerHighest: Color(0xFF3C3C3C),
      onSurfaceVariant: Color(0xFFD2D2D2),
      outline: Color(0xFF6E6E6E),
      outlineVariant: Color(0xFF4D4D4D),
      shadow: Color(0xFF000000),
      scrim: Color(0xFF000000),
      inverseSurface: Color(0xFFD2D2D2),
      onInverseSurface: Color(0xFF111111),
      inversePrimary: Color(0xFF764ED1),
      surfaceTint: Color(0xFF1D6FE0),
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
