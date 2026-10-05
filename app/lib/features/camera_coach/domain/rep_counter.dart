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
  const JointAngles({
    this.elbowAngleDeg,
    this.hipAngleDeg,
    this.kneeAngleDeg,
    this.shoulderAngleDeg,
    this.barHeightNormalized,
    this.outOfFrame = false,
  });

  final double? elbowAngleDeg;
  final double? hipAngleDeg;
  final double? kneeAngleDeg;

  /// Interior angle at the shoulder (elbow-shoulder-hip) — how far the arm
  /// is swung out from the torso. Unlike [elbowAngleDeg], this changes
  /// meaningfully for a fly/crossover/raise, where the elbow stays roughly
  /// fixed and the arm swings via shoulder horizontal ad/abduction instead.
  final double? shoulderAngleDeg;
  final double? barHeightNormalized;

  /// True when a landmark this frame's angles depend on sits within a thin
  /// margin of the camera frame's edge — MediaPipe keeps reporting a
  /// confident position for a joint for a few frames after it's actually
  /// stepped out of shot (extrapolating rather than admitting occlusion),
  /// so a confidence check alone doesn't catch it. Sourced from
  /// `pose_angle_mapper.dart`, which has the raw pixel coordinates and
  /// frame size needed to compute it; callers use it to prioritize a "step
  /// back into frame" cue over ordinary form feedback, since every other
  /// rule is meaningless on an extrapolated landmark.
  final bool outOfFrame;
}

/// Which single value in [JointAngles] a [RepCounter] watches to detect
/// reps. Everything else in [JointAngles] is still available to
/// `FormHeuristics` for scoring/cues — a rep can be *driven* by knee angle
/// while still being *graded* on hip angle, for example.
enum RepDrivingJoint { elbow, hip, knee, shoulder, barHeight }

