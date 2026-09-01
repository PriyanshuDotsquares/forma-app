import 'package:flutter/material.dart';

import '../../../../core/design_system/design_system.dart';

/// Small pill chip for a muscle/equipment tag — used across the plan
/// overview, day editor, session preview, exercise library, and the
/// dashboard's "today" card.
class MuscleTagChip extends StatelessWidget {
  const MuscleTagChip(this.label, {super.key, this.selected = false, this.onTap});

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
      decoration: BoxDecoration(
        color: selected ? AppColors.accentBlue : AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(color: selected ? AppColors.accentBlue : AppColors.outlineVariant),
      ),
      child: Text(
        label,
        style: AppTypography.body(
          size: 12,
          weight: FontWeight.w600,
          color: selected ? AppColors.accentBlueDark : AppColors.textSecondary,
        ),
      ),
    );
    if (onTap == null) return chip;
    return GestureDetector(onTap: onTap, child: chip);
  }
}

/// "lower_back" -> "Lower Back"
String titleCaseMuscle(String raw) {
  return raw.split('_').where((w) => w.isNotEmpty).map((w) => '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
}
