import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../app_spacing.dart';
import '../app_typography.dart';

/// The recurring "WORKOUTS 148" / "VOLUME 1.24M kg" stat card used across
/// the dashboard, progress hub, and achievements header.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.delta,
    this.deltaPositive = true,
  });

  final String label;
  final String value;
  final String? unit;
  final String? delta;
  final bool deltaPositive;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceBase,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: AppTypography.body(size: 11, weight: FontWeight.w700, color: AppColors.textMuted).copyWith(letterSpacing: 1.0),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  value,
                  style: AppTypography.mono(size: 26, weight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (unit != null) ...[
                const SizedBox(width: 4),
                Text(unit!, style: AppTypography.body(size: 13, color: AppColors.textSecondary)),
              ],
              if (delta != null) ...[
                const SizedBox(width: 8),
                Text(
                  delta!,
                  style: AppTypography.mono(size: 13, weight: FontWeight.w600, color: deltaPositive ? AppColors.accentGreen : AppColors.accentRed),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