/// The outcome of one completed rep.
class RepResult {
  const RepResult({
    required this.index,
    required this.romPct,
    required this.tempoEccentricSeconds,
    required this.tempoConcentricSeconds,
    this.bottomPauseSeconds = 0,
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

  /// Seconds the driving value took to *fall* from the top threshold to the
  /// bottom threshold. Pure travel time: rest at the top before the rep (and,
  /// on rep 1, the whole setup time) is not included.
  ///
  /// This is "the angle-falling phase", which is the lowering (eccentric)
  /// phase for a squat, hinge or press but the *pulling* (concentric) phase for
  /// a row, curl or pulldown, where closing the elbow is the effort. Map it to
  /// lowering/lifting with `RepTempo.fromRep` rather than reading it directly.
  final double tempoEccentricSeconds;

  /// Seconds the driving value took to *rise* from the bottom threshold back
  /// to the top threshold — the other half of [tempoEccentricSeconds], with the
  /// same caveat about which one is the lift. Excludes the pause at the bottom
  /// ([bottomPauseSeconds]) and the confirmation hold used to accept the rep.
  final double tempoConcentricSeconds;

  /// Seconds the value stayed beyond the bottom threshold — the pause at the
  /// bottom of a squat, or the held squeeze at the peak of a row.
  ///
  /// This is time *past the threshold*, so it includes roughly 0.3-0.5s of the
  /// movement itself even with no pause at all (the counter needs a dwell there
  /// to accept the rep). Treat only values well above that as a real pause; see
  /// `TempoSummary.minDeliberatePauseSeconds`.
  final double bottomPauseSeconds;
}

enum _Phase { atTop, atBottom }

double _median(List<double> values) {
  final sorted = List<double>.of(values)..sort();
  final n = sorted.length;
  if (n.isOdd) return sorted[n ~/ 2];
  return (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2;
}

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
///
/// Two more guards sit on top of that hysteresis, both aimed at the same
/// real-camera failure mode: a single noisy or briefly-extrapolated
/// MediaPipe frame (motion blur, a joint dipping under the landmark
/// confidence floor for one frame, a lighting flicker) reading a spurious
/// value that shouldn't by itself flip a phase, complete a rep, or corrupt
/// the recorded top/bottom of one:
///
/// - [smoothingWindow] runs the raw per-frame value through a trailing
///   *median* filter before anything else sees it. A median is preferred
///   over an average here because it fully rejects a single outlier
///   (unlike an exponential/rolling average, which still gets pulled
///   toward it) as long as fewer than half the window is bad — exactly the
///   "one spike mid-rep" shape a moving average lets through.
/// - [minPhaseHoldMs] requires the (smoothed) value to sit continuously
///   past a threshold for at least this long before the phase actually
///   flips, rather than reacting to the first sample that crosses it. A
///   single-frame blip that crosses a line and immediately bounces back
///   never accumulates enough dwell time to be treated as a real
///   transition.
///
/// The top/bottom values used for a completed rep's excursion and ROM% are
/// also no longer a raw running min/max — a single extreme noisy sample
/// used to permanently latch in as "how deep this rep was". Instead each
/// phase accumulates every (smoothed) sample seen during that dwell, and
/// the rep uses the *median* of each side's samples, which is far less
/// sensitive to one bad frame at the exact turnaround.
class RepCounter {
  RepCounter({
    required this.drivingJoint,
    required this.bottomThreshold,
    required this.topThreshold,
    this.minAngleDelta = 15,
    this.smoothingWindow = 5,
    this.minPhaseHoldMs = 250,
    this.onRepCompleted,
  }) : assert(bottomThreshold < topThreshold, 'bottomThreshold must be < topThreshold'),
       assert(smoothingWindow >= 1, 'smoothingWindow must be >= 1'),
       assert(minPhaseHoldMs >= 0, 'minPhaseHoldMs must be >= 0');

  final RepDrivingJoint drivingJoint;
  final double bottomThreshold;
  final double topThreshold;
  final double minAngleDelta;

  /// How many trailing raw samples the median filter looks at. 1 disables
  /// smoothing entirely (the raw value is used as-is).
  final int smoothingWindow;

  /// How long (in milliseconds) the smoothed value must sit continuously
  /// past a threshold before the phase transition is accepted. 0 disables
  /// this guard (matches a plain single-sample threshold crossing).
  final int minPhaseHoldMs;

  /// Called synchronously from [addSample] whenever a rep completes.
  void Function(RepResult result)? onRepCompleted;

  _Phase _phase = _Phase.atTop;
  int _repCount = 0;
  DateTime? _phaseStartedAt;
  DateTime? _bottomReachedAt;

  // Tempo bookkeeping. These are the *last* time the value was at each
  // extreme, not the first, so a rep's travel time is measured between the two
  // threshold crossings and excludes any rest or pause at either end.
  DateTime? _lastAtTopAt;
  DateTime? _lastAtBottomAt;

  final List<double> _rawWindow = [];
  final List<double> _topSamples = [];
  final List<double> _bottomSamples = [];

  // Candidate-transition tracking for the [minPhaseHoldMs] dwell guard.
  DateTime? _bottomCandidateAt;
  final List<double> _bottomCandidateSamples = [];
  DateTime? _topCandidateAt;
  final List<double> _topCandidateSamples = [];

  int get repCount => _repCount;

  /// Feeds one frame of joint angles. Frames where the driving value is
  /// unavailable (e.g. the joint was occluded) are ignored rather than
  /// resetting the state machine, so a brief dropout mid-rep doesn't cost
  /// the rep.
  void addSample(JointAngles angles, {DateTime? at}) {
    final raw = _extract(angles);
    if (raw == null) return;

    _rawWindow.add(raw);
    if (_rawWindow.length > smoothingWindow) {
      _rawWindow.removeAt(0);
    }
    final value = smoothingWindow <= 1 ? raw : _median(_rawWindow);

    final now = at ?? DateTime.now();
    _phaseStartedAt ??= now;

    switch (_phase) {
      case _Phase.atTop:
        if (value > bottomThreshold) {
          // Still genuinely at the top — a real sample for this rep's peak,
          // and not a candidate descent (in case we bounced back from one).
          _topSamples.add(value);
          if (value >= topThreshold) _lastAtTopAt = now;
          _bottomCandidateAt = null;
          _bottomCandidateSamples.clear();
        } else {
          _bottomCandidateAt ??= now;
          _bottomCandidateSamples.add(value);
          if (now.difference(_bottomCandidateAt!).inMilliseconds >= minPhaseHoldMs) {
            _phase = _Phase.atBottom;
            _bottomReachedAt = _bottomCandidateAt;
            _lastAtBottomAt = now;
            _bottomSamples
              ..clear()
              ..addAll(_bottomCandidateSamples);
            _bottomCandidateAt = null;
            _bottomCandidateSamples.clear();
          }
        }
      case _Phase.atBottom:
        if (value < topThreshold) {
          _bottomSamples.add(value);
          if (value <= bottomThreshold) _lastAtBottomAt = now;
          _topCandidateAt = null;
          _topCandidateSamples.clear();
        } else {
          _topCandidateAt ??= now;
          _topCandidateSamples.add(value);
          if (now.difference(_topCandidateAt!).inMilliseconds >= minPhaseHoldMs) {
            final top = _median(_topSamples.isNotEmpty ? _topSamples : [value]);
            final bottom = _median(_bottomSamples.isNotEmpty ? _bottomSamples : [value]);
            final excursion = top - bottom;
            if (excursion >= minAngleDelta) {
              _repCount += 1;
              // Travel time between the two threshold crossings, not between
              // "arrived at one end" and "arrived at the other": the lifter's
              // rest at the top (and, on rep 1, the setup before the first
              // movement) and the pause at the bottom are not part of the
              // tempo, and the confirmation hold used to accept a phase change
              // is not either. The "first sample at the extreme" timestamps
              // used previously folded all of those in.
              double secondsBetween(DateTime? from, DateTime? to) =>
                  from != null && to != null ? (to.difference(from).inMilliseconds / 1000).clamp(0.0, double.infinity).toDouble() : 0.0;
              final leftTopAt = _lastAtTopAt ?? _phaseStartedAt;
              final leftBottomAt = _lastAtBottomAt ?? _bottomReachedAt;
              final eccentricS = secondsBetween(leftTopAt, _bottomReachedAt);
              final bottomPauseS = secondsBetween(_bottomReachedAt, _lastAtBottomAt);
              final concentricS = secondsBetween(leftBottomAt, _topCandidateAt);
              final thresholdGap = topThreshold - bottomThreshold;
              final romPct = thresholdGap <= 0 ? 0.0 : (excursion / thresholdGap * 100).clamp(0, 150).toDouble();
              onRepCompleted?.call(
                RepResult(
                  index: _repCount,
                  romPct: romPct,
                  tempoEccentricSeconds: eccentricS,
                  tempoConcentricSeconds: concentricS,
                  bottomPauseSeconds: bottomPauseS,
                ),
              );
            }
            // Reset for the next rep regardless of whether this one
            // counted, so a shallow dip near the bottom line can't
            // permanently wedge the counter in `atBottom`.
            _phase = _Phase.atTop;
            _phaseStartedAt = _topCandidateAt;
            _topSamples
              ..clear()
              ..addAll(_topCandidateSamples);
            _bottomSamples.clear();
            _topCandidateAt = null;
            _topCandidateSamples.clear();
            _bottomReachedAt = null;
            // Back at the top: the next rep's descent is timed from the last
            // moment the value is still at/above the top threshold.
            _lastAtTopAt = now;
            _lastAtBottomAt = null;
          }
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
      case RepDrivingJoint.shoulder:
        return angles.shoulderAngleDeg;
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
    _lastAtTopAt = null;
    _lastAtBottomAt = null;
    _rawWindow.clear();
    _topSamples.clear();
    _bottomSamples.clear();
    _bottomCandidateAt = null;
    _bottomCandidateSamples.clear();
    _topCandidateAt = null;
    _topCandidateSamples.clear();
  }
}
