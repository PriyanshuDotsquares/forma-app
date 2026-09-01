import 'package:flutter/material.dart';

import '../app_colors.dart';

/// The barbell-sleeve "load strip": a segmented progress bar where each
/// completed segment is colored like a competition plate, drawn right-to-
/// left as sets are logged (`0/18`, `8/18`, `18/18` in the style guide).
class LoadStrip extends StatelessWidget {
  const LoadStrip({super.key, required this.total, required this.completed, this.height = 8});

  final int total;
  final int completed;
  final double height;

  static const _plateColors = [AppColors.accentRed, AppColors.accentBlue, AppColors.accentGreen, AppColors.accentWhite];

  @override
  Widget build(BuildContext context) {
    if (total <= 0) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: Row(
          children: List.generate(total, (i) {
            final filled = i < completed;
            return Expanded(
              child: Container(
                margin: EdgeInsets.only(right: i == total - 1 ? 0 : 1.5),
                color: filled ? _plateColors[i % _plateColors.length] : AppColors.surfaceHighest,
              ),
            );
          }),
        ),
      ),
    );
  }
}
