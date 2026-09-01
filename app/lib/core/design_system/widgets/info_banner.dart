import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../app_spacing.dart';
import '../app_typography.dart';

/// Left-accent-bordered callout used for "SUGGESTION" recovery tips, "FROM
/// YOUR LAST SET" coaching notes, "ONE THING TO FIX" post-set feedback, and
/// "ELBOWS FLARED" form-quality flags.
class InfoBanner extends StatelessWidget {
  const InfoBanner({
    super.key,
    required this.title,
    this.body,
    this.icon,
    this.accent = AppColors.accentBlue,
    this.trailing,
  });

  final String title;
  final String? body;
  final IconData? icon;
  final Color accent;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceBase,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: accent, width: 3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[Icon(icon, size: 18, color: accent), const SizedBox(width: AppSpacing.sm)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.body(size: 14, weight: FontWeight.w700)),
                if (body != null) ...[
                  const SizedBox(height: 2),
                  Text(body!, style: AppTypography.body(size: 13, color: AppColors.textSecondary)),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
