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

// F26 chunk 3：找回密码页。沿用 F14a/F14b 登录页设计语言——同一渐变底、
// 登录色板 token 胶囊输入与胶囊按钮；不引入新的动画循环（测试可安全 pump）。

/// 与登录页相同的浅色 / 深色渐变底。
const LinearGradient _backgroundLight = LinearGradient(
  begin: Alignment(-0.97, -0.26),
  end: Alignment(0.97, 0.26),
  colors: AppColors.loginBackgroundLightColors,
  stops: [0.0, 0.30, 0.68, 1.0],
);

const LinearGradient _backgroundDark = LinearGradient(
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
  colors: AppColors.loginBackgroundDarkColors,
  stops: [0.0, 0.52, 1.0],
);

const OutlineInputBorder _pillBorder = OutlineInputBorder(
  borderRadius: BorderRadius.all(Radius.circular(999)),
  borderSide: BorderSide.none,
);

const OutlineInputBorder _codeBorder = OutlineInputBorder(
  borderRadius: BorderRadius.all(Radius.circular(20)),
  borderSide: BorderSide.none,
);

const double _fieldMaxWidth = 300;
const double _fieldWidthFactor = 0.72;
const double _fieldGap = 22;
const double _pillHeight = 40;
const double _fieldFontSize = 14;
const double _titleFontSize = 22;
const double _forgotLinkFontSize = 13;

class RecoverPage extends StatefulWidget {
  const RecoverPage({super.key, this.authService});

  /// 测试可注入；生产为 ServiceLocator.authService（提交时才解析）。
  final AuthService? authService;

  @override
  State<RecoverPage> createState() => _RecoverPageState();
}

