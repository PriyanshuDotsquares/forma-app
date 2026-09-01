import 'package:flutter/material.dart';

import '../../../../core/design_system/design_system.dart';

/// Minimal inline trend line for hub row-link previews. Deliberately not a
/// real `fl_chart` chart — these are tiny glanceable previews with no axes
/// to configure, not one of the primary detail-screen charts.
class Sparkline extends StatelessWidget {
  const Sparkline({
    super.key,
    required this.values,
    this.color = AppColors.accentBlue,
    this.width = 64,
    this.height = 28,
    this.strokeWidth = 1.6,
  });

  final List<double> values;
  final Color color;
  final double width;
  final double height;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) {
      return SizedBox(
        width: width,
        height: height,
        child: Center(child: Text('—', style: AppTypography.mono(size: 12, color: AppColors.textMuted))),
      );
    }
    return CustomPaint(size: Size(width, height), painter: _SparklinePainter(values: values, color: color, strokeWidth: strokeWidth));
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({required this.values, required this.color, required this.strokeWidth});

  final List<double> values;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final minV = values.reduce((a, b) => a < b ? a : b);
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final range = (maxV - minV).abs() < 1e-9 ? 1.0 : maxV - minV;
    final dx = values.length > 1 ? size.width / (values.length - 1) : 0.0;

    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = dx * i;
      final t = (values[i] - minV) / range;
      final y = size.height - t * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
}
