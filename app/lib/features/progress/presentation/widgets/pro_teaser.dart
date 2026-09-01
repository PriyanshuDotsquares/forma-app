import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/router/app_router.dart';
import 'progress_card.dart';

/// Locked-content teaser shown in place of a Pro-gated screen's real content
/// — dimmed placeholder bars behind a centered lock card, rather than a
/// literal blur (cheap to build, reads fine, doesn't fabricate real data
/// behind the lock).
class ProLockedTeaser extends StatelessWidget {
  const ProLockedTeaser({super.key, required this.title, required this.message});

  final String title;
  final String message;

  static const _placeholderBarHeights = [0.4, 0.65, 0.5, 0.8, 0.6, 0.78, 0.55, 0.7];

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Opacity(
          opacity: 0.28,
          child: SizedBox(
            height: 180,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final f in _placeholderBarHeights)
                  Container(
                    width: 16,
                    height: 180 * f,
                    decoration: BoxDecoration(color: AppColors.textMuted, borderRadius: BorderRadius.circular(4)),
                  ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: ProgressCard(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, color: AppColors.accentBlue, size: 28),
                const SizedBox(height: AppSpacing.md),
                Text(title, textAlign: TextAlign.center, style: AppTypography.display(size: 18)),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: AppTypography.body(size: 13, color: AppColors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.lg),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => context.push(AppRoutes.premium),
                    child: const Text('TRY PRO FREE FOR 7 DAYS'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
