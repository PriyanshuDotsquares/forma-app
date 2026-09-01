import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/app_router.dart';
import 'auth_controller.dart';

class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key, this.initialToken});

  final String? initialToken;

  @override
  ConsumerState<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _tokenController = TextEditingController(text: widget.initialToken ?? '');
  final _passwordController = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _tokenController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).confirmPasswordReset(
        token: _tokenController.text.trim(),
        newPassword: _passwordController.text,
      );
      if (!mounted) return;
      context.go(AppRoutes.auth);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password reset — sign in with your new password.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is ApiException ? e.message : 'That reset code is invalid or has expired.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(leading: const BackButton(), title: const Text('RESET PASSWORD')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Choose a new password.', style: AppTypography.display(size: 26)),
                const SizedBox(height: AppSpacing.xl),
                const SectionLabel('RESET CODE'),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _tokenController,
                  enabled: !_loading,
                  decoration: const InputDecoration(hintText: 'Paste your reset code'),
                  validator: (value) => (value == null || value.trim().isEmpty) ? 'Enter your reset code' : null,
                ),
                const SizedBox(height: AppSpacing.lg),
                const SectionLabel('NEW PASSWORD'),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscure,
                  enabled: !_loading,
                  decoration: InputDecoration(
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (value) => (value == null || value.length < 8) ? 'At least 8 characters' : null,
                ),
                const SizedBox(height: AppSpacing.lg),
                if (_error != null) ...[
                  InfoBanner(title: 'Could not reset password', body: _error, accent: AppColors.error, icon: Icons.error_outline),
                  const SizedBox(height: AppSpacing.lg),
                ],
                FilledButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Reset password'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
