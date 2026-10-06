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
            : const _AnimatedWordmark(),
      ),
    );
  }
}

/// The letters of FORMA rise and fade in one after another, then a thin bar
/// fills underneath for the rest of the splash so the wait reads as progress
/// rather than a frozen screen.
class _AnimatedWordmark extends StatefulWidget {
  const _AnimatedWordmark();

  @override
  State<_AnimatedWordmark> createState() => _AnimatedWordmarkState();
}

class _AnimatedWordmarkState extends State<_AnimatedWordmark> with SingleTickerProviderStateMixin {
  static const _letters = ['F', 'O', 'R', 'M', 'A'];

  late final AnimationController _letterController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..forward();

  @override
  void dispose() {
    _letterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = AppTypography.wordmark(size: 40, color: AppColors.textPrimary);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          label: 'FORMA',
          child: ExcludeSemantics(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < _letters.length; i++)
                  AnimatedBuilder(
                    animation: _letterController,
                    builder: (context, child) {
                      // Each letter owns a window of the timeline, overlapping
                      // its neighbours so the motion flows rather than steps.
                      final start = i * 0.12;
                      final t = Curves.easeOutCubic.transform(
                        ((_letterController.value - start) / 0.52).clamp(0.0, 1.0),
                      );
                      return Opacity(
                        opacity: t,
                        child: Transform.translate(offset: Offset(0, 16 * (1 - t)), child: child),
                      );
                    },
                    child: Text(_letters[i], style: style),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        // Fills over the minimum splash time, then holds full if the session
        // check is still running.
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: AuthController.minSplashDuration,
          curve: Curves.easeInOut,
          builder: (context, value, _) => ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: SizedBox(
              width: 96,
              child: LinearProgressIndicator(
                value: value,
                minHeight: 3,
                backgroundColor: AppColors.surfaceHighest,
                color: AppColors.accentBlue,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
