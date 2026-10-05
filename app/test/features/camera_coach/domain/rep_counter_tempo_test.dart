import 'package:flutter_test/flutter_test.dart';
import 'package:forma/features/camera_coach/domain/rep_counter.dart';

/// Same deterministic ~30fps clock as `rep_counter_test.dart`: one frame every
/// 33ms, so tempo is asserted against known frame counts instead of racing
/// `DateTime.now()`.
DateTime _feed(RepCounter counter, List<double> values, DateTime start) {
  var t = start;
  for (final v in values) {
    counter.addSample(JointAngles(elbowAngleDeg: v), at: t);
    t = t.add(const Duration(milliseconds: 33));
  }
  return t;
}

List<double> _ramp(double from, double to, {int steps = 30, int hold = 8}) => [
  ...List.generate(steps, (i) => from + (to - from) * i / (steps - 1)),
  ...List.filled(hold, to),
];

List<double> _stand(int frames) => List.filled(frames, 170.0);

RepCounter _counter(List<RepResult> out) =>
    RepCounter(drivingJoint: RepDrivingJoint.elbow, bottomThreshold: 90, topThreshold: 160, onRepCompleted: out.add);

void main() {
  group('RepResult tempo — travel time between the threshold crossings', () {
    test('rep 1 does not include the setup time spent standing before the first movement', () {
      final reps = <RepResult>[];
      // ~3s of standing, then a ~1s descent/ascent.
      _feed(_counter(reps), [..._stand(90), ..._ramp(170, 80), ..._ramp(80, 170)], DateTime(2026));

      expect(reps, hasLength(1));
      // 170 -> 90 takes ~23 of the 30 ramp frames (~0.76s). Counting from the
      // first sample would have reported ~3.7s.
      expect(reps.single.tempoEccentricSeconds, inInclusiveRange(0.5, 1.2));
    });

    test('a long rest at the top between reps is not folded into the next rep', () {
      final reps = <RepResult>[];
      _feed(
        _counter(reps),
        [..._stand(5), ..._ramp(170, 80), ..._ramp(80, 170), ..._stand(60), ..._ramp(170, 80), ..._ramp(80, 170)],
        DateTime(2026),
      );

      expect(reps, hasLength(2));
      expect(reps[1].tempoEccentricSeconds, inInclusiveRange(0.5, 1.2), reason: 'a ~2s rest at the top must not count as lowering time');
    });

    test('lifting time excludes the pause at the bottom, which is reported separately', () {
      final reps = <RepResult>[];
      // ~1s parked at the bottom.
      _feed(_counter(reps), [..._stand(5), ..._ramp(170, 80, hold: 30), ..._ramp(80, 170)], DateTime(2026));

      expect(reps, hasLength(1));
      expect(reps.single.bottomPauseSeconds, inInclusiveRange(0.95, 1.45));
      expect(reps.single.tempoConcentricSeconds, inInclusiveRange(0.5, 1.2), reason: 'the ~1s pause must not inflate the lift');
    });

    test('a touch-and-go rep reports a pause well below a deliberate one', () {
      final reps = <RepResult>[];
      // Just enough dwell at the bottom for the counter to accept the rep.
      _feed(_counter(reps), [..._stand(5), ..._ramp(170, 80, hold: 9), ..._ramp(80, 170)], DateTime(2026));

      expect(reps, hasLength(1));
      // Includes ~0.3-0.5s of the movement itself, hence the cut-off in
      // TempoSummary.minDeliberatePauseSeconds being well above this.
      expect(reps.single.bottomPauseSeconds, lessThan(0.8));
    });

    test('a slower descent measures longer than a faster one', () {
      final fast = <RepResult>[];
      final slow = <RepResult>[];
      _feed(_counter(fast), [..._stand(5), ..._ramp(170, 80, steps: 20), ..._ramp(80, 170, steps: 20)], DateTime(2026));
      _feed(_counter(slow), [..._stand(5), ..._ramp(170, 80, steps: 60), ..._ramp(80, 170, steps: 20)], DateTime(2026));

      expect(slow.single.tempoEccentricSeconds, greaterThan(fast.single.tempoEccentricSeconds * 2));
    });

    test('reset() clears the tempo bookkeeping so the next set starts clean', () {
      final reps = <RepResult>[];
      final counter = _counter(reps);
      var t = _feed(counter, [..._stand(5), ..._ramp(170, 80), ..._ramp(80, 170)], DateTime(2026));
      counter.reset();
      // A 5s gap after reset, then a fresh rep: the gap must not leak into rep 1.
      t = t.add(const Duration(seconds: 5));
      _feed(counter, [..._stand(5), ..._ramp(170, 80), ..._ramp(80, 170)], t);

      expect(reps, hasLength(2));
      expect(reps.last.tempoEccentricSeconds, inInclusiveRange(0.5, 1.2));
    });
  });
}
