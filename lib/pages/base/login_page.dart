import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_animations.dart';
import '../../core/app_snackbar.dart';
import '../../core/service_locator.dart';
import '../../core/theme.dart';
import '../../router/app_router.dart';
import '../../services/base/auth_service.dart';

// F14a 登录页 1:1 参考稿（routepass_login_1to1.html）专用尺寸；
// 色值已在 F14b 提升为 AppColors 登录色板 token，本页只引用 token。

/// 浅色底：CSS 105deg 对角渐变（左上偏绿 → 右下偏蓝）。
const LinearGradient _backgroundLight = LinearGradient(
  begin: Alignment(-0.97, -0.26),
  end: Alignment(0.97, 0.26),
  colors: AppColors.loginBackgroundLightColors,
  stops: [0.0, 0.30, 0.68, 1.0],
);

/// 深色底：CSS 90deg 水平渐变（近黑 → 中灰）。
const LinearGradient _backgroundDark = LinearGradient(
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
  colors: AppColors.loginBackgroundDarkColors,
  stops: [0.0, 0.52, 1.0],
);

/// 深色气泡高光：radial-gradient(circle at 32% 28%, ...)。
const RadialGradient _bubbleGradient = RadialGradient(
  center: Alignment(-0.36, -0.44),
  colors: AppColors.loginBubbleColors,
  stops: [0.0, 0.22, 0.48, 0.78, 1.0],
);

/// F15（P1-4）：气泡内高光——左上白色高光 → 右下深蓝内阴影，对应参考稿
/// inset 4px 6px 10px rgba(255,255,255,.45) 与 inset -6px -8px 14px rgba(0,0,40,.55)。
/// Flutter 无 inset 阴影，用对角渐变叠层近似；中段全透明，露出 radial 底色。
const LinearGradient _bubbleInnerLight = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [
    AppColors.loginBubbleGloss,
    AppColors.loginBubbleGlossFade,
    AppColors.loginBubbleInnerShadeFade,
    AppColors.loginBubbleInnerShade,
  ],
  stops: [0.0, 0.35, 0.65, 1.0],
);

// F18：F15 尺寸整体缩小——元素尺寸 x0.6，纵向间距 x0.8，
// 让登录页比例贴近参考稿并在手机上一屏内更宽松。
const double _graphicTop = 62;
const double _graphicHeight = 138;
const double _graphicToTitle = 42;
const double _titleToPill = 51;
const double _pillGap = 30;
const double _pillHeight = 34;
const double _pillMaxWidth = 180;
const double _pillWidthFactor = 0.44;
const double _pillFontSize = 14;
const double _titleFontSize = 24;

/// F15：离线打包的 Oswald（用户提供的 TTF，见 pubspec fonts:），标题 700 / 胶囊 600。
const String _loginFontFamily = 'Oswald';

const double _blobWidth = 141;
const double _blobHeight = 123;
const double _blobBumpSize = 55;
const double _blobBumpOverhang = 18;
const double _blobBumpTop = 31;
const double _blobFloatRange = 8;
const double _blobTilt = 1.5 * math.pi / 180;

/// 参考稿 border-radius 48% 52% 46% 54% / 58% 60% 40% 42%（按 141x123 缩放）。
const BorderRadius _blobRadiusA = BorderRadius.only(
  topLeft: Radius.elliptical(67.7, 71.3),
  topRight: Radius.elliptical(73.3, 73.8),
  bottomRight: Radius.elliptical(64.9, 49.2),
  bottomLeft: Radius.elliptical(76.1, 51.7),
);

/// 形变目标 55% 45% 52% 48% / 50% 55% 45% 50%（同比例缩放）。
const BorderRadius _blobRadiusB = BorderRadius.only(
  topLeft: Radius.elliptical(77.6, 61.5),
  topRight: Radius.elliptical(63.5, 67.7),
  bottomRight: Radius.elliptical(73.3, 55.4),
  bottomLeft: Radius.elliptical(67.7, 61.5),
);

const double _clusterWidth = 126;
const double _clusterHeight = 108;
const double _clusterFloatRange = 6;
const double _bubbleBobRange = 5;
const double _bubbleBobPeriod = 4;

class _BubbleSpec {
  const _BubbleSpec(this.size, this.left, this.top, this.delay);

  final double size;
  final double left;
  final double top;
  final double delay;
}

