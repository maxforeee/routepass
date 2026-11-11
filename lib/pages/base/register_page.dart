import 'package:flutter/material.dart';

import '../../router/app_router.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _nicknameController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _usernameError;
  String? _passwordError;
  String? _confirmError;
  String? _nicknameError;

  static final RegExp _usernameRegExp = RegExp(r'^[A-Za-z0-9_]{4,20}$');
  static final RegExp _letterRegExp = RegExp(r'[A-Za-z]');
  static final RegExp _digitRegExp = RegExp(r'[0-9]');

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _nicknameController.dispose();
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

  String? _validateNickname(String value) {
    if (value.trim().length > 20) {
      return '昵称最长 20 个字符';
    }
    return null;
  }

  void _submit() {
    final usernameError = _validateUsername(_usernameController.text.trim());
    final passwordError = _validatePassword(_passwordController.text);
    final confirmError = _passwordController.text == _confirmController.text
        ? null
        : '两次输入的密码不一致';
    final nicknameError = _validateNickname(_nicknameController.text);
    setState(() {
      _usernameError = usernameError;
      _passwordError = passwordError;
      _confirmError = confirmError;
      _nicknameError = nicknameError;
    });
    if (usernameError != null ||
        passwordError != null ||
        confirmError != null ||
        nicknameError != null) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('演示注册，后端未接入')));
    Navigator.of(context).pushReplacementNamed(AppRoutes.home);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('注册')),
      body: SafeArea(
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
              textInputAction: TextInputAction.next,
              onChanged: (_) {
                if (_confirmError != null) {
                  setState(() {
                    _confirmError = null;
                  });
                }
              },
              autofillHints: const [AutofillHints.newPassword],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _confirmController,
              obscureText: _obscureConfirm,
              decoration: InputDecoration(
                labelText: '确认密码',
                hintText: '再次输入密码',
                errorText: _confirmError,
                prefixIcon: const Icon(Icons.lock_reset_outlined),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureConfirm
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  tooltip: _obscureConfirm ? '显示密码' : '隐藏密码',
                  onPressed: () {
                    setState(() {
                      _obscureConfirm = !_obscureConfirm;
                    });
                  },
                ),
              ),
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.newPassword],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nicknameController,
              decoration: InputDecoration(
                labelText: '昵称（可选）',
                hintText: '最长 20 个字符',
                errorText: _nicknameError,
                prefixIcon: const Icon(Icons.badge_outlined),
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _submit,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: const Text('注册'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('已有账号？返回登录'),
            ),
          ],
        ),
      ),
    );
  }
}
