import 'package:flutter/material.dart';

import '../../core/app_snackbar.dart';
import '../../core/service_locator.dart';
import '../../router/app_router.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscurePassword = true;
  String? _usernameError;
  String? _passwordError;

  static final RegExp _usernameRegExp = RegExp(r'^[A-Za-z0-9_]{4,20}$');
  static final RegExp _letterRegExp = RegExp(r'[A-Za-z]');
  static final RegExp _digitRegExp = RegExp(r'[0-9]');

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String? _validateUsername(String value) {
    if (value.isEmpty) {
      return '请输入用户名';
    }
    if (!_usernameRegExp.hasMatch(value)) {
      return '用户名需为 4-20 位字母、数字或下划线';
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
    final usernameError = _validateUsername(_usernameController.text.trim());
    final passwordError = _validatePassword(_passwordController.text);
    setState(() {
      _usernameError = usernameError;
      _passwordError = passwordError;
    });
    if (usernameError != null || passwordError != null) {
      return;
    }
    final result = await ServiceLocator.authService.login(
      username: _usernameController.text.trim(),
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
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('登录')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            children: [
              TextField(
                controller: _usernameController,
                decoration: InputDecoration(
                  labelText: '用户名',
                  hintText: '4-20 位字母、数字或下划线',
                  errorText: _usernameError,
                  prefixIcon: const Icon(Icons.person_outline),
                ),
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.username],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: '密码',
                  hintText: '8-32 位，需包含字母和数字',
                  errorText: _passwordError,
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  ),
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                autofillHints: const [AutofillHints.password],
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _submit,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text('登录'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pushNamed(AppRoutes.register),
                child: const Text('没有账号？去注册'),
              ),
              const SizedBox(height: 16),
              Text(
                '演示登录，后端未接入',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
