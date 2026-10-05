import 'dart:math' as math;
import 'dart:ui' show Size;

import '../../../camera_coach/data/mediapipe/pose_types.dart';
import '../../../camera_coach/domain/form_heuristics.dart';
import '../../../camera_coach/domain/rep_counter.dart';

/// Bridges MediaPipe's [Pose] to the camera-coach engine's camera-agnostic
/// [JointAngles]. This is the one file in the workout feature that imports
/// both the pose types and the pure `camera_coach/domain` types —
/// everything downstream of [jointAnglesFromPose] (RepCounter,
/// FormHeuristics) only ever sees [JointAngles], which is what keeps those
/// two testable without a camera.
const double _minLikelihood = 0.5;

/// How far outside a segment's plausible length — expressed as a multiple
/// of the lifter's own torso length (shoulder-to-hip), so it holds up
/// across camera distances — a joint-triple reading is allowed to be
/// before it's treated as a bad detection rather than a real pose. Guards
/// against exactly the failure mode a visibility/confidence check alone
/// misses: MediaPipe reporting high confidence for landmarks that have
/// collapsed into an anatomically-impossible cluster (e.g. a "knee" and
/// "ankle" a few pixels apart), which reads as a valid but wildly wrong
/// angle instead of a missing one.
const double _minSegmentToTorsoRatio = 0.12;
const double _maxSegmentToTorsoRatio = 3.5;

/// How close to the camera frame's edge (as a fraction of width/height) a
/// landmark can sit before it's treated as [JointAngles.outOfFrame] —
/// MediaPipe keeps extrapolating a confident position for a joint for a
/// few frames after it's stepped out of shot, so this catches what a
/// confidence check alone doesn't.
const double _outOfFrameMargin = 0.02;

bool _confident(PoseLandmark? landmark) => landmark != null && landmark.likelihood >= _minLikelihood;

double _distance(PoseLandmark a, PoseLandmark b) {
  final dx = a.x - b.x, dy = a.y - b.y;
  return math.sqrt(dx * dx + dy * dy);
}

/// The lifter's torso length this frame (shoulder-to-hip), averaged across
/// whichever side(s) are confidently visible — the stable reference every
/// joint-triple's segment lengths are checked against, since it's rigid
/// and (for a roughly side-on or front-on camera) preserved under
/// perspective the way a pose-dependent measurement wouldn't be. `null`
/// when neither side is visible, in which case the geometric-plausibility
/// gate is skipped for this frame (falling back to confidence-only
/// gating) rather than rejecting everything.
double? _torsoScale(Pose pose) {
  final lengths = <double>[];
  final ls = pose.landmarks[PoseLandmarkType.leftShoulder];
  final lh = pose.landmarks[PoseLandmarkType.leftHip];
  if (_confident(ls) && _confident(lh)) lengths.add(_distance(ls!, lh!));
  final rs = pose.landmarks[PoseLandmarkType.rightShoulder];
  final rh = pose.landmarks[PoseLandmarkType.rightHip];
  if (_confident(rs) && _confident(rh)) lengths.add(_distance(rs!, rh!));
  if (lengths.isEmpty) return null;
  return lengths.reduce((a, b) => a + b) / lengths.length;
}

/// The interior angle at [b] of the triangle a-b-c, in degrees, using 2D
/// image-plane coordinates (the pose detector's x/y are pixel coordinates in the
/// input image; z is a rough relative depth we don't attempt to use here —
/// 2D is a reasonable approximation for a coaching heuristic viewed from a
/// roughly side-on or front-on camera).
double? _angleAt(PoseLandmark a, PoseLandmark b, PoseLandmark c) {
  final abx = a.x - b.x, aby = a.y - b.y;
  final cbx = c.x - b.x, cby = c.y - b.y;
  final magAB = math.sqrt(abx * abx + aby * aby);
  final magCB = math.sqrt(cbx * cbx + cby * cby);
  if (magAB == 0 || magCB == 0) return null;
  final cosAngle = ((abx * cbx + aby * cby) / (magAB * magCB)).clamp(-1.0, 1.0);
  return math.acos(cosAngle) * 180 / math.pi;
}

