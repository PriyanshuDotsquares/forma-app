import 'dart:math' as math;

import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../../../camera_coach/domain/form_heuristics.dart';
import '../../../camera_coach/domain/rep_counter.dart';

/// Bridges ML Kit's [Pose] to the camera-coach engine's camera-agnostic
/// [JointAngles]. This is the one file in the workout feature that imports
/// both ML Kit pose types and the pure `camera_coach/domain` types —
/// everything downstream of [jointAnglesFromPose] (RepCounter,
/// FormHeuristics) only ever sees [JointAngles], which is what keeps those
/// two testable without a camera.
const double _minLikelihood = 0.5;

bool _confident(PoseLandmark? landmark) => landmark != null && landmark.likelihood >= _minLikelihood;

/// The interior angle at [b] of the triangle a-b-c, in degrees, using 2D
/// image-plane coordinates (ML Kit's x/y are pixel coordinates in the
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

double? _jointAngle(Pose pose, PoseLandmarkType a, PoseLandmarkType b, PoseLandmarkType c) {
  final la = pose.landmarks[a];
  final lb = pose.landmarks[b];
  final lc = pose.landmarks[c];
  if (!_confident(la) || !_confident(lb) || !_confident(lc)) return null;
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
}) {
  final left = _jointAngle(pose, leftA, leftB, leftC);
  final right = _jointAngle(pose, rightA, rightB, rightC);
  if (left != null && right != null) return (left + right) / 2;
  return left ?? right;
}

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

JointAngles jointAnglesFromPose(Pose pose) {
  return JointAngles(
    elbowAngleDeg: _averagedAngle(
      pose,
      leftA: PoseLandmarkType.leftShoulder,
      leftB: PoseLandmarkType.leftElbow,
      leftC: PoseLandmarkType.leftWrist,
      rightA: PoseLandmarkType.rightShoulder,
      rightB: PoseLandmarkType.rightElbow,
      rightC: PoseLandmarkType.rightWrist,
    ),
    hipAngleDeg: _averagedAngle(
      pose,
      leftA: PoseLandmarkType.leftShoulder,
      leftB: PoseLandmarkType.leftHip,
      leftC: PoseLandmarkType.leftKnee,
      rightA: PoseLandmarkType.rightShoulder,
      rightB: PoseLandmarkType.rightHip,
      rightC: PoseLandmarkType.rightKnee,
    ),
    kneeAngleDeg: _averagedAngle(
      pose,
      leftA: PoseLandmarkType.leftHip,
      leftB: PoseLandmarkType.leftKnee,
      leftC: PoseLandmarkType.leftAnkle,
      rightA: PoseLandmarkType.rightHip,
      rightB: PoseLandmarkType.rightKnee,
      rightC: PoseLandmarkType.rightAnkle,
    ),
    barHeightNormalized: _barHeightNormalized(pose),
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
    case MovementPattern.generic:
      return const RepCounterConfig(drivingJoint: RepDrivingJoint.elbow, bottomThreshold: 90, topThreshold: 150);
  }
}