/// 深色气泡簇：直径 / 位置 / 起伏延迟均取自参考稿 b1–b7。
const List<_BubbleSpec> _bubbleSpecs = [
  _BubbleSpec(53, 0, 31, 0),
  _BubbleSpec(38, 35, 5, 0.5),
  _BubbleSpec(46, 49, 23, 1.0),
  _BubbleSpec(35, 83, 0, 1.4),
  _BubbleSpec(40, 85, 40, 0.8),
  _BubbleSpec(36, 58, 62, 1.8),
  _BubbleSpec(26, 26, 72, 2.2),
];

const OutlineInputBorder _pillBorder = OutlineInputBorder(
  borderRadius: BorderRadius.all(Radius.circular(999)),
  borderSide: BorderSide.none,
);

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.authService});

  /// 测试可注入；生产为 ServiceLocator.authService。
  final AuthService? authService;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with TickerProviderStateMixin {
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneFocus = FocusNode();
  final _passwordFocus = FocusNode();
  String? _phoneError;
  String? _passwordError;
  bool _submitting = false;

  late final AnimationController _blobFloat;
  late final AnimationController _blobMorph;
  late final AnimationController _clusterFloat;
  late final AnimationController _bubbleBob;
  late final Animation<double> _blobFloatCurve;
  late final Animation<double> _blobMorphCurve;
  late final Animation<double> _clusterFloatCurve;

  static final RegExp _phoneRegExp = RegExp(r'^1[3-9]\d{9}$');

  @override
  void initState() {
    super.initState();
    _phoneFocus.addListener(_onFocusChange);
    _passwordFocus.addListener(_onFocusChange);
    // CSS 关键帧 0%/100% 同值、50% 到峰值：用 repeat(reverse) 的半周期表达。
    _blobFloat = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat(reverse: true);
    _blobMorph = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3500),
    )..repeat(reverse: true);
    _clusterFloat = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat(reverse: true);
    _bubbleBob = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    )..repeat();
    _blobFloatCurve = CurvedAnimation(
      parent: _blobFloat,
      curve: Curves.easeInOut,
    );
    _blobMorphCurve = CurvedAnimation(
      parent: _blobMorph,
      curve: Curves.easeInOut,
    );
    _clusterFloatCurve = CurvedAnimation(
      parent: _clusterFloat,
      curve: Curves.easeInOut,
    );
  }

  void _onFocusChange() {
    setState(() {});
  }

  @override
  void dispose() {
    _phoneFocus.removeListener(_onFocusChange);
    _passwordFocus.removeListener(_onFocusChange);
    _phoneFocus.dispose();
    _passwordFocus.dispose();
    _blobFloat.dispose();
    _blobMorph.dispose();
    _clusterFloat.dispose();
    _bubbleBob.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String? _validatePhone(String value) {
    if (value.isEmpty) {
      return '请输入手机号码';
    }
    if (!_phoneRegExp.hasMatch(value)) {
      return '请输入 11 位手机号码';
    }
    return null;
  }

  String? _validatePassword(String value) {
    if (value.isEmpty) {
      return '请输入密码';
    }
    // 服务端规则：密码 6–72 **字节**（中文等多字节字符按字节算）。
    final bytes = utf8.encode(value).length;
    if (bytes < 6 || bytes > 72) {
      return '密码长度需为 6-72 字节';
    }
    return null;
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final phoneError = _validatePhone(_phoneController.text.trim());
    final passwordError = _validatePassword(_passwordController.text);
    setState(() {
      _phoneError = phoneError;
      _passwordError = passwordError;
    });
    if (phoneError != null || passwordError != null) {
      return;
    }
    setState(() => _submitting = true);
    final auth = widget.authService ?? ServiceLocator.authService;
    final result = await auth.login(
      phone: _phoneController.text.trim(),
      password: _passwordController.text,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (!result.success) {
      // 服务端文案（401 / 422 / 409）或网络错误；留在登录页，不导航。
      showAppSnackBar(context, result.message ?? '登录失败', aboveNav: false);
      return;
    }
    final restoreCode = result.restoreCode;
    if (restoreCode != null && restoreCode.isNotEmpty) {
      // 新账号的一次性恢复码：必须让用户看到并存下。
      await _showRestoreCode(restoreCode);
      if (!mounted) return;
    }
    // cache-first：登录后后台把服务端记录 / 增量拉进本地，不阻塞进首页。
    unawaited(_syncAfterLogin());
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(AppRoutes.home);
  }

  Future<void> _syncAfterLogin() async {
    try {
      await ServiceLocator.answerRecordService.syncFromServer();
    } catch (_) {
      // 接口未就绪 / 离线：本地缓存照常可用。
    }
    try {
      await ServiceLocator.syncService.pullIncremental();
    } catch (_) {
      // 同上，同步失败不影响登录结果。
    }
  }

  Future<void> _showRestoreCode(String code) async {
    await showAppDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('请保存恢复码'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('新账号已创建成功。下面是 12 词恢复码，只显示这一次；忘记密码时凭它找回，请立即抄下或复制保存。'),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(dialogContext).colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  code,
                  key: const Key('restore-code'),
                  style: const TextStyle(fontFamily: 'monospace', height: 1.5),
                ),
              ),
            ],
          ),
          actions: [
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: code));
                if (!dialogContext.mounted) return;
                showAppSnackBar(dialogContext, '恢复码已复制');
              },
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('复制'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('我已保存，进入 App'),
            ),
          ],
        );
      },
    );
  }

  TextStyle _pillTextStyle(Color color) {
    return TextStyle(
      fontFamily: _loginFontFamily,
      fontSize: _pillFontSize,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.12,
      height: 1.0,
      color: color,
    );
  }

  Widget _buildPillField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hint,
    required double width,
    required Color pillColor,
    required Color textColor,
    required Color errorColor,
    String? errorText,
    bool obscureText = false,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    ValueChanged<String>? onSubmitted,
    Iterable<String>? autofillHints,
  }) {
    // 聚焦即隐藏占位符（Flutter 默认聚焦仍显示 hint，这里必须覆盖）。
    // 规范 §6 标签上浮：本输入用 hint 而非 label，无标签可浮；TextField 自带
    // 的标签浮动（SDK 固定 167ms）无 token 绑定入口，按规范说明不重建 TextField。
    final decoration = InputDecoration(
      hintText: focusNode.hasFocus ? null : hint,
      hintStyle: _pillTextStyle(textColor),
      errorText: errorText,
      errorStyle: TextStyle(fontSize: 10, color: errorColor),
      filled: true,
      fillColor: pillColor,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 17,
        vertical: (_pillHeight - _pillFontSize) / 2,
      ),
      border: _pillBorder,
      enabledBorder: _pillBorder,
      focusedBorder: _pillBorder,
      errorBorder: _pillBorder,
      focusedErrorBorder: _pillBorder,
    );
    // 规范 §6：报错时输入框抖动；错误文案走 InputDecoration.errorText（校验
    // 结果对外暴露在同一处，不再另挂一份 AnimatedErrorText 造成重复显示）；获焦
    // 指示线叠在胶囊底边直线段内（左右各让开半高的圆角），不改变输入框尺寸。
    return SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ErrorShake(
            hasError: errorText != null,
            child: Stack(
              children: [
                TextField(
                  controller: controller,
                  focusNode: focusNode,
                  obscureText: obscureText,
                  keyboardType: keyboardType,
                  textInputAction: textInputAction,
                  onSubmitted: onSubmitted,
                  autofillHints: autofillHints,
                  textAlign: TextAlign.center,
                  textAlignVertical: TextAlignVertical.center,
                  style: _pillTextStyle(textColor),
                  decoration: decoration,
                ),
                Positioned(
                  left: _pillHeight / 2,
                  right: _pillHeight / 2,
                  bottom: 0,
                  child: FocusIndicator(
                    focused: focusNode.hasFocus,
                    color: textColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBlob() {
    return AnimatedBuilder(
      animation: Listenable.merge([_blobFloatCurve, _blobMorphCurve]),
      builder: (context, _) {
        final float = _blobFloatCurve.value;
        final radius = BorderRadius.lerp(
          _blobRadiusA,
          _blobRadiusB,
          _blobMorphCurve.value,
        )!;
        return Transform.translate(
          offset: Offset(0, -_blobFloatRange * float),
          child: Transform.rotate(
            angle: _blobTilt * float,
            // F15（P1-3）：居中 blob 本体，凸起挂在左缘外（left: -18），
            // 与参考稿一致；旧实现居中 265 宽容器导致 blob 右偏 15px。
            child: SizedBox(
              width: _blobWidth,
              height: _blobHeight,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 0,
                    top: 0,
                    child: Container(
                      width: _blobWidth,
                      height: _blobHeight,
                      decoration: BoxDecoration(
                        color: AppColors.loginBlobViolet,
                        borderRadius: radius,
                      ),
                    ),
                  ),
                  Positioned(
                    left: -_blobBumpOverhang,
                    top: _blobBumpTop,
                    child: Container(
                      width: _blobBumpSize,
                      height: _blobBumpSize,
                      decoration: const BoxDecoration(
                        color: AppColors.loginBlobViolet,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// 单个气泡的起伏：余弦波保证 0 → -9 → 0 平滑循环，delay 制造错峰。
  double _bobOffset(double phase) {
    final t = phase % 1.0;
    return -_bubbleBobRange * (0.5 - 0.5 * math.cos(2 * math.pi * t));
  }

  Widget _buildBubbles() {
    return AnimatedBuilder(
      animation: Listenable.merge([_clusterFloatCurve, _bubbleBob]),
      builder: (context, _) {
        return Transform.translate(
          offset: Offset(0, -_clusterFloatRange * _clusterFloatCurve.value),
          child: SizedBox(
            width: _clusterWidth,
            height: _clusterHeight,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (final bubble in _bubbleSpecs)
                  Positioned(
                    left: bubble.left,
                    top:
                        bubble.top +
                        _bobOffset(
                          _bubbleBob.value + bubble.delay / _bubbleBobPeriod,
                        ),
                    child: Container(
                      width: bubble.size,
                      height: bubble.size,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: _bubbleGradient,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.loginBubbleShadow,
                            offset: Offset(0, 4),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      foregroundDecoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: _bubbleInnerLight,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pillColor = isDark
        ? AppColors.loginPillDark
        : AppColors.loginPillLight;
    final textColor = isDark ? AppColors.loginInkDark : AppColors.loginInkLight;
    final errorColor = isDark
        ? AppColors.loginErrorDark
        : AppColors.loginErrorLight;
    final pillWidth = math.min(
      MediaQuery.sizeOf(context).width * _pillWidthFactor,
      _pillMaxWidth,
    );
    // 参考稿图形距屏幕顶 78（含状态栏区域）；SafeArea 之外先取真实 inset，
    // 保证内容总偏移 = max(78, 系统 inset)，不会压到状态栏下面。
    final topInset = MediaQuery.paddingOf(context).top;

    // F15：导航栏透明 + 关闭系统对比度 scrim，渐变才能透进底部系统区域。
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
      ),
      child: Scaffold(
        body: Container(
          // F15：显式撑满整屏（含底部系统 inset）。Scaffold body 是松约束，
          // 不指定尺寸时 Container 会收缩到内容高度，下方露出黑底。
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            gradient: isDark ? _backgroundDark : _backgroundLight,
          ),
          child: SafeArea(
            top: true,
            bottom: false,
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                top: math.max(0.0, _graphicTop - topInset),
                bottom: 19,
              ),
              child: Column(
                children: [
                  SizedBox(
                    height: _graphicHeight,
                    child: Center(
                      child: isDark ? _buildBubbles() : _buildBlob(),
                    ),
                  ),
                  const SizedBox(height: _graphicToTitle),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'login in / sign up',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: _loginFontFamily,
                        fontSize: _titleFontSize,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                        height: 1.1,
                        color: textColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: _titleToPill),
                  _buildPillField(
                    controller: _phoneController,
                    focusNode: _phoneFocus,
                    hint: 'phone number',
                    width: pillWidth,
                    pillColor: pillColor,
                    textColor: textColor,
                    errorColor: errorColor,
                    errorText: _phoneError,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.telephoneNumber],
                  ),
                  const SizedBox(height: _pillGap),
                  _buildPillField(
                    controller: _passwordController,
                    focusNode: _passwordFocus,
                    hint: 'password',
                    width: pillWidth,
                    pillColor: pillColor,
                    textColor: textColor,
                    errorColor: errorColor,
                    errorText: _passwordError,
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    autofillHints: const [AutofillHints.password],
                  ),
                  const SizedBox(height: _pillGap),
                  SizedBox(
                    width: pillWidth / 2,
                    height: _pillHeight,
                    // 规范 §5：按压缩到 0.97、释放回 1.0，提交中淡到 0.38 且
                    // 点击无动画。点击仍由 FilledButton 的 onPressed 处理，
                    // Pressable 不接管手势，避免重复触发登录。
                    child: Pressable(
                      enabled: !_submitting,
                      child: FilledButton(
                        onPressed: _submitting ? null : _submit,
                        style: FilledButton.styleFrom(
                          backgroundColor: pillColor,
                          foregroundColor: textColor,
                          shape: const StadiumBorder(),
                          padding: EdgeInsets.zero,
                          textStyle: _pillTextStyle(textColor),
                        ),
                        child: _submitting
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: textColor,
                                ),
                              )
                            : const Text('login'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