double? _jointAngle(Pose pose, PoseLandmarkType a, PoseLandmarkType b, PoseLandmarkType c, double? torsoScale) {
  final la = pose.landmarks[a];
  final lb = pose.landmarks[b];
  final lc = pose.landmarks[c];
  if (!_confident(la) || !_confident(lb) || !_confident(lc)) return null;
  if (torsoScale != null && torsoScale > 0) {
    final ratioAB = _distance(la!, lb!) / torsoScale;
    final ratioBC = _distance(lb, lc!) / torsoScale;
    final plausible =
        ratioAB >= _minSegmentToTorsoRatio &&
        ratioAB <= _maxSegmentToTorsoRatio &&
        ratioBC >= _minSegmentToTorsoRatio &&
        ratioBC <= _maxSegmentToTorsoRatio;
    if (!plausible) return null;
  }
  return _angleAt(la!, lb!, lc!);
}

/// Averages the left- and right-side reading for a joint when both sides
/// are confidently visible (steadier against single-side occlusion or
/// noise); falls back to whichever single side is visible, or `null` if
/// neither is.
double? _averagedAngle(
  Pose pose, {
  required PoseLandmarkType leftA,
  required PoseLandmarkType leftB,
  required PoseLandmarkType leftC,
  required PoseLandmarkType rightA,
  required PoseLandmarkType rightB,
  required PoseLandmarkType rightC,
  required double? torsoScale,
}) {
  final left = _jointAngle(pose, leftA, leftB, leftC, torsoScale);
  final right = _jointAngle(pose, rightA, rightB, rightC, torsoScale);
  if (left != null && right != null) return (left + right) / 2;
  return left ?? right;
}

/// Every landmark that any of the driving/scored joint-triples uses —
/// checked for edge-clipping to compute [JointAngles.outOfFrame].
const List<PoseLandmarkType> _trackedLandmarks = [
  PoseLandmarkType.leftShoulder,
  PoseLandmarkType.rightShoulder,
  PoseLandmarkType.leftElbow,
  PoseLandmarkType.rightElbow,
  PoseLandmarkType.leftWrist,
  PoseLandmarkType.rightWrist,
  PoseLandmarkType.leftHip,
  PoseLandmarkType.rightHip,
  PoseLandmarkType.leftKnee,
  PoseLandmarkType.rightKnee,
  PoseLandmarkType.leftAnkle,
  PoseLandmarkType.rightAnkle,
];

bool _isOutOfFrame(Pose pose, Size? imageSize) => _anyLandmarkOutOfFrame(pose, imageSize, _trackedLandmarks);

bool _anyLandmarkOutOfFrame(Pose pose, Size? imageSize, List<PoseLandmarkType> landmarks) {
  if (imageSize == null || imageSize.width <= 0 || imageSize.height <= 0) return false;
  final marginX = imageSize.width * _outOfFrameMargin;
  final marginY = imageSize.height * _outOfFrameMargin;
  for (final type in landmarks) {
    final landmark = pose.landmarks[type];
    if (!_confident(landmark)) continue;
    final x = landmark!.x, y = landmark.y;
    if (x <= marginX || x >= imageSize.width - marginX || y <= marginY || y >= imageSize.height - marginY) {
      return true;
    }
  }
  return false;
}

