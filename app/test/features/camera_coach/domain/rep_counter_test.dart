import 'package:flutter_test/flutter_test.dart';
import 'package:forma/features/camera_coach/domain/rep_counter.dart';

/// Feeds a list of raw angle values (elbow-driven) into [counter] one at a
/// time, one frame (33ms, ~30fps) apart so tempo math and the hold-time
/// guard have a stable, deterministic clock instead of racing
/// `DateTime.now()`. Reuses (and advances) [start] rather than resetting to
/// a fixed instant, so multiple calls against the same counter stay on one
/// continuous timeline.
DateTime _feed(RepCounter counter, List<double?> values, DateTime start) {
  var t = start;
  for (final v in values) {
    counter.addSample(v == null ? const JointAngles() : JointAngles(elbowAngleDeg: v), at: t);
    t = t.add(const Duration(milliseconds: 33));
  }
  return t;
}

/// A smooth, monotonic ramp from [from] to [to] over [steps] samples —
/// models a real rep's gradual joint-angle travel — followed by [hold]
/// extra samples parked at [to], the way a real lifter briefly settles at
/// the top/bottom of a rep rather than instantly reversing direction. The
/// hold matters once the counter smooths its input ([RepCounter.
/// smoothingWindow]) and debounces a phase transition ([RepCounter.
/// minPhaseHoldMs]): both need a handful of settled frames at the true
/// extreme, just like a real ~30fps camera stream would produce.
List<double> _rampAndHold(double from, double to, {int steps = 30, int hold = 8}) {
  final ramp = steps <= 1 ? <double>[from] : List.generate(steps, (i) => from + (to - from) * i / (steps - 1));
  return [...ramp, ...List.filled(hold, to)];
}

