import 'package:flutter/material.dart';

import '../../core/app_snackbar.dart';
import '../../core/service_locator.dart';
import '../../core/theme.dart';
import '../../router/app_router.dart';
import '../../widgets/route_pass_logo.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  String? _phoneError;
  String? _passwordError;

  static final RegExp _phoneRegExp = RegExp(r'^1[3-9]\d{9}$');
  static final RegExp _letterRegExp = RegExp(r'[A-Za-z]');
  static final RegExp _digitRegExp = RegExp(r'[0-9]');

  @override
  void dispose() {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBackgroundLight,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSizes.contentMaxWidth,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.only(
                    top: AppSpacing.pageTop,
                    left: AppSpacing.pageHorizontal,
                    right: AppSpacing.pageHorizontal,
                    bottom: AppSpacing.pageBottom,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight:
                          constraints.maxHeight -
                          AppSpacing.pageTop -
                          AppSpacing.pageBottom,
                    ),
                    child: IntrinsicHeight(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Center(
                            child: RoutePassLogo(size: AppSizes.logo),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          Text(
                            '欢迎回来',
                            textAlign: TextAlign.center,
                            style: AppTheme.brandTitleStyle,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            '登录后开始刷题（演示模式，不会发送任何请求）',
                            textAlign: TextAlign.center,
                            style: AppTheme.brandSubtitleStyle,
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          _LoginTextField(
                            label: '手机号码',
                            hint: '请输入 11 位手机号码',
                            controller: _phoneController,
                            errorText: _phoneError,
                            keyboardType: TextInputType.phone,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [
                              AutofillHints.telephoneNumber,
                            ],
                          ),
                          const SizedBox(height: AppSpacing.formBlock),
                          _LoginTextField(
                            label: '密码',
                            hint: '8–32 位，含字母与数字',
                            controller: _passwordController,
                            errorText: _passwordError,
                            obscureText: _obscurePassword,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _submit(),
                            autofillHints: const [AutofillHints.password],
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                size: AppSizes.icon,
                                color: AppColors.brandCaption,
                              ),
                              tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                          ),
                          const SizedBox(height: AppSpacing.formBlock),
                          SizedBox(
                            height: AppSizes.buttonHeight,
                            child: FilledButton(
                              onPressed: _submit,
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.brandPrimary,
                                foregroundColor: AppColors.brandOnPrimary,
                                textStyle: AppTheme.brandButtonStyle,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    AppRadii.button,
                                  ),
                                ),
                              ),
                              child: const Text('登录 / 注册'),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xxl),
                          const Spacer(),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: AppSpacing.md,
                            children: [
                              _LoginLink(
                                label: '先看看知识库',
                                route: AppRoutes.knowledge,
                              ),
                              _LoginLink(
                                label: '打开工具箱',
                                route: AppRoutes.toolbox,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _LoginTextField extends StatelessWidget {
  const _LoginTextField({
    required this.label,
    required this.hint,
    required this.controller,
    this.errorText,
    this.obscureText = false,
    this.suffixIcon,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
    this.autofillHints,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final String? errorText;
  final bool obscureText;
  final Widget? suffixIcon;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final Iterable<String>? autofillHints;

  OutlineInputBorder _border(
    Color color, {
    double width = AppSizes.borderWidth,
  }) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadii.input),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTheme.brandFieldLabelStyle),
        const SizedBox(height: AppSpacing.fieldLabelGap),
        TextField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          style: AppTheme.brandFieldTextStyle,
          textInputAction: textInputAction,
          onSubmitted: onSubmitted,
          autofillHints: autofillHints,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: AppTheme.brandFieldHintStyle,
            errorText: errorText,
            filled: true,
            fillColor: AppColors.brandSurface,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.fieldHorizontal,
              vertical: AppSpacing.fieldVertical,
            ),
            border: _border(AppColors.brandBorder),
            enabledBorder: _border(AppColors.brandBorder),
            focusedBorder: _border(
              AppColors.brandPrimary,
              width: AppSizes.focusedBorderWidth,
            ),
            errorBorder: _border(theme.colorScheme.error),
            focusedErrorBorder: _border(
              theme.colorScheme.error,
              width: AppSizes.focusedBorderWidth,
            ),
            suffixIcon: suffixIcon,
          ),
        ),
      ],
    );
  }
}

class _LoginLink extends StatelessWidget {
  const _LoginLink({required this.label, required this.route});

  final String label;
  final String route;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () => Navigator.of(context).pushNamed(route),
      style: TextButton.styleFrom(
        foregroundColor: AppColors.brandPrimary,
        textStyle: AppTheme.brandLinkStyle,
        minimumSize: Size.zero,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.xs,
        ),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label),
    );
  }
}
