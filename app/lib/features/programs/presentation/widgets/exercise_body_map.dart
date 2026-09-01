import 'package:flutter/material.dart';

import '../../../../core/design_system/design_system.dart';
import 'muscle_tag_chip.dart';

/// Tappable body silhouette backing the library's BODY MAP view. Same
/// flat-blob, fractional-zone-rect `CustomPainter` approach as
/// `progress/presentation/widgets/recovery_silhouette.dart` (no art asset —
/// the design system forbids gradients/glassmorphism, so a schematic
/// reading is the honest choice) — repurposed here to pick a muscle filter
/// instead of shading by recovery percentage.
class ExerciseBodyMap extends StatefulWidget {
  const ExerciseBodyMap({super.key, required this.availableMuscles, required this.selected, required this.onSelect});

  /// Primary-muscle keys that at least one loaded exercise targets — zones
  /// outside this set render dim and don't respond to taps.
  final Set<String> availableMuscles;
  final String? selected;
  final ValueChanged<String> onSelect;

  @override
  State<ExerciseBodyMap> createState() => _ExerciseBodyMapState();
}

class _ExerciseBodyMapState extends State<ExerciseBodyMap> {
  bool _isFront = true;

  static const _canvasSize = Size(200, 300);

  void _handleTapUp(TapUpDetails details) {
    final zones = _isFront ? _frontZones : _backZones;
    final fraction = Offset(
      details.localPosition.dx / _canvasSize.width,
      details.localPosition.dy / _canvasSize.height,
    );
    for (final zone in zones) {
      if (zone.muscle != null && zone.rect.contains(fraction) && widget.availableMuscles.contains(zone.muscle)) {
        widget.onSelect(zone.muscle!);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _OrientationTab(label: 'FRONT', selected: _isFront, onTap: () => setState(() => _isFront = true)),
            const SizedBox(width: AppSpacing.sm),
            _OrientationTab(label: 'BACK', selected: !_isFront, onTap: () => setState(() => _isFront = false)),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        GestureDetector(
          onTapUp: _handleTapUp,
          child: CustomPaint(
            size: _canvasSize,
            painter: _BodyMapPainter(
              zones: _isFront ? _frontZones : _backZones,
              selected: widget.selected,
              available: widget.availableMuscles,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          widget.selected == null ? 'Tap a muscle group to filter' : 'Showing ${titleCaseMuscle(widget.selected!)}',
          style: AppTypography.body(size: 13, color: AppColors.textMuted),
        ),
      ],
    );
  }
}

class _OrientationTab extends StatelessWidget {
  const _OrientationTab({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentBlue : AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(AppRadius.chip),
          border: Border.all(color: selected ? AppColors.accentBlue : AppColors.outlineVariant),
        ),
        child: Text(
          label,
          style: AppTypography.body(
            size: 12,
            weight: FontWeight.w700,
            color: selected ? AppColors.accentBlueDark : AppColors.textSecondary,
          ).copyWith(letterSpacing: 0.8),
        ),
      ),
    );
  }
}

class _Zone {
  const _Zone(this.muscle, this.rect);
  final String? muscle; // null = untracked / neutral filler shape
  final Rect rect; // fractional, 0..1 of the canvas
}

// Fractional (left, top, right, bottom) zones, mirroring the proportions in
// recovery_silhouette.dart. Keys match the primary-muscle vocabulary the
// backend seed data actually uses (see backend/app/db/seed_data.py) — every
// key here is one the library's muscle filter can produce.
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

class _BodyMapPainter extends CustomPainter {
  _BodyMapPainter({required this.zones, required this.selected, required this.available});

  final List<_Zone> zones;
  final String? selected;
  final Set<String> available;

  @override
  void paint(Canvas canvas, Size size) {
    final headCenter = Offset(size.width * 0.5, size.height * 0.075);
    final headRadius = size.width * 0.12;
    canvas.drawCircle(headCenter, headRadius, Paint()..color = AppColors.surfaceHighest);
    canvas.drawCircle(
      headCenter,
      headRadius,
      Paint()
        ..color = AppColors.outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    for (final zone in zones) {
      final rect = Rect.fromLTRB(
        zone.rect.left * size.width,
        zone.rect.top * size.height,
        zone.rect.right * size.width,
        zone.rect.bottom * size.height,
      );
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(10));
      final isSelected = zone.muscle != null && zone.muscle == selected;
      final isAvailable = zone.muscle != null && available.contains(zone.muscle);

      final fill = isSelected ? AppColors.accentBlue : (isAvailable ? AppColors.surfaceHigh : AppColors.surfaceHighest);
      final stroke = isSelected ? AppColors.accentBlue : (isAvailable ? AppColors.outline : AppColors.outlineVariant);

      canvas.drawRRect(rrect, Paint()..color = isSelected ? fill.withValues(alpha: 0.55) : fill);
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = stroke
          ..style = PaintingStyle.stroke
          ..strokeWidth = isSelected ? 1.6 : 1,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BodyMapPainter oldDelegate) =>
      oldDelegate.selected != selected || oldDelegate.available != available || oldDelegate.zones != zones;
}