void main() {
  group('RepCounter — clean single-plane reps', () {
    test('counts one full press-style rep (elbow: extended -> flexed -> extended)', () {
      final counter = RepCounter(drivingJoint: RepDrivingJoint.elbow, bottomThreshold: 90, topThreshold: 160);
      _feed(counter, [..._rampAndHold(170, 170, steps: 1, hold: 5), ..._rampAndHold(170, 80), ..._rampAndHold(80, 170)], DateTime(2026));
      expect(counter.repCount, 1);
    });

    test('counts three consecutive reps', () {
      final counter = RepCounter(drivingJoint: RepDrivingJoint.elbow, bottomThreshold: 90, topThreshold: 160);
      final values = <double>[..._rampAndHold(170, 170, steps: 1, hold: 5)];
      for (var i = 0; i < 3; i++) {
        values.addAll(_rampAndHold(170, 80));
        values.addAll(_rampAndHold(80, 170));
      }
      _feed(counter, values, DateTime(2026));
      expect(counter.repCount, 3);
    });

    test('does not count a shallow dip that never reaches bottomThreshold', () {
      final counter = RepCounter(drivingJoint: RepDrivingJoint.elbow, bottomThreshold: 90, topThreshold: 160);
      _feed(counter, [
        ..._rampAndHold(170, 170, steps: 1, hold: 5),
        ..._rampAndHold(170, 130), // only a partial rep — never crosses 90
        ..._rampAndHold(130, 170),
      ], DateTime(2026));
      expect(counter.repCount, 0);
    });

    test('null (occluded) samples are ignored, not treated as zero', () {
      final counter = RepCounter(drivingJoint: RepDrivingJoint.elbow, bottomThreshold: 90, topThreshold: 160);
      _feed(counter, [
        ..._rampAndHold(170, 170, steps: 1, hold: 5),
        ..._rampAndHold(170, 80),
        null, null, // a couple of dropped/occluded frames mid-rep
        ..._rampAndHold(80, 170),
      ], DateTime(2026));
      expect(counter.repCount, 1);
    });
  });

  group('RepCounter — noise robustness (the reported "wrong rep counts" bug)', () {
    test('a single noisy frame spiking past topThreshold mid-descent does not register a false rep', () {
      final counter = RepCounter(drivingJoint: RepDrivingJoint.elbow, bottomThreshold: 90, topThreshold: 160);
      _feed(counter, [
        ..._rampAndHold(170, 170, steps: 1, hold: 5),
        ..._rampAndHold(170, 120, steps: 15, hold: 0), // descending, not yet past bottomThreshold
        200, // one bad MediaPipe frame (occlusion/motion blur) reading an impossible angle
        ..._rampAndHold(118, 80, steps: 15), // descent continues from where it left off
        ..._rampAndHold(80, 170),
      ], DateTime(2026));
      // Exactly the one genuine rep should count — the noise spike must not
      // have corrupted the top-of-rep median or the state machine.
      expect(counter.repCount, 1);
    });

    test('a single noisy frame dipping past bottomThreshold during the top phase does not fabricate a rep', () {
      final counter = RepCounter(drivingJoint: RepDrivingJoint.elbow, bottomThreshold: 90, topThreshold: 160);
      _feed(counter, [
        ..._rampAndHold(170, 170, steps: 1, hold: 5),
        40, // one bad frame reading a false deep-flexion value while standing at the top
        ..._rampAndHold(170, 170, steps: 1, hold: 5),
        // No real rep was ever performed.
      ], DateTime(2026));
      expect(counter.repCount, 0);
    });

    test('a sustained (multi-frame) change still counts as a real rep, not just single-frame spikes', () {
      final counter = RepCounter(drivingJoint: RepDrivingJoint.elbow, bottomThreshold: 90, topThreshold: 160);
      _feed(
        counter,
        [..._rampAndHold(170, 170, steps: 1, hold: 5), ..._rampAndHold(170, 70), ..._rampAndHold(70, 170)],
        DateTime(2026),
      );
      expect(counter.repCount, 1);
    });

    test('minAngleDelta still rejects a full threshold crossing with too small an excursion', () {
      final counter = RepCounter(
        drivingJoint: RepDrivingJoint.elbow,
        bottomThreshold: 90,
        topThreshold: 100,
        minAngleDelta: 50,
        smoothingWindow: 1, // isolate this guard from smoothing
        minPhaseHoldMs: 0, // and from the hold-time guard
      );
      _feed(counter, [
        ..._rampAndHold(105, 105, steps: 1, hold: 3),
        ..._rampAndHold(105, 85, steps: 5, hold: 1),
        ..._rampAndHold(85, 105, steps: 5, hold: 1),
      ], DateTime(2026));
      expect(counter.repCount, 0);
    });

    test('a brief threshold blip shorter than minPhaseHoldMs does not trigger a phase change', () {
      final counter = RepCounter(
        drivingJoint: RepDrivingJoint.elbow,
        bottomThreshold: 90,
        topThreshold: 160,
        smoothingWindow: 1, // isolate the hold-time guard from median smoothing
        minPhaseHoldMs: 250,
      );
      var t = DateTime(2026);
      t = _feed(counter, [
        170, 170, 170,
        85, 85, // ~66ms below bottomThreshold — well short of the 250ms hold
        170, 170, 170,
      ], t);
      expect(counter.repCount, 0, reason: 'the blip never dwelt long enough to count as reaching the bottom');

      // The counter must not be stuck — a real, sustained descent still
      // works on the very same instance afterward.
      _feed(counter, [..._rampAndHold(170, 80), ..._rampAndHold(80, 170)], t);
      expect(counter.repCount, 1);
    });

    test('a single outlier sample at the bottom does not skew the rep depth (median, not raw min)', () {
      RepResult? captured;
      final counter = RepCounter(
        drivingJoint: RepDrivingJoint.elbow,
        bottomThreshold: 90,
        topThreshold: 170,
        smoothingWindow: 1, // isolate the windowed-median depth estimate
        minPhaseHoldMs: 0, // from per-frame smoothing and the hold-time guard
        onRepCompleted: (r) => captured = r,
      );
      _feed(counter, [
        180, 180, 180, 180, 180, 180, // settle at top -> _topSamples (median 180)
        85, 85, 85, 20, 85, 85, 85, 85, // bottom phase: mostly ~85 with one wild outlier (20)
        180, 180, // ascend back above topThreshold -> completes the rep
      ], DateTime(2026));

      expect(counter.repCount, 1);
      // top(180) - bottom(median 85) = 95; / thresholdGap(80) * 100 ≈ 118.75%.
      // The old raw-min behavior would have used the outlier (20) as the
      // bottom, giving top(180) - 20 = 160 -> 200%, clamped to 150.
      expect(captured, isNotNull);
      expect(captured!.romPct, closeTo(118.75, 1));
    });
  });

  group('RepCounter — shoulder-driven (fly/crossover) config', () {
    test('counts a fly/crossover rep driven by shoulder angle, not elbow', () {
      final counter = RepCounter(drivingJoint: RepDrivingJoint.shoulder, bottomThreshold: 30, topThreshold: 60);
      var t = DateTime(2026);
      for (final v in [..._rampAndHold(70, 70, steps: 1, hold: 5), ..._rampAndHold(70, 15), ..._rampAndHold(15, 70)]) {
        counter.addSample(JointAngles(shoulderAngleDeg: v), at: t);
        t = t.add(const Duration(milliseconds: 33));
      }
      expect(counter.repCount, 1);
    });
  });

  group('RepCounter — reset()', () {
    test('reset clears count, phase, smoothing, and sample-median state for a new set', () {
      final counter = RepCounter(drivingJoint: RepDrivingJoint.elbow, bottomThreshold: 90, topThreshold: 160);
      _feed(
        counter,
        [..._rampAndHold(170, 170, steps: 1, hold: 5), ..._rampAndHold(170, 80), ..._rampAndHold(80, 170)],
        DateTime(2026),
      );
      expect(counter.repCount, 1);

      counter.reset();
      expect(counter.repCount, 0);

      _feed(
        counter,
        [..._rampAndHold(170, 170, steps: 1, hold: 5), ..._rampAndHold(170, 80), ..._rampAndHold(80, 170)],
        DateTime(2030),
      );
      expect(counter.repCount, 1);
    });
  });
}
