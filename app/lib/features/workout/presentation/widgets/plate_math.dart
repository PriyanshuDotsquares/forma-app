/// Standard Olympic barbell plate set, heaviest first, in kg — used to
/// greedily fill the per-side remainder above the bar weight.
const List<double> _standardPlatesKg = [20, 10, 5, 2.5, 1.25];

/// Default Olympic barbell weight in kg.
const double defaultBarWeightKg = 20;

/// The per-side plate breakdown for loading a barbell to [targetWeightKg]
/// using a [barWeightKg] bar and a standard plate set (20/10/5/2.5/1.25kg
/// pairs). Greedily picks the largest plate that still fits the remaining
/// per-side weight, repeating until the remainder is smaller than the
/// smallest available plate (1.25kg) — so unusual targets (e.g. an odd
/// number from a typed-in weight) may leave a small [leftoverPerSideKg]
/// that can't be exactly represented by the standard set.
class PlateBreakdown {
  const PlateBreakdown({required this.barWeightKg, required this.platesPerSide, required this.leftoverPerSideKg});

  final double barWeightKg;

  /// Plates for one side of the bar, heaviest first.
  final List<double> platesPerSide;

  /// Weight per side that couldn't be represented by the standard plate
  /// set (should normally be 0, or a fraction under 1.25kg from a
  /// non-standard typed weight).
  final double leftoverPerSideKg;

  bool get isEmpty => platesPerSide.isEmpty && leftoverPerSideKg < 0.01;

  /// e.g. "20kg bar + 10 + 5 + 2.5 / side".
  String get label {
    if (platesPerSide.isEmpty) return '${barWeightKg.toStringAgnosticTrim()}kg bar only';
    final plates = platesPerSide.map((p) => p.toStringAgnosticTrim()).join(' + ');
    return '${barWeightKg.toStringAgnosticTrim()}kg bar + $plates / side';
  }
}

PlateBreakdown computePlateBreakdown(double targetWeightKg, {double barWeightKg = defaultBarWeightKg}) {
  final remainderTotal = (targetWeightKg - barWeightKg).clamp(0, double.infinity);
  var remainderPerSide = remainderTotal / 2;

  final plates = <double>[];
  for (final plate in _standardPlatesKg) {
    while (remainderPerSide + 1e-6 >= plate) {
      plates.add(plate);
      remainderPerSide -= plate;
    }
  }

  return PlateBreakdown(
    barWeightKg: barWeightKg,
    platesPerSide: plates,
    leftoverPerSideKg: remainderPerSide < 0.01 ? 0 : double.parse(remainderPerSide.toStringAsFixed(2)),
  );
}

extension _TrimZeros on double {
  /// Formats without a trailing ".0" for whole numbers, keeping decimals
  /// (e.g. "2.5") otherwise — plate/weight labels read better as "20kg"
  /// than "20.0kg".
  String toStringAgnosticTrim() => this == truncateToDouble() ? toStringAsFixed(0) : toString();
}
