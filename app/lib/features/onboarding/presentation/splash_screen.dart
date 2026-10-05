import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/design_system.dart';
import '../../auth/presentation/auth_controller.dart';

/// Shown while `AuthController.build()` checks a stored token on launch,
/// and again if that check fails with a network/backend error (not a real
/// "you're signed out" — see the controller's doc comment) so the user can
/// retry without losing their session or being sent to the marketing intro
/// screen as if they needed to sign in again.
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.surfaceLowest,
      body: Center(
        child: authState.hasError
            ? Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: FormaEmptyState(
                  icon: Icons.wifi_off,
                  title: "Couldn't connect.",
                  message: "We couldn't reach FORMA to check your session. Your login is still saved — just try again.",
                  primaryLabel: 'RETRY',
                  onPrimary: () => ref.invalidate(authControllerProvider),
                  bordered: false,
                ),
              )
            : const FormaWordmark(size: 40),
      ),
    );
  }
}
