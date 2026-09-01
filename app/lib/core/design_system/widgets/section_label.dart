import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../app_typography.dart';

/// Small uppercase muted section heading ("TRAINING", "RECENT", "AUGUST").
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      text.toUpperCase(),
      style: AppTypography.body(size: 12, weight: FontWeight.w700, color: AppColors.textMuted).copyWith(letterSpacing: 1.2),
    );
    if (trailing == null) return label;
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [label, trailing!]);
  }
}
