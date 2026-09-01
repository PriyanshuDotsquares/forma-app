import 'package:flutter/material.dart';

import '../../../../core/design_system/design_system.dart';
import 'progress_format.dart';

/// A simple, deliberately non-photorealistic body silhouette with muscle
/// zones colored by recovery percentage. Built from flat rounded-rect
/// "blobs" rather than an illustration — there's no art asset for this, and
/// the design system forbids gradients/glassmorphism anyway, so a schematic
/// reading is the honest choice.
class RecoverySilhouette extends StatelessWidget {
  const RecoverySilhouette({super.key, required this.pctByMuscle, required this.isFront, this.width = 200, this.height = 300});

  final Map<String, double> pctByMuscle;
  final bool isFront;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(width, height),
      painter: _SilhouettePainter(pctByMuscle: pctByMuscle, isFront: isFront),
    );
  }
}

class _Zone {
  const _Zone(this.muscle, this.rect);
  final String? muscle; // null = untracked / neutral filler shape
  final Rect rect; // fractional, 0..1 of the canvas
}

// Fractional (left, top, right, bottom) zones. Per the task's mapping:
// front = chest, shoulders, biceps, triceps, quads, core.
// back  = back, hamstrings, glutes, calves.
const _frontZones = [
  _Zone('shoulders', Rect.fromLTRB(0.10, 0.15, 0.34, 0.24)),
  _Zone('shoulders', Rect.fromLTRB(0.66, 0.15, 0.90, 0.24)),
  _Zone('chest', Rect.fromLTRB(0.30, 0.21, 0.70, 0.34)),
  _Zone('biceps', Rect.fromLTRB(0.06, 0.25, 0.23, 0.43)),
  _Zone('biceps', Rect.fromLTRB(0.77, 0.25, 0.94, 0.43)),
  _Zone('core', Rect.fromLTRB(0.33, 0.34, 0.67, 0.52)),
  _Zone('triceps', Rect.fromLTRB(0.05, 0.43, 0.21, 0.60)),
  _Zone('triceps', Rect.fromLTRB(0.79, 0.43, 0.95, 0.60)),
  _Zone('quads', Rect.fromLTRB(0.27, 0.54, 0.48, 0.80)),
  _Zone('quads', Rect.fromLTRB(0.52, 0.54, 0.73, 0.80)),
  _Zone(null, Rect.fromLTRB(0.30, 0.80, 0.48, 0.98)),
  _Zone(null, Rect.fromLTRB(0.52, 0.80, 0.70, 0.98)),
];

const _backZones = [
  _Zone(null, Rect.fromLTRB(0.10, 0.15, 0.34, 0.24)),
  _Zone(null, Rect.fromLTRB(0.66, 0.15, 0.90, 0.24)),
  _Zone('back', Rect.fromLTRB(0.28, 0.20, 0.72, 0.50)),
  _Zone(null, Rect.fromLTRB(0.06, 0.25, 0.23, 0.50)),
  _Zone(null, Rect.fromLTRB(0.77, 0.25, 0.94, 0.50)),
  _Zone('glutes', Rect.fromLTRB(0.31, 0.50, 0.69, 0.60)),
  _Zone('hamstrings', Rect.fromLTRB(0.27, 0.60, 0.48, 0.80)),
  _Zone('hamstrings', Rect.fromLTRB(0.52, 0.60, 0.73, 0.80)),
  _Zone('calves', Rect.fromLTRB(0.29, 0.80, 0.47, 0.98)),
  _Zone('calves', Rect.fromLTRB(0.53, 0.80, 0.71, 0.98)),
];

class _SilhouettePainter extends CustomPainter {
  _SilhouettePainter({required this.pctByMuscle, required this.isFront});

  final Map<String, double> pctByMuscle;
  final bool isFront;

  @override
  void paint(Canvas canvas, Size size) {
    // Head — decorative only, not a tracked muscle group.
    final headCenter = Offset(size.width * 0.5, size.height * 0.075);
    final headRadius = size.width * 0.12;
    canvas.drawCircle(
      headCenter,
      headRadius,
      Paint()..color = AppColors.surfaceHighest,
    );
    canvas.drawCircle(
      headCenter,
      headRadius,
      Paint()
        ..color = AppColors.outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    final zones = isFront ? _frontZones : _backZones;
    for (final zone in zones) {
      final rect = Rect.fromLTRB(
        zone.rect.left * size.width,
        zone.rect.top * size.height,
        zone.rect.right * size.width,
        zone.rect.bottom * size.height,
      );
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(10));
      final pct = zone.muscle != null ? pctByMuscle[zone.muscle] : null;
      final fill = pct != null ? recoveryColor(pct) : AppColors.surfaceHighest;

      canvas.drawRRect(rrect, Paint()..color = pct != null ? fill.withValues(alpha: 0.55) : fill);
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = pct != null ? fill : AppColors.outline
          ..style = PaintingStyle.stroke
          ..strokeWidth = pct != null ? 1.6 : 1,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SilhouettePainter oldDelegate) =>
      oldDelegate.isFront != isFront || oldDelegate.pctByMuscle != pctByMuscle;
}
