import 'package:flutter/material.dart';

import '../../../../core/design_system/design_system.dart';

/// A selectable card used throughout the quiz (goal, experience, gym
/// location, split preference). Mirrors the selected-vs-not styling of
/// `_ModeTab` in the auth screen: `accentBlue` border/fill when selected,
/// `outlineVariant` otherwise, with `accentBlueDark` as the text-on-accent
/// color.
class OnboardingOptionCard extends StatelessWidget {
  const OnboardingOptionCard({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.selected = false,
    this.enabled = true,
    this.disabledReason,
    this.badge,
    this.trailing,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final bool selected;
  final bool enabled;
  final String? disabledReason;
  final String? badge;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Color borderColor = selected ? AppColors.accentBlue : AppColors.outlineVariant;
    final Color fillColor = selected ? AppColors.accentBlue.withValues(alpha: 0.12) : AppColors.surfaceBase;

    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: fillColor,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: borderColor, width: selected ? 1.5 : 1),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (icon != null) ...[
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected ? AppColors.accentBlue : AppColors.surfaceLowest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 20, color: selected ? AppColors.accentBlueDark : AppColors.textSecondary),
                  ),
                  const SizedBox(width: AppSpacing.md),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(title, style: AppTypography.body(size: 15, weight: FontWeight.w600))),
                          if (badge != null) ...[const SizedBox(width: AppSpacing.sm), BadgePill(badge!)],
                        ],
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(subtitle!, style: AppTypography.body(size: 13, color: AppColors.textSecondary)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                if (!enabled && disabledReason != null)
                  SizedBox(
                    width: 96,
                    child: Text(
                      disabledReason!,
                      textAlign: TextAlign.right,
                      style: AppTypography.body(size: 12, weight: FontWeight.w600, color: AppColors.accentAmber),
                    ),
                  )
                else
                  trailing ??
                      Icon(
                        selected ? Icons.check_circle : Icons.radio_button_unchecked,
                        color: selected ? AppColors.accentBlue : AppColors.outline,
                        size: 22,
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