/// Just the landmarks feeding [joint]'s own angle triple (both sides) —
/// unlike [_isOutOfFrame]/[JointAngles.outOfFrame], which considers every
/// tracked landmark and is meant for the general "step back into frame"
/// voice cue. A bench press (elbow-driven) routinely has its legs cropped
/// out of shot or resting near the frame edge, which is irrelevant to
/// whether the elbow angle is trustworthy — gating the rep counter on the
/// blanket flag would wrongly stall counting for the whole set.
List<PoseLandmarkType> _landmarksFor(RepDrivingJoint joint) {
  switch (joint) {
    case RepDrivingJoint.elbow:
      return const [
        PoseLandmarkType.leftShoulder,
        PoseLandmarkType.rightShoulder,
        PoseLandmarkType.leftElbow,
        PoseLandmarkType.rightElbow,
        PoseLandmarkType.leftWrist,
        PoseLandmarkType.rightWrist,
      ];
    case RepDrivingJoint.hip:
      return const [
        PoseLandmarkType.leftShoulder,
        PoseLandmarkType.rightShoulder,
        PoseLandmarkType.leftHip,
        PoseLandmarkType.rightHip,
        PoseLandmarkType.leftKnee,
        PoseLandmarkType.rightKnee,
      ];
    case RepDrivingJoint.knee:
      return const [
        PoseLandmarkType.leftHip,
        PoseLandmarkType.rightHip,
        PoseLandmarkType.leftKnee,
        PoseLandmarkType.rightKnee,
        PoseLandmarkType.leftAnkle,
        PoseLandmarkType.rightAnkle,
      ];
    case RepDrivingJoint.shoulder:
      return const [
        PoseLandmarkType.leftElbow,
        PoseLandmarkType.rightElbow,
        PoseLandmarkType.leftShoulder,
        PoseLandmarkType.rightShoulder,
        PoseLandmarkType.leftHip,
        PoseLandmarkType.rightHip,
      ];
    case RepDrivingJoint.barHeight:
      return const [
        PoseLandmarkType.leftShoulder,
        PoseLandmarkType.rightShoulder,
        PoseLandmarkType.leftWrist,
        PoseLandmarkType.rightWrist,
        PoseLandmarkType.leftAnkle,
        PoseLandmarkType.rightAnkle,
      ];
  }
}

/// Whether the specific landmarks driving [joint]'s rep-counting angle are
/// near the frame edge — see [_landmarksFor] for why this is scoped rather
/// than using the blanket [JointAngles.outOfFrame].
bool isDrivingJointOutOfFrame(Pose pose, Size? imageSize, RepDrivingJoint joint) =>
    _anyLandmarkOutOfFrame(pose, imageSize, _landmarksFor(joint));

double? _avgLandmarkY(Pose pose, PoseLandmarkType left, PoseLandmarkType right) {
  final l = pose.landmarks[left];
  final r = pose.landmarks[right];
  final ys = <double>[if (_confident(l)) l!.y, if (_confident(r)) r!.y];
  if (ys.isEmpty) return null;
  return ys.reduce((a, b) => a + b) / ys.length;
}

/// A 0 (ankle-height) .. ~1 (shoulder-height) proxy for hand/bar height,
/// self-normalized against the lifter's own shoulder-to-ankle span in this
/// frame (rather than needing the raw image dimensions) so it holds up
/// across camera distances.
double? _barHeightNormalized(Pose pose) {
  final shoulderY = _avgLandmarkY(pose, PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder);
  final ankleY = _avgLandmarkY(pose, PoseLandmarkType.leftAnkle, PoseLandmarkType.rightAnkle);
  final wristY = _avgLandmarkY(pose, PoseLandmarkType.leftWrist, PoseLandmarkType.rightWrist);
  if (shoulderY == null || ankleY == null || wristY == null || ankleY <= shoulderY) return null;
  // Image y grows downward, so a smaller y is physically higher.
  return ((ankleY - wristY) / (ankleY - shoulderY)).clamp(0.0, 1.5);
}

