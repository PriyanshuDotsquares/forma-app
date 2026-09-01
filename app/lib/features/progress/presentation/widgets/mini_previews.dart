import 'package:flutter/material.dart';

import '../../../../core/design_system/design_system.dart';
import 'progress_format.dart';

/// Tiny inline bar preview (e.g. top few muscles by sets) used on the hub's
/// "Volume by muscle" row-link.
class MiniBarPreview extends StatelessWidget {
  const MiniBarPreview({super.key, required this.values, this.color = AppColors.accentBlue, this.height = 28, this.barWidth = 5});

  /// Each value normalized 0..1.
  final List<double> values;
  final Color color;
  final double height;
  final double barWidth;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(child: Text('—', style: AppTypography.mono(size: 12, color: AppColors.textMuted))),
      );
    }
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final v in values)
            Container(
              width: barWidth,
              height: (height * v.clamp(0.08, 1)).toDouble(),
              margin: const EdgeInsets.only(right: 3),
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(1.5)),
            ),
        ],
      ),
    );
  }
}

/// Compact dot-grid preview — a handful of recent days as small filled/empty
/// squares, used on the hub's "Consistency" row-link.
class MiniDotGrid extends StatelessWidget {
  const MiniDotGrid({super.key, required this.filled, this.columns = 7, this.size = 6});

  final List<bool> filled;
  final int columns;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: columns * (size + 3),
      child: Wrap(
        spacing: 3,
        runSpacing: 3,
        children: [
          for (final f in filled)
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: f ? AppColors.accentBlue : AppColors.surfaceHighest,
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
        ],
      ),
    );
  }
}

/// Tiny "two-figure" recovery glyph for the hub's "Recovery" row-link — two
/// overlapping body icons tinted by the average recovered percentage.
class MiniRecoveryFigures extends StatelessWidget {
  const MiniRecoveryFigures({super.key, required this.avgPct});

  final double avgPct;

  @override
  Widget build(BuildContext context) {
    final color = recoveryColor(avgPct);
    return SizedBox(
      width: 34,
      height: 28,
      child: Stack(
        children: [
          Positioned(left: 0, top: 2, child: Icon(Icons.accessibility_new, size: 20, color: color.withValues(alpha: 0.45))),
          Positioned(right: 0, top: 0, child: Icon(Icons.accessibility_new, size: 22, color: color)),
        ],
      ),
    );
  }
}
