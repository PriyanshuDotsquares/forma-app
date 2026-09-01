import 'package:flutter/material.dart';

import '../../../../core/design_system/design_system.dart';
import 'progress_format.dart';

/// The W / M / 3M / Y / ALL chip row used at the top of every progress
/// screen, mapping to backend period strings `week|month|3month|year|all`.
class PeriodSelector extends StatelessWidget {
  const PeriodSelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.options = const ['week', 'month', '3month', 'year', 'all'],
  });

  final String value;
  final ValueChanged<String> onChanged;
  final List<String> options;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final opt in options) ...[
          Expanded(
            child: _PeriodChip(
              label: kPeriodShortLabels[opt] ?? opt.toUpperCase(),
              selected: opt == value,
              onTap: () => onChanged(opt),
            ),
          ),
          if (opt != options.last) const SizedBox(width: AppSpacing.xs),
        ],
      ],
    );
  }
}

class _PeriodChip extends StatelessWidget {
  const _PeriodChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentBlue : AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(AppRadius.chip),
          border: Border.all(color: selected ? AppColors.accentBlue : AppColors.outlineVariant),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: AppTypography.mono(
            size: 12,
            weight: FontWeight.w700,
            color: selected ? AppColors.accentBlueDark : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
