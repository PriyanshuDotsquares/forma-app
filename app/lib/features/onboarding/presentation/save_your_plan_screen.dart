import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/router/app_router.dart';
import '../../auth/presentation/auth_controller.dart';
import 'onboarding_controller.dart';

/// Shown once, right after `PlanPreviewScreen`'s "Looks good" — a closing
/// beat before landing on `/today`.
///
/// This app already requires a real account *before* onboarding starts (see
/// the router redirect in `core/router/app_router.dart`), so by the time
/// someone reaches this screen their plan is already persisted to a real,
/// logged-in account — there's no pending "create account" step left to
/// honestly gate behind Apple/Google/email. Apple and Google are shown as
/// stubs (matching the same "coming soon" convention used for Notifications
/// and Language in Settings) since wiring them for real needs OAuth
/// credentials this project doesn't have; "Continue with email" and the
/// "not now" link below it are both real and do the same thing — they're
/// simply the confirmation that the account already covers this.
class SaveYourPlanScreen extends ConsumerWidget {
  const SaveYourPlanScreen({super.key});

  void _showComingSoon(BuildContext context, String provider) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$provider sign-in coming soon.')));
  }

  void _showLegalComingSoon(BuildContext context, String document) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$document coming soon.')));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final answers = ref.watch(onboardingControllerProvider);
    final splitLabel = answers.splitPreference
        .split('_')
        .where((s) => s.isNotEmpty)
        .map((s) => s.toUpperCase())
        .join(' / ');

    void continueWithEmail() {
      final email = ref.read(authControllerProvider).valueOrNull?.email;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(email == null ? 'Saved to your account.' : 'Saved to $email.')),
      );
      // Done with the post-onboarding detour — let the router send future
      // auth-state refreshes straight to /today again.
      ref.read(onboardingPostFlowActiveProvider.notifier).state = false;
      context.go(AppRoutes.today);
    }

    return Scaffold(
      backgroundColor: AppColors.surfaceLowest,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.lg),
              decoration: const BoxDecoration(
                color: AppColors.surfaceHigh,
                borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: AppSpacing.lg),
                      decoration: BoxDecoration(color: AppColors.outline, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  if (splitLabel.isNotEmpty)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceHighest,
                          borderRadius: BorderRadius.circular(AppRadius.field),
                        ),
                        child: Text(
                          splitLabel.replaceAll(' / ', '\n'),
                          style: AppTypography.mono(size: 12, color: AppColors.textSecondary),
                        ),
                      ),
                    ),
                  const SizedBox(height: AppSpacing.md),
                  Text('Save your plan.', style: AppTypography.display(size: 32)),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Your plan and every workout are saved to your account — they\'ll follow you across devices.',
                    style: AppTypography.body(size: 15, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  OutlinedButton.icon(
                    onPressed: () => _showComingSoon(context, 'Apple'),
                    icon: const Icon(Icons.apple),
                    label: const Text('Continue with Apple'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  OutlinedButton.icon(
                    onPressed: () => _showComingSoon(context, 'Google'),
                    icon: const Text('G', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF4285F4))),
                    label: const Text('Continue with Google'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      const Expanded(child: Divider(color: AppColors.outlineVariant)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                        child: Text('OR', style: AppTypography.body(size: 12, color: AppColors.textMuted)),
                      ),
                      const Expanded(child: Divider(color: AppColors.outlineVariant)),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  OutlinedButton(onPressed: continueWithEmail, child: const Text('Continue with email')),
                  const SizedBox(height: AppSpacing.lg),
                  Center(
                    child: TextButton(
                      onPressed: continueWithEmail,
                      child: Text(
                        'NOT NOW — KEEP IT ON THIS DEVICE ONLY',
                        style: AppTypography.body(size: 11, weight: FontWeight.w700, color: AppColors.textMuted).copyWith(letterSpacing: 0.6),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Center(
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      children: [
                        Text('By continuing you agree to our ', style: AppTypography.body(size: 12, color: AppColors.textMuted)),
                        GestureDetector(
                          onTap: () => _showLegalComingSoon(context, 'Terms'),
                          child: Text('Terms', style: AppTypography.body(size: 12, weight: FontWeight.w600, color: AppColors.accentBlue)),
                        ),
                        Text(' and ', style: AppTypography.body(size: 12, color: AppColors.textMuted)),
                        GestureDetector(
                          onTap: () => _showLegalComingSoon(context, 'Privacy Policy'),
                          child: Text('Privacy Policy', style: AppTypography.body(size: 12, weight: FontWeight.w600, color: AppColors.accentBlue)),
                        ),
                        Text('.', style: AppTypography.body(size: 12, color: AppColors.textMuted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
