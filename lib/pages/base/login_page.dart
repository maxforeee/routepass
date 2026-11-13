import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/app_snackbar.dart';
import '../../core/service_locator.dart';
import '../../core/theme.dart';
import '../../router/app_router.dart';

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

const double _graphicTop = 78;
const double _graphicHeight = 230;
const double _graphicToTitle = 52;
const double _titleToPill = 64;
const double _pillGap = 38;
const double _pillHeight = 64;
const double _pillMaxWidth = 322;
const double _pillWidthFactor = 0.82;
const double _pillFontSize = 27;
const double _titleFontSize = 46;

const double _blobWidth = 235;
const double _blobHeight = 205;
const double _blobBumpSize = 92;
const double _blobBumpOverhang = 30;
const double _blobBumpTop = 52;
const double _blobFloatRange = 14;
const double _blobTilt = 1.5 * math.pi / 180;

/// 参考稿 border-radius 48% 52% 46% 54% / 58% 60% 40% 42%（235x205）。
const BorderRadius _blobRadiusA = BorderRadius.only(
  topLeft: Radius.elliptical(112.8, 118.9),
  topRight: Radius.elliptical(122.2, 123.0),
  bottomRight: Radius.elliptical(108.1, 82.0),
  bottomLeft: Radius.elliptical(126.9, 86.1),
);

/// 形变目标 55% 45% 52% 48% / 50% 55% 45% 50%。
const BorderRadius _blobRadiusB = BorderRadius.only(
  topLeft: Radius.elliptical(129.25, 102.5),
  topRight: Radius.elliptical(105.75, 112.75),
  bottomRight: Radius.elliptical(122.2, 92.25),
  bottomLeft: Radius.elliptical(112.8, 102.5),
);

const double _clusterWidth = 210;
const double _clusterHeight = 180;
const double _clusterFloatRange = 10;
const double _bubbleBobRange = 9;
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
  _BubbleSpec(88, 0, 52, 0),
  _BubbleSpec(64, 58, 8, 0.5),
  _BubbleSpec(76, 82, 38, 1.0),
  _BubbleSpec(58, 138, 0, 1.4),
  _BubbleSpec(66, 142, 66, 0.8),
  _BubbleSpec(60, 96, 104, 1.8),
  _BubbleSpec(44, 44, 120, 2.2),
];

const OutlineInputBorder _pillBorder = OutlineInputBorder(
  borderRadius: BorderRadius.all(Radius.circular(999)),
  borderSide: BorderSide.none,
);

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

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

  late final AnimationController _blobFloat;
  late final AnimationController _blobMorph;
  late final AnimationController _clusterFloat;
  late final AnimationController _bubbleBob;
  late final Animation<double> _blobFloatCurve;
  late final Animation<double> _blobMorphCurve;
  late final Animation<double> _clusterFloatCurve;

  static final RegExp _phoneRegExp = RegExp(r'^1[3-9]\d{9}$');
  static final RegExp _letterRegExp = RegExp(r'[A-Za-z]');
  static final RegExp _digitRegExp = RegExp(r'[0-9]');

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
    if (value.length < 8 || value.length > 32) {
      return '密码长度需为 8-32 位';
    }
    if (!_letterRegExp.hasMatch(value) || !_digitRegExp.hasMatch(value)) {
      return '密码需同时包含字母和数字';
    }
    return null;
  }

  Future<void> _submit() async {
    final phoneError = _validatePhone(_phoneController.text.trim());
    final passwordError = _validatePassword(_passwordController.text);
    setState(() {
      _phoneError = phoneError;
      _passwordError = passwordError;
    });
    if (phoneError != null || passwordError != null) {
      return;
    }
    final result = await ServiceLocator.authService.login(
      username: _phoneController.text.trim(),
      password: _passwordController.text,
    );
    if (!mounted) return;
    if (!result.success) {
      showAppSnackBar(context, result.message ?? '登录失败');
      return;
    }
    showAppSnackBar(context, '演示登录，后端未接入', aboveNav: false);
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(AppRoutes.home);
  }

  TextStyle _pillTextStyle(Color color) {
    return TextStyle(
      fontSize: _pillFontSize,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
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
    final decoration = InputDecoration(
      hintText: focusNode.hasFocus ? null : hint,
      hintStyle: _pillTextStyle(textColor),
      errorText: errorText,
      errorStyle: TextStyle(fontSize: 12, color: errorColor),
      filled: true,
      fillColor: pillColor,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 28,
        vertical: (_pillHeight - _pillFontSize) / 2,
      ),
      border: _pillBorder,
      enabledBorder: _pillBorder,
      focusedBorder: _pillBorder,
      errorBorder: _pillBorder,
      focusedErrorBorder: _pillBorder,
    );
    return SizedBox(
      width: width,
      child: TextField(
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
            child: SizedBox(
              width: _blobWidth + _blobBumpOverhang,
              height: _blobHeight,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: _blobBumpOverhang,
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
                    left: 0,
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
                            offset: Offset(0, 6),
                            blurRadius: 14,
                          ),
                        ],
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

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: isDark ? _backgroundDark : _backgroundLight,
        ),
        child: SafeArea(
          top: true,
          bottom: false,
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              top: math.max(0.0, _graphicTop - topInset),
              bottom: 24,
            ),
            child: Column(
              children: [
                SizedBox(
                  height: _graphicHeight,
                  child: Center(child: isDark ? _buildBubbles() : _buildBlob()),
                ),
                const SizedBox(height: _graphicToTitle),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'login in / sign up',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: _titleFontSize,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
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
                  child: FilledButton(
                    onPressed: _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: pillColor,
                      foregroundColor: textColor,
                      shape: const StadiumBorder(),
                      padding: EdgeInsets.zero,
                      textStyle: _pillTextStyle(textColor),
                    ),
                    child: const Text('login'),
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
