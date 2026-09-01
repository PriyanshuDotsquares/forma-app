import 'package:flutter/material.dart';

import '../../../../core/design_system/design_system.dart';

/// One row in the profile screen's navigation list: leading icon, label,
/// an optional trailing value/badge, and a chevron (unless [showChevron]
/// is false, e.g. for a row that opens an info dialog rather than drilling
/// into another screen).
class ProfileNavRow extends StatelessWidget {
  const ProfileNavRow({
    super.key,
    required this.icon,
    required this.label,
    this.trailingText,
    this.trailing,
    this.showChevron = true,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String? trailingText;
  final Widget? trailing;
  final bool showChevron;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Row(
            children: [
              Icon(icon, size: 20, color: AppColors.textSecondary),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: Text(label, style: AppTypography.body(size: 15, weight: FontWeight.w600))),
              if (trailingText != null) ...[
                Text(trailingText!, style: AppTypography.mono(size: 13, color: AppColors.textSecondary)),
                const SizedBox(width: AppSpacing.sm),
              ],
              if (trailing != null) ...[trailing!, const SizedBox(width: AppSpacing.sm)],
              if (showChevron) const Icon(Icons.chevron_right, size: 20, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
