import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../app_spacing.dart';
import '../app_typography.dart';

/// Shared empty/error-state card — covers "No plan yet", "Nothing logged
/// yet", "No search results", "You're offline", "Camera access is off",
/// and the generic "That didn't work" error, all of which share one layout
/// in the design: icon, title, subtitle, primary action, optional secondary
/// action, optional small caption/eyebrow above.
class FormaEmptyState extends StatelessWidget {
  const FormaEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.eyebrow,
    this.primaryLabel,
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.iconColor,
    this.bordered = true,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? eyebrow;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final Color? iconColor;
  final bool bordered;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xxl),
      decoration: bordered
          ? BoxDecoration(
              border: Border.all(color: AppColors.outlineVariant),
              borderRadius: BorderRadius.circular(16),
            )
          : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (eyebrow != null) ...[
            _Eyebrow(eyebrow!),
            const SizedBox(height: AppSpacing.md),
          ],
          Icon(icon, size: 40, color: iconColor ?? AppColors.textMuted),
          const SizedBox(height: AppSpacing.lg),
          Text(title, textAlign: TextAlign.center, style: AppTypography.display(size: 20)),
          const SizedBox(height: AppSpacing.sm),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTypography.body(size: 14, color: AppColors.textSecondary),
          ),
          if (primaryLabel != null) ...[
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton(onPressed: onPrimary, child: Text(primaryLabel!)),
            ),
          ],
          if (secondaryLabel != null) ...[
            const SizedBox(height: AppSpacing.sm),
            TextButton(onPressed: onSecondary, child: Text(secondaryLabel!)),
          ],
        ],
      ),
    );
  }
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: AppTypography.body(size: 11, weight: FontWeight.w700, color: AppColors.textMuted).copyWith(letterSpacing: 1.2),
    );
  }
}
