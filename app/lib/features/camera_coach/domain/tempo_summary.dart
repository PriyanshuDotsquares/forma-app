import 'dart:math' as math;

import 'form_heuristics.dart';
import 'rep_counter.dart';

/// Whether the phase where the counter's driving angle *falls* is the lowering
/// (eccentric) phase for [pattern].
///
/// True for squat, hinge and press: the joint closes as the lifter lowers.
/// False for pull, bent-over row and fly/crossover: there the joint closes as
/// the lifter pulls, so the falling phase is the effort and the rising phase is
/// the controlled return. [MovementPattern.generic] shares the pull config, so
/// it is treated as pull-type — a best guess, since an unclassified exercise
/// has no known direction.
bool fallingPhaseIsLowering(MovementPattern pattern) {
  switch (pattern) {
    case MovementPattern.squat:
    case MovementPattern.hinge:
    case MovementPattern.press:
      return true;
    case MovementPattern.pull:
    case MovementPattern.bentOverRow:
    case MovementPattern.flyIsolation:
    case MovementPattern.generic:
      return false;
  }
}

/// One rep's tempo, in lowering/lifting terms rather than the counter's raw
/// angle-falling/angle-rising terms.
///
/// Tempo is **reported, never graded**. A trainer's own sets can differ by more
/// than 2x in duration, so a "too fast" cut-off invented from a few videos would
/// be wrong or useless; this only measures.
class RepTempo {
  const RepTempo({required this.index, this.loweringSeconds, this.liftingSeconds, this.pauseSeconds});

  /// Builds the tempo of [rep]. [fallingIsLowering] comes from
  /// [fallingPhaseIsLowering] for the exercise's movement pattern.
  ///
  /// A phase that measured 0 (e.g. the very first frames of a set, or a rep that
  /// completed in fewer frames than the clock can resolve) is reported as
  /// unknown rather than as "0.0s", which would read as an impossibly fast rep.
  factory RepTempo.fromRep(RepResult rep, {required bool fallingIsLowering}) {
    double? known(double v) => v > 0 ? v : null;
    final falling = known(rep.tempoEccentricSeconds);
    final rising = known(rep.tempoConcentricSeconds);
    return RepTempo(
      index: rep.index,
      loweringSeconds: fallingIsLowering ? falling : rising,
      liftingSeconds: fallingIsLowering ? rising : falling,
      pauseSeconds: known(rep.bottomPauseSeconds),
    );
  }

  final int index;

  /// Controlled-return time (eccentric). Null when it could not be measured.
  final double? loweringSeconds;

  /// Effort time (concentric). Null when it could not be measured.
  final double? liftingSeconds;

  /// Pause at the extreme of the counter's range, before the direction change.
  final double? pauseSeconds;

  /// Both phases measured — the rep can contribute to averages and trends.
  bool get isComplete => loweringSeconds != null && liftingSeconds != null;

  /// Moving time for the rep (excludes the pause). Null unless [isComplete].
  double? get totalSeconds => isComplete ? loweringSeconds! + liftingSeconds! : null;
}

/// The overall tempo of one set, built from its [RepTempo]s.
class TempoSummary {
  const TempoSummary._({
    required this.reps,
    required this.avgLoweringSeconds,
    required this.avgLiftingSeconds,
    required this.avgPauseSeconds,
    required this.fastest,
    required this.slowest,
    required this.consistency,
    required this.trend,
  });

  /// Summarises [reps], or returns null when no rep has a complete tempo (e.g. a
  /// set logged by hand, or one where every rep was too short to time).
  static TempoSummary? fromReps(List<RepTempo> reps) {
    final complete = reps.where((r) => r.isComplete).toList();
    if (complete.isEmpty) return null;

    double mean(Iterable<double> values) => values.reduce((a, b) => a + b) / values.length;

    final pauses = complete.map((r) => r.pauseSeconds).whereType<double>().toList();
    final totals = complete.map((r) => r.totalSeconds!).toList();

    RepTempo pick(bool Function(double a, double b) better) =>
        complete.reduce((best, r) => better(r.totalSeconds!, best.totalSeconds!) ? r : best);

    return TempoSummary._(
      reps: List.unmodifiable(reps),
      avgLoweringSeconds: mean(complete.map((r) => r.loweringSeconds!)),
      avgLiftingSeconds: mean(complete.map((r) => r.liftingSeconds!)),
      avgPauseSeconds: pauses.isEmpty ? null : mean(pauses),
      fastest: pick((a, b) => a < b),
      slowest: pick((a, b) => a > b),
      consistency: _consistencyOf(totals),
      trend: _trendOf(totals),
    );
  }

