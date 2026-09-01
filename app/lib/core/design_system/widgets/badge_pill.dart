import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../app_typography.dart';

/// Small pill badge: "PRO", "NEW", "2 PR", "OFFLINE" status chips.
class BadgePill extends StatelessWidget {
  const BadgePill(this.text, {super.key, this.color = AppColors.accentBlue, this.onColor, this.outlined = false});

  final String text;
  final Color color;
  final Color? onColor;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: outlined ? Colors.transparent : color,
        borderRadius: BorderRadius.circular(100),
        border: outlined ? Border.all(color: color) : null,
      ),
      child: Text(
        text.toUpperCase(),
        style: AppTypography.body(
          size: 10,
          weight: FontWeight.w700,
          color: outlined ? color : (onColor ?? AppColors.accentBlueDark),
        ).copyWith(letterSpacing: 0.6),
      ),
    );
  }
}