class _RecoverPageState extends State<RecoverPage> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _phoneFocus = FocusNode();
  final _codeFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmFocus = FocusNode();
  String? _phoneError;
  String? _codeError;
  String? _passwordError;
  String? _confirmError;
  bool _submitting = false;

  static final RegExp _phoneRegExp = RegExp(r'^1[3-9]\d{9}$');

  @override
  void initState() {
    super.initState();
    _phoneFocus.addListener(_onFocusChange);
    _codeFocus.addListener(_onFocusChange);
    _passwordFocus.addListener(_onFocusChange);
    _confirmFocus.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    setState(() {});
  }

  @override
  void dispose() {
    _phoneFocus.removeListener(_onFocusChange);
    _codeFocus.removeListener(_onFocusChange);
    _passwordFocus.removeListener(_onFocusChange);
    _confirmFocus.removeListener(_onFocusChange);
    _phoneFocus.dispose();
    _codeFocus.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    _phoneController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
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

  String? _validateCode(String value) {
    if (value.isEmpty) {
      return '请输入 12 词恢复码';
    }
    return null;
  }

  String? _validatePassword(String value) {
    if (value.isEmpty) {
      return '请输入新密码';
    }
    // 服务端规则：密码 6–72 **字节**（中文等多字节字符按字节算）。
    final bytes = utf8.encode(value).length;
    if (bytes < 6 || bytes > 72) {
      return '密码长度需为 6-72 字节';
    }
    return null;
  }

  String? _validateConfirm(String value, String password) {
    if (value != password) {
      return '两次输入的密码不一致';
    }
    return null;
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final phone = _phoneController.text.trim();
    final code = _codeController.text.trim();
    final password = _passwordController.text;
    final phoneError = _validatePhone(phone);
    final codeError = _validateCode(code);
    final passwordError = _validatePassword(password);
    final confirmError = _validateConfirm(_confirmController.text, password);
    setState(() {
      _phoneError = phoneError;
      _codeError = codeError;
      _passwordError = passwordError;
      _confirmError = confirmError;
    });
    if (phoneError != null ||
        codeError != null ||
        passwordError != null ||
        confirmError != null) {
      return;
    }
    setState(() => _submitting = true);
    final auth = widget.authService ?? ServiceLocator.authService;
    final result = await auth.recover(
      phone: phone,
      restoreCode: code,
      newPassword: password,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (!result.success) {
      // 服务端文案（401 恢复码无效 / 422 格式）或网络错误；留在本页可重试。
      showAppSnackBar(context, result.message ?? '找回密码失败', aboveNav: false);
      return;
    }
    final restoreCode = result.restoreCode;
    if (restoreCode != null && restoreCode.isNotEmpty) {
      // 旧恢复码已被消耗：新码只显示这一次，必须让用户看到并存下。
      await _showNewRestoreCode(restoreCode);
      if (!mounted) return;
    }
    // 与登录成功一致：后台同步不阻塞进首页。
    unawaited(_syncAfterLogin());
    if (!mounted) return;
    // 找回即登录：清掉登录页在内的旧路由栈，直接进首页。
    Navigator.of(context)
        .pushNamedAndRemoveUntil(AppRoutes.home, (route) => false);
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
      // 同上，同步失败不影响找回结果。
    }
  }

  Future<void> _showNewRestoreCode(String code) async {
    await showAppDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('请保存新恢复码'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '密码已重置并登录成功。旧恢复码已失效，下面是新的 12 词恢复码，只显示这一次；下次忘记密码凭它找回，请立即抄下或复制保存。',
              ),
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

  TextStyle _fieldTextStyle(Color color) {
    return TextStyle(
      fontSize: _fieldFontSize,
      fontWeight: FontWeight.w600,
      height: 1.0,
      color: color,
    );
  }

  Widget _buildField({
    required Key fieldKey,
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
    int maxLines = 1,
    bool isCodeField = false,
  }) {
    // 与登录页一致：聚焦即隐藏占位符；错误走 InputDecoration.errorText。
    final border = isCodeField ? _codeBorder : _pillBorder;
    final decoration = InputDecoration(
      hintText: focusNode.hasFocus ? null : hint,
      hintStyle: _fieldTextStyle(textColor),
      errorText: errorText,
      errorStyle: TextStyle(fontSize: 10, color: errorColor),
      filled: true,
      fillColor: pillColor,
      isDense: true,
      contentPadding: EdgeInsets.symmetric(
        horizontal: 17,
        vertical: isCodeField ? 12 : (_pillHeight - _fieldFontSize) / 2,
      ),
      border: border,
      enabledBorder: border,
      focusedBorder: border,
      errorBorder: border,
      focusedErrorBorder: border,
    );
    return SizedBox(
      width: width,
      child: ErrorShake(
        hasError: errorText != null,
        child: TextField(
          key: fieldKey,
          controller: controller,
          focusNode: focusNode,
          obscureText: obscureText,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          onSubmitted: onSubmitted,
          maxLines: maxLines,
          textAlign: isCodeField ? TextAlign.left : TextAlign.center,
          textAlignVertical: TextAlignVertical.center,
          style: _fieldTextStyle(textColor),
          decoration: decoration,
        ),
      ),
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
    final fieldWidth = math.min(
      MediaQuery.sizeOf(context).width * _fieldWidthFactor,
      _fieldMaxWidth,
    );

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: isDark ? _backgroundDark : _backgroundLight,
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 19),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton(
                  key: const Key('recover-back'),
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back),
                  color: textColor,
                ),
                Center(
                  child: Column(
                    children: [
                      const SizedBox(height: 8),
                      Text(
                        '找回密码',
                        style: TextStyle(
                          fontSize: _titleFontSize,
                          fontWeight: FontWeight.w700,
                          height: 1.1,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '输入注册手机号与 12 词恢复码，设置新密码',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: _forgotLinkFontSize,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(height: _fieldGap + 8),
                      _buildField(
                        fieldKey: const Key('recover-phone'),
                        controller: _phoneController,
                        focusNode: _phoneFocus,
                        hint: '手机号码',
                        width: fieldWidth,
                        pillColor: pillColor,
                        textColor: textColor,
                        errorColor: errorColor,
                        errorText: _phoneError,
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: _fieldGap),
                      _buildField(
                        fieldKey: const Key('recover-code'),
                        controller: _codeController,
                        focusNode: _codeFocus,
                        hint: '12 词恢复码（空格分隔）',
                        width: fieldWidth,
                        pillColor: pillColor,
                        textColor: textColor,
                        errorColor: errorColor,
                        errorText: _codeError,
                        maxLines: 2,
                        isCodeField: true,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: _fieldGap),
                      _buildField(
                        fieldKey: const Key('recover-password'),
                        controller: _passwordController,
                        focusNode: _passwordFocus,
                        hint: '新密码（6-72 字节）',
                        width: fieldWidth,
                        pillColor: pillColor,
                        textColor: textColor,
                        errorColor: errorColor,
                        errorText: _passwordError,
                        obscureText: true,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: _fieldGap),
                      _buildField(
                        fieldKey: const Key('recover-confirm'),
                        controller: _confirmController,
                        focusNode: _confirmFocus,
                        hint: '确认新密码',
                        width: fieldWidth,
                        pillColor: pillColor,
                        textColor: textColor,
                        errorColor: errorColor,
                        errorText: _confirmError,
                        obscureText: true,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _submit(),
                      ),
                      const SizedBox(height: _fieldGap + 8),
                      SizedBox(
                        width: fieldWidth / 2,
                        height: _pillHeight,
                        child: Pressable(
                          enabled: !_submitting,
                          child: FilledButton(
                            key: const Key('recover-submit'),
                            onPressed: _submitting ? null : _submit,
                            style: FilledButton.styleFrom(
                              backgroundColor: pillColor,
                              foregroundColor: textColor,
                              shape: const StadiumBorder(),
                              padding: EdgeInsets.zero,
                              textStyle: _fieldTextStyle(textColor),
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
                                : const Text('重置密码'),
                          ),
                        ),
                      ),
                    ],
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
