/// A single frame's worth of joint angles, decoupled from any ML Kit type.
///
/// This is the boundary between the camera/pose plumbing (`google_mlkit_
/// pose_detection`'s `Pose`/`PoseLandmark`, in `data/pose_service.dart`) and
/// the pure state machines below — nothing in this file, or in
/// `form_heuristics.dart`, imports ML Kit or `camera`. That keeps both
/// unit-testable with plain Dart values instead of a device/camera.
///
/// Angles are in degrees, measured at the named joint (e.g. [elbowAngleDeg]
/// is the interior angle of the shoulder-elbow-wrist triangle at the
/// elbow). [barHeightNormalized] is a 0 (floor) .. 1 (fully overhead) proxy
/// for bar/hand height when an exercise is better tracked by vertical
/// travel than by a joint angle (e.g. a pulldown or shrug) — it is optional
/// and most movement patterns drive off an angle instead.
class JointAngles {
  const JointAngles({this.elbowAngleDeg, this.hipAngleDeg, this.kneeAngleDeg, this.barHeightNormalized});

  final double? elbowAngleDeg;
  final double? hipAngleDeg;
  final double? kneeAngleDeg;
  final double? barHeightNormalized;
}

/// Which single value in [JointAngles] a [RepCounter] watches to detect
/// reps. Everything else in [JointAngles] is still available to
/// `FormHeuristics` for scoring/cues — a rep can be *driven* by knee angle
/// while still being *graded* on hip angle, for example.
enum RepDrivingJoint { elbow, hip, knee, barHeight }

/// The outcome of one completed rep.
class RepResult {
  const RepResult({
    required this.index,
    required this.romPct,
    required this.tempoEccentricSeconds,
    required this.tempoConcentricSeconds,
  });

  /// 1-based rep number within the set.
  final int index;

  /// Range of motion achieved, as a percentage of the *configured*
  /// bottom-to-top threshold gap (see [RepCounter.bottomThreshold] /
  /// [RepCounter.topThreshold]) — 100% means the lifter's angle excursion
  /// matched or exceeded the coach-configured "full rep" window. This is
  /// deliberately relative to the threshold gap rather than a hardcoded
  /// anatomical range, so the same math works whether the driving value is
  /// a joint angle in degrees or a normalized bar height.
  final double romPct;

  /// Seconds spent moving from the top of the rep down to the bottom
  /// (the lowering / eccentric phase).
  final double tempoEccentricSeconds;

  /// Seconds spent moving from the bottom of the rep back up to the top
  /// (the lifting / concentric phase).
  final double tempoConcentricSeconds;
}

enum _Phase { atTop, atBottom }

/// A pure, testable hysteresis rep counter.
///
/// Feed it a stream of [JointAngles] via [addSample] (one call per pose
/// frame). A rep completes when the driving value crosses below
/// [bottomThreshold] and then back above [topThreshold] — classic two-
/// threshold hysteresis, not a single midpoint crossing, so small jitter
/// sitting near one line can't by itself register as a rep: the value has
/// to travel all the way to the *other* line before anything is counted.
/// [minAngleDelta] adds a second guard on top of that — even after a full
/// threshold-to-threshold crossing, the actual excursion (top-of-rep value
/// minus bottom-of-rep value) must be at least this large, which filters
/// out someone barely dipping past both lines (e.g. a shallow half-rep or
/// sensor noise) rather than performing a genuine rep.
class RepCounter {
  RepCounter({
    required this.drivingJoint,
    required this.bottomThreshold,
    required this.topThreshold,
    this.minAngleDelta = 15,
    this.onRepCompleted,
  }) : assert(bottomThreshold < topThreshold, 'bottomThreshold must be < topThreshold');

  final RepDrivingJoint drivingJoint;
  final double bottomThreshold;
  final double topThreshold;
  final double minAngleDelta;

  /// Called synchronously from [addSample] whenever a rep completes.
  void Function(RepResult result)? onRepCompleted;

  _Phase _phase = _Phase.atTop;
  int _repCount = 0;
  DateTime? _phaseStartedAt;
  DateTime? _bottomReachedAt;
  double? _topValueThisRep;
  double? _bottomValueThisRep;

  int get repCount => _repCount;

  /// Feeds one frame of joint angles. Frames where the driving value is
  /// unavailable (e.g. the joint was occluded) are ignored rather than
  /// resetting the state machine, so a brief dropout mid-rep doesn't cost
  /// the rep.
  void addSample(JointAngles angles, {DateTime? at}) {
    final value = _extract(angles);
    if (value == null) return;
    final now = at ?? DateTime.now();
    _phaseStartedAt ??= now;

    switch (_phase) {
      case _Phase.atTop:
        if (_topValueThisRep == null || value > _topValueThisRep!) {
          _topValueThisRep = value;
        }
        if (value <= bottomThreshold) {
          _bottomValueThisRep = value;
          _bottomReachedAt = now;
          _phase = _Phase.atBottom;
        }
      case _Phase.atBottom:
        if (_bottomValueThisRep == null || value < _bottomValueThisRep!) {
          _bottomValueThisRep = value;
        }
        if (value >= topThreshold) {
          final top = _topValueThisRep ?? value;
          final bottom = _bottomValueThisRep ?? value;
          final excursion = top - bottom;
          if (excursion >= minAngleDelta) {
            _repCount += 1;
            final eccentricS = _phaseStartedAt != null && _bottomReachedAt != null
                ? _bottomReachedAt!.difference(_phaseStartedAt!).inMilliseconds / 1000
                : 0.0;
            final concentricS = _bottomReachedAt != null ? now.difference(_bottomReachedAt!).inMilliseconds / 1000 : 0.0;
            final thresholdGap = topThreshold - bottomThreshold;
            final romPct = thresholdGap <= 0 ? 0.0 : (excursion / thresholdGap * 100).clamp(0, 150).toDouble();
            onRepCompleted?.call(
              RepResult(
                index: _repCount,
                romPct: romPct,
                tempoEccentricSeconds: eccentricS,
                tempoConcentricSeconds: concentricS,
              ),
            );
          }
          // Reset for the next rep regardless of whether this one counted,
          // so a shallow dip near the bottom line can't permanently wedge
          // the counter in `atBottom`.
          _phase = _Phase.atTop;
          _phaseStartedAt = now;
          _topValueThisRep = value;
          _bottomValueThisRep = null;
          _bottomReachedAt = null;
        }
    }
  }

  double? _extract(JointAngles angles) {
    switch (drivingJoint) {
      case RepDrivingJoint.elbow:
        return angles.elbowAngleDeg;
      case RepDrivingJoint.hip:
        return angles.hipAngleDeg;
      case RepDrivingJoint.knee:
        return angles.kneeAngleDeg;
      case RepDrivingJoint.barHeight:
        return angles.barHeightNormalized;
    }
  }

  /// Resets rep count and in-progress phase tracking (e.g. when starting a
  /// new set with the same [RepCounter] instance).
  void reset() {
    _phase = _Phase.atTop;
    _repCount = 0;
    _phaseStartedAt = null;
    _bottomReachedAt = null;
    _topValueThisRep = null;
    _bottomValueThisRep = null;
  }
}
