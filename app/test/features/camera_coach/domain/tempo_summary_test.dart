import 'package:flutter_test/flutter_test.dart';
import 'package:forma/features/camera_coach/domain/form_heuristics.dart';
import 'package:forma/features/camera_coach/domain/rep_counter.dart';
import 'package:forma/features/camera_coach/domain/tempo_summary.dart';

RepResult _rep(int i, double falling, double rising, {double pause = 0}) =>
    RepResult(index: i, romPct: 100, tempoEccentricSeconds: falling, tempoConcentricSeconds: rising, bottomPauseSeconds: pause);

RepTempo _t(int i, double lowering, double lifting, {double? pause}) =>
    RepTempo(index: i, loweringSeconds: lowering, liftingSeconds: lifting, pauseSeconds: pause);

void main() {
  group('fallingPhaseIsLowering', () {
    test('squat, hinge and press: the angle-falling phase is the lowering', () {
      for (final p in [MovementPattern.squat, MovementPattern.hinge, MovementPattern.press]) {
        expect(fallingPhaseIsLowering(p), isTrue, reason: '$p');
      }
    });

    test('pull, row and fly: the angle-falling phase is the effort, not the lowering', () {
      for (final p in [MovementPattern.pull, MovementPattern.bentOverRow, MovementPattern.flyIsolation]) {
        expect(fallingPhaseIsLowering(p), isFalse, reason: '$p');
      }
    });
  });

  group('RepTempo.fromRep', () {
    test('maps the falling phase to lowering for a squat-type exercise', () {
      final t = RepTempo.fromRep(_rep(1, 2.0, 1.0), fallingIsLowering: true);
      expect(t.loweringSeconds, 2.0);
      expect(t.liftingSeconds, 1.0);
    });

    test('swaps the two for a pull-type exercise (a row: the pull is the angle-falling phase)', () {
      final t = RepTempo.fromRep(_rep(1, 1.0, 2.5), fallingIsLowering: false);
      expect(t.liftingSeconds, 1.0, reason: 'pulling is the effort');
      expect(t.loweringSeconds, 2.5, reason: 'the controlled return');
    });

    test('a phase that measured 0 is unknown, not an impossibly fast 0.0s', () {
      final t = RepTempo.fromRep(_rep(1, 0, 1.2), fallingIsLowering: true);
      expect(t.loweringSeconds, isNull);
      expect(t.isComplete, isFalse);
      expect(t.totalSeconds, isNull);
    });
  });

  group('TempoSummary.fromReps', () {
    test('is null when no rep has a complete tempo', () {
      expect(TempoSummary.fromReps(const []), isNull);
      expect(TempoSummary.fromReps(const [RepTempo(index: 1)]), isNull);
    });

    test('averages lowering, lifting and pause over the timed reps only', () {
      final s = TempoSummary.fromReps([
        _t(1, 2.0, 1.0, pause: 0.5),
        _t(2, 3.0, 1.0, pause: 0.5),
        const RepTempo(index: 3), // untimed: must not drag the averages down
      ])!;
      expect(s.avgLoweringSeconds, closeTo(2.5, 1e-9));
      expect(s.avgLiftingSeconds, closeTo(1.0, 1e-9));
      expect(s.avgPauseSeconds, closeTo(0.5, 1e-9));
      expect(s.timedReps, 2);
      expect(s.reps, hasLength(3), reason: 'the untimed rep is still part of the set');
    });

    test('identifies the fastest and slowest rep by moving time', () {
      final s = TempoSummary.fromReps([_t(1, 2.0, 1.0), _t(2, 1.0, 0.5), _t(3, 3.0, 2.0)])!;
      expect(s.fastest.index, 2);
      expect(s.slowest.index, 3);
    });

    test('only reports a pause once it is long enough to be deliberate', () {
      expect(TempoSummary.fromReps([_t(1, 2, 1, pause: 0.1), _t(2, 2, 1, pause: 0.2)])!.deliberatePauseSeconds, isNull);
      expect(TempoSummary.fromReps([_t(1, 2, 1, pause: 0.8), _t(2, 2, 1, pause: 1.0)])!.deliberatePauseSeconds, closeTo(0.9, 1e-9));
    });

    test('consistency: near-identical reps are steady, widely varying reps are uneven', () {
      final steady = TempoSummary.fromReps([_t(1, 2.0, 1.0), _t(2, 2.1, 1.0), _t(3, 1.9, 1.1)])!;
      final uneven = TempoSummary.fromReps([_t(1, 1.0, 0.5), _t(2, 3.0, 2.0), _t(3, 1.0, 0.5), _t(4, 4.0, 2.0)])!;
      expect(steady.consistency, TempoConsistency.steady);
      expect(uneven.consistency, TempoConsistency.uneven);
    });

    test('a single rep cannot be judged for consistency', () {
      expect(TempoSummary.fromReps([_t(1, 2, 1)])!.consistency, TempoConsistency.notEnoughReps);
    });

    test('trend: a set that gets clearly faster is flagged, a steady one is not', () {
      final speedingUp = TempoSummary.fromReps([_t(1, 3, 2), _t(2, 3, 2), _t(3, 1.5, 1), _t(4, 1.5, 1)])!;
      final slowingDown = TempoSummary.fromReps([_t(1, 1.5, 1), _t(2, 1.5, 1), _t(3, 3, 2), _t(4, 3, 2)])!;
      final even = TempoSummary.fromReps([_t(1, 2, 1), _t(2, 2.1, 1), _t(3, 2, 1.1), _t(4, 2.1, 1)])!;
      expect(speedingUp.trend, TempoTrend.speedingUp);
      expect(slowingDown.trend, TempoTrend.slowingDown);
      expect(even.trend, isNull);
    });

    test('trend needs at least 4 timed reps', () {
      expect(TempoSummary.fromReps([_t(1, 3, 2), _t(2, 1, 1), _t(3, 1, 1)])!.trend, isNull);
    });
  });

  test('fmt shows one decimal and a dash for unknown', () {
    expect(TempoSummary.fmt(2.04), '2.0s');
    expect(TempoSummary.fmt(null), '—');
  });
}
