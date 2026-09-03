/// Dart-side mirror of MediaPipe Tasks Vision's Pose Landmarker output,
/// shaped to match `google_mlkit_pose_detection`'s `Pose`/`PoseLandmark`/
/// `PoseLandmarkType` API exactly (a `Map<PoseLandmarkType, PoseLandmark>`,
/// with `PoseLandmark.x`/`.y`/`.likelihood`). Every other file in this app
/// that consumes a pose (`pose_angle_mapper.dart`, `pose_painter.dart`,
/// `live_tracking_overlay.dart`, `camera_precheck_screen.dart`) was written
/// against that shape, so keeping it identical here means those files only
/// need an import swap — see `mediapipe_pose_detector.dart` for where these
/// values actually get constructed from the native platform-channel result.
library;

/// BlazePose's 33 landmarks, in the fixed index order MediaPipe reports
/// them in (index 0 = [nose] ... index 32 = [rightFootIndex]) — this order
/// matters: `MediaPipePoseDetector` builds this map via
/// `PoseLandmarkType.values[index]`, so it must stay in sync with the
/// native side's landmark list order, not be reordered for readability.
enum PoseLandmarkType {
  nose,
  leftEyeInner,
  leftEye,
  leftEyeOuter,
  rightEyeInner,
  rightEye,
  rightEyeOuter,
  leftEar,
  rightEar,
  leftMouth,
  rightMouth,
  leftShoulder,
  rightShoulder,
  leftElbow,
  rightElbow,
  leftWrist,
  rightWrist,
  leftPinky,
  rightPinky,
  leftIndex,
  rightIndex,
  leftThumb,
  rightThumb,
  leftHip,
  rightHip,
  leftKnee,
  rightKnee,
  leftAnkle,
  rightAnkle,
  leftHeel,
  rightHeel,
  leftFootIndex,
  rightFootIndex,
}

/// One detected landmark. [x]/[y] are in the input image's pixel space
/// (the native side scales MediaPipe's normalized 0..1 coordinates by the
/// frame's width/height before crossing the platform channel, so callers
/// never see normalized values) — the same pixel-space contract ML Kit's
/// `PoseLandmark` used. [z] is a rough relative depth, same scale as [x],
/// unused by this app's 2D joint-angle math. [likelihood] mirrors
/// MediaPipe's per-landmark `visibility` score (defaults to 1.0 if the
/// native side didn't report one) — how confident the model is that this
/// point is actually visible, not occluded.
class PoseLandmark {
  const PoseLandmark({required this.type, required this.x, required this.y, required this.z, required this.likelihood});

  final PoseLandmarkType type;
  final double x;
  final double y;
  final double z;
  final double likelihood;
}

/// One frame's full set of detected landmarks.
class Pose {
  const Pose({required this.landmarks});

  final Map<PoseLandmarkType, PoseLandmark> landmarks;
}
