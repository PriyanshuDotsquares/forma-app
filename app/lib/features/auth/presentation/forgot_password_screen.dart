import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/app_router.dart';
import 'auth_controller.dart';

/// Requests a password-reset code. No SMTP is configured on this backend,
/// so the API echoes the reset token directly in its response instead of
/// emailing it (`debug_token` — see `AuthRepository.requestPasswordReset`)
/// — surfaced here as an explicitly-labeled dev-mode panel rather than
/// pretending an email went out. Once real SMTP is wired up server-side,
/// `debugToken` comes back null and this panel simply stops appearing.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _loading = false;
  String? _message;
  String? _debugToken;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await ref.read(authRepositoryProvider).requestPasswordReset(_emailController.text.trim());
      if (!mounted) return;
      setState(() {
        _loading = false;
        _message = result.message;
        _debugToken = result.debugToken;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is ApiException ? e.message : 'Something went wrong. Please try again.';
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
                Text('Forgot your password?', style: AppTypography.display(size: 26)),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  "Enter your account email and we'll send you a reset code.",
                  style: AppTypography.body(size: 15, color: AppColors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.xl),
                const SectionLabel('EMAIL'),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  enabled: !_loading,
                  decoration: const InputDecoration(hintText: 'you@example.com'),
                  validator: (value) {
                    if (value == null || !value.contains('@')) return 'Enter a valid email';
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.lg),
                if (_error != null) ...[
                  InfoBanner(title: 'Could not send reset code', body: _error, accent: AppColors.error, icon: Icons.error_outline),
                  const SizedBox(height: AppSpacing.lg),
                ],
                if (_message != null) ...[
                  InfoBanner(title: _message!, accent: AppColors.accentGreen, icon: Icons.mark_email_read_outlined),
                  const SizedBox(height: AppSpacing.md),
                ],
                if (_debugToken != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceHigh,
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      border: Border.all(color: AppColors.accentAmber),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'DEV MODE — NO EMAIL SERVICE CONFIGURED',
                          style: AppTypography.body(size: 11, weight: FontWeight.w700, color: AppColors.accentAmber).copyWith(letterSpacing: 0.8),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "This code would normally be emailed to you. It's shown here instead so you can finish the flow.",
                          style: AppTypography.body(size: 12, color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        SelectableText(_debugToken!, style: AppTypography.mono(size: 13)),
                        const SizedBox(height: AppSpacing.sm),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: () => context.push('${AppRoutes.resetPassword}?token=$_debugToken'),
                            child: const Text('Enter reset code'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
                if (_message == null)
                  FilledButton(
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Send reset code'),
                  ),
                if (_message != null && _debugToken == null)
                  OutlinedButton(
                    onPressed: () => context.push(AppRoutes.resetPassword),
                    child: const Text('I have a code'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