/// [imageSize] is the frame's display (upright, rotation-applied) pixel
/// size — the same value `PoseCoachService.lastFrameSize` reports — used
/// only to detect [JointAngles.outOfFrame]; the rest of this mapping is
/// resolution-independent. `null` skips that check (no rep-counting or
/// form-scoring behavior depends on it).
JointAngles jointAnglesFromPose(Pose pose, {Size? imageSize}) {
  final torsoScale = _torsoScale(pose);
  return JointAngles(
    elbowAngleDeg: _averagedAngle(
      pose,
      leftA: PoseLandmarkType.leftShoulder,
      leftB: PoseLandmarkType.leftElbow,
      leftC: PoseLandmarkType.leftWrist,
      rightA: PoseLandmarkType.rightShoulder,
      rightB: PoseLandmarkType.rightElbow,
      rightC: PoseLandmarkType.rightWrist,
      torsoScale: torsoScale,
    ),
    hipAngleDeg: _averagedAngle(
      pose,
      leftA: PoseLandmarkType.leftShoulder,
      leftB: PoseLandmarkType.leftHip,
      leftC: PoseLandmarkType.leftKnee,
      rightA: PoseLandmarkType.rightShoulder,
      rightB: PoseLandmarkType.rightHip,
      rightC: PoseLandmarkType.rightKnee,
      torsoScale: torsoScale,
    ),
    kneeAngleDeg: _averagedAngle(
      pose,
      leftA: PoseLandmarkType.leftHip,
      leftB: PoseLandmarkType.leftKnee,
      leftC: PoseLandmarkType.leftAnkle,
      rightA: PoseLandmarkType.rightHip,
      rightB: PoseLandmarkType.rightKnee,
      rightC: PoseLandmarkType.rightAnkle,
      torsoScale: torsoScale,
    ),
    shoulderAngleDeg: _averagedAngle(
      pose,
      leftA: PoseLandmarkType.leftElbow,
      leftB: PoseLandmarkType.leftShoulder,
      leftC: PoseLandmarkType.leftHip,
      rightA: PoseLandmarkType.rightElbow,
      rightB: PoseLandmarkType.rightShoulder,
      rightC: PoseLandmarkType.rightHip,
      torsoScale: torsoScale,
    ),
    barHeightNormalized: _barHeightNormalized(pose),
    outOfFrame: _isOutOfFrame(pose, imageSize),
  );
}

/// The [RepDrivingJoint] and bottom/top hysteresis thresholds
/// [RepCounter] should use for a given [MovementPattern]. Thresholds are
/// degrees for every current pattern (all drive off elbow/hip/knee, never
/// bar height) — see `camera_coach/domain/rep_counter.dart` for why the
/// bottom-then-top crossing shape works the same regardless of which
/// direction "down" moves the angle.
class RepCounterConfig {
  const RepCounterConfig({required this.drivingJoint, required this.bottomThreshold, required this.topThreshold});

  final RepDrivingJoint drivingJoint;
  final double bottomThreshold;
  final double topThreshold;
}

RepCounterConfig repCounterConfigFor(MovementPattern pattern) {
  switch (pattern) {
    case MovementPattern.squat:
      // Knee bends from ~170° standing to ~70-100° at depth.
      return const RepCounterConfig(drivingJoint: RepDrivingJoint.knee, bottomThreshold: 100, topThreshold: 160);
    case MovementPattern.hinge:
      // Hip closes from ~170° standing to ~45-100° at the bottom of a
      // hinge.
      return const RepCounterConfig(drivingJoint: RepDrivingJoint.hip, bottomThreshold: 90, topThreshold: 160);
    case MovementPattern.press:
      // Elbow closes from ~160°+ locked out to ~70-90° at the chest/racked
      // position.
      return const RepCounterConfig(drivingJoint: RepDrivingJoint.elbow, bottomThreshold: 90, topThreshold: 160);
    case MovementPattern.pull:
    case MovementPattern.bentOverRow:
      // Rows/curls/pulldowns: elbow closes from extended (~150°+) to a
      // contracted ~70-90° at the top of the pull. bentOverRow shares this
      // config — only the form-heuristic hip band differs for it (see
      // form_heuristics.dart).
      return const RepCounterConfig(drivingJoint: RepDrivingJoint.elbow, bottomThreshold: 90, topThreshold: 150);
    case MovementPattern.flyIsolation:
      // Fly/crossover/raise-type isolation moves: the elbow stays roughly
      // fixed throughout, so tracking it (like `press` does) barely crosses
      // any threshold. The shoulder angle (elbow-shoulder-hip) is what
      // actually swings — wide/extended arms read ~60-90°, arms
      // crossed/raised-in read ~10-30°.
      return const RepCounterConfig(drivingJoint: RepDrivingJoint.shoulder, bottomThreshold: 30, topThreshold: 60);
    case MovementPattern.generic:
      return const RepCounterConfig(drivingJoint: RepDrivingJoint.elbow, bottomThreshold: 90, topThreshold: 150);
  }
}
