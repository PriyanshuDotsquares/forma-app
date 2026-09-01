import 'package:flutter/material.dart';

import '../../../../core/design_system/design_system.dart';
import 'progress_card.dart';

/// One row in the progress hub's list of mini-card row-links: a title, an
/// optional subtitle, a small inline preview (sparkline / bars / dot-grid /
/// icon), and a chevron when it navigates somewhere.
class HubRowLink extends StatelessWidget {
  const HubRowLink({
    super.key,
    required this.title,
    this.subtitle,
    required this.preview,
    this.trailingBadge,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final Widget preview;
  final Widget? trailingBadge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ProgressCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title.toUpperCase(),
                        style: AppTypography.body(
                          size: 13,
                          weight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ).copyWith(letterSpacing: 0.6),
                      ),
                    ),
                    if (trailingBadge != null) ...[const SizedBox(width: 6), trailingBadge!],
                  ],
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: AppTypography.body(size: 12, color: AppColors.textSecondary)),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          preview,
          if (onTap != null) ...[
            const SizedBox(width: AppSpacing.xs),
            const Icon(Icons.chevron_right, color: AppColors.textMuted, size: 20),
          ],
        ],
      ),
    );
  }
}