  /// Every rep of the set, including any whose tempo could not be measured.
  final List<RepTempo> reps;

  final double avgLoweringSeconds;
  final double avgLiftingSeconds;

  /// Average pause, over the reps that had a measurable one; null if none did.
  final double? avgPauseSeconds;

  /// The quickest and slowest reps by moving time.
  final RepTempo fastest;
  final RepTempo slowest;

  final TempoConsistency consistency;

  /// How the pace changed through the set, or null when the set was too short
  /// to say (fewer than 4 timed reps) or the pace held steady.
  final TempoTrend? trend;

  /// Reps that contributed to the averages.
  int get timedReps => reps.where((r) => r.isComplete).length;

  /// Average moving time of one rep.
  double get avgTotalSeconds => avgLoweringSeconds + avgLiftingSeconds;

  /// The measured pause is the time spent past the bottom threshold, which
  /// includes ~0.3-0.5s of the movement itself (the counter requires a dwell
  /// there before it accepts the rep, and the joint still has to travel in and
  /// out of the zone). Only a pause comfortably longer than that is a real,
  /// deliberate one — a lower cut-off would show "PAUSE" on nearly every rep.
  static const double minDeliberatePauseSeconds = 0.8;

  /// The average pause when it is long enough to be a deliberate one.
  double? get deliberatePauseSeconds {
    final p = avgPauseSeconds;
    return p != null && p >= minDeliberatePauseSeconds ? p : null;
  }

  /// "2.1s" — one decimal, the precision the timing can actually support.
  static String fmt(double? seconds) => seconds == null ? '—' : '${seconds.toStringAsFixed(1)}s';

  /// Spread of rep times: coefficient of variation = std-dev / mean.
  static TempoConsistency _consistencyOf(List<double> totals) {
    if (totals.length < 2) return TempoConsistency.notEnoughReps;
    final mean = totals.reduce((a, b) => a + b) / totals.length;
    if (mean <= 0) return TempoConsistency.notEnoughReps;
    final variance = totals.map((t) => math.pow(t - mean, 2)).reduce((a, b) => a + b) / totals.length;
    final cv = math.sqrt(variance) / mean;
    if (cv < 0.15) return TempoConsistency.steady;
    if (cv < 0.30) return TempoConsistency.slightlyUneven;
    return TempoConsistency.uneven;
  }

  /// Compares the first half of the set against the second. A 20% change is the
  /// smallest shift that is still visible above rep-to-rep noise.
  static TempoTrend? _trendOf(List<double> totals) {
    if (totals.length < 4) return null;
    final half = totals.length ~/ 2;
    double mean(List<double> v) => v.reduce((a, b) => a + b) / v.length;
    final first = mean(totals.sublist(0, half));
    final second = mean(totals.sublist(totals.length - half));
    if (first <= 0) return null;
    final change = (second - first) / first;
    if (change <= -0.20) return TempoTrend.speedingUp;
    if (change >= 0.20) return TempoTrend.slowingDown;
    return null;
  }
}

enum TempoConsistency {
  steady('Steady pace'),
  slightlyUneven('Slightly uneven'),
  uneven('Uneven pace'),
  notEnoughReps('Too few reps to judge');

  const TempoConsistency(this.label);
  final String label;
}

enum TempoTrend {
  speedingUp('Speeding up as the set went on'),
  slowingDown('Slowing down as the set went on');

  const TempoTrend(this.label);
  final String label;
}
