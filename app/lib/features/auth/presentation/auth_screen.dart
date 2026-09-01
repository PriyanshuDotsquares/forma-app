import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/app_router.dart';
import '../../../l10n/generated/app_localizations.dart';
import 'auth_controller.dart';

enum _Mode { signUp, signIn }

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  _Mode _mode = _Mode.signUp;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  double get _passwordStrength {
    final p = _passwordController.text;
    if (p.isEmpty) return 0;
    var score = 0;
    if (p.length >= 8) score++;
    if (RegExp(r'[0-9]').hasMatch(p)) score++;
    if (RegExp(r'[A-Z]').hasMatch(p) && RegExp(r'[a-z]').hasMatch(p)) score++;
    return score / 3;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _error = null);

    final auth = ref.read(authControllerProvider.notifier);
    try {
      if (_mode == _Mode.signUp) {
        await auth.register(email: _emailController.text.trim(), password: _passwordController.text);
      } else {
        await auth.login(email: _emailController.text.trim(), password: _passwordController.text);
      }
      if (!mounted) return; // router already navigated away on success — nothing left to update
      final state = ref.read(authControllerProvider);
      if (state.hasError) throw state.error!;
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e is ApiException ? e.message : 'Something went wrong. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final loading = authState.isLoading;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(l10n.createAccountTitle),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(AppRadius.button),
                  ),
                  child: Row(
                    children: [
                      Expanded(child: _ModeTab(label: l10n.signUpTab, selected: _mode == _Mode.signUp, onTap: () => setState(() => _mode = _Mode.signUp))),
                      Expanded(child: _ModeTab(label: l10n.signInTab, selected: _mode == _Mode.signIn, onTap: () => setState(() => _mode = _Mode.signIn))),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                SectionLabel(l10n.emailLabel),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: InputDecoration(
                    hintText: 'you@example.com',
                    errorText: _error != null && _mode == _Mode.signUp ? _error : null,
                    suffixIcon: _error != null && _mode == _Mode.signUp
                        ? const Icon(Icons.error, color: AppColors.error, size: 18)
                        : null,
                  ),
                  validator: (value) {
                    if (value == null || !value.contains('@')) return 'Enter a valid email';
                    return null;
                  },
                  onChanged: (_) => setState(() {}),
                ),
                if (_error != null && _mode == _Mode.signUp) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(_error!, style: AppTypography.body(size: 12, color: AppColors.error)),
                ],
                const SizedBox(height: AppSpacing.lg),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    SectionLabel(l10n.passwordLabel),
                    if (_mode == _Mode.signUp && _passwordController.text.isNotEmpty)
                      Text(
                        _passwordStrength >= 1
                            ? l10n.passwordStrong
                            : _passwordStrength >= 0.66
                            ? l10n.passwordGood
                            : l10n.passwordWeak,
                        style: AppTypography.body(
                          size: 12,
                          weight: FontWeight.w600,
                          color: _passwordStrength >= 0.66 ? AppColors.accentGreen : AppColors.accentAmber,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.length < 8) return 'At least 8 characters';
                    return null;
                  },
                  onChanged: (_) => setState(() {}),
                ),
                if (_mode == _Mode.signUp) ...[
                  const SizedBox(height: AppSpacing.sm),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: _passwordStrength,
                      minHeight: 4,
                      backgroundColor: AppColors.surfaceHighest,
                      color: _passwordStrength >= 0.66 ? AppColors.accentGreen : AppColors.accentAmber,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _RequirementRow(label: l10n.passwordReq8Chars, met: _passwordController.text.length >= 8),
                  const SizedBox(height: 4),
                  _RequirementRow(label: l10n.passwordReqNumber, met: RegExp(r'[0-9]').hasMatch(_passwordController.text)),
                ],
                if (_error != null && _mode == _Mode.signIn) ...[
                  const SizedBox(height: AppSpacing.md),
                  InfoBanner(title: 'Sign-in failed', body: _error, accent: AppColors.error, icon: Icons.error_outline),
                ],
                const SizedBox(height: AppSpacing.xl),
                FilledButton(
                  onPressed: loading ? null : _submit,
                  child: loading
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(_mode == _Mode.signUp ? l10n.createAccountButton : l10n.signInButton),
                ),
                if (_mode == _Mode.signUp) ...[
                  const SizedBox(height: AppSpacing.md),
                  Center(
                    child: Text(
                      l10n.verificationNotice,
                      style: AppTypography.body(size: 12, color: AppColors.textMuted),
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                Center(
                  child: TextButton(
                    onPressed: () => context.push(AppRoutes.forgotPassword),
                    child: Text(l10n.forgotPassword),
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

class _RequirementRow extends StatelessWidget {
  const _RequirementRow({required this.label, required this.met});

  final String label;
  final bool met;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          met ? Icons.check_circle : Icons.radio_button_unchecked,
          size: 16,
          color: met ? AppColors.accentGreen : AppColors.outline,
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(label, style: AppTypography.body(size: 13, color: met ? AppColors.accentGreen : AppColors.textSecondary)),
      ],
    );
  }
}

class _ModeTab extends StatelessWidget {
  const _ModeTab({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.button - 4),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: AppTypography.body(
            size: 13,
            weight: FontWeight.w700,
            color: selected ? AppColors.accentBlueDark : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
