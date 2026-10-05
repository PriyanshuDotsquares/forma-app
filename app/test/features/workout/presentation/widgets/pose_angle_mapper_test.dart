import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:forma/features/camera_coach/data/mediapipe/pose_types.dart';
import 'package:forma/features/workout/presentation/widgets/pose_angle_mapper.dart';

PoseLandmark _lm(double x, double y, {double likelihood = 0.95}) {
  return PoseLandmark(type: PoseLandmarkType.nose, x: x, y: y, z: 0, likelihood: likelihood);
}

/// A plausible, side-on standing pose in a 1000x1000 pixel frame: shoulder
/// directly above hip (torso length 200px), then a straight leg down to the
/// ankle — a believable knee angle near full extension.
Pose _standingPose({double kneeX = 500, double kneeY = 700, double ankleX = 500, double ankleY = 900}) {
  return Pose(
    landmarks: {
      PoseLandmarkType.leftShoulder: _lm(500, 300),
      PoseLandmarkType.rightShoulder: _lm(520, 300),
      PoseLandmarkType.leftHip: _lm(500, 500),
      PoseLandmarkType.rightHip: _lm(520, 500),
      PoseLandmarkType.leftKnee: _lm(kneeX, kneeY),
      PoseLandmarkType.rightKnee: _lm(kneeX + 20, kneeY),
      PoseLandmarkType.leftAnkle: _lm(ankleX, ankleY),
      PoseLandmarkType.rightAnkle: _lm(ankleX + 20, ankleY),
      PoseLandmarkType.leftElbow: _lm(450, 400),
      PoseLandmarkType.rightElbow: _lm(570, 400),
      PoseLandmarkType.leftWrist: _lm(430, 480),
      PoseLandmarkType.rightWrist: _lm(590, 480),
    },
  );
}

void main() {
  group('jointAnglesFromPose — geometric-plausibility gate', () {
    test('a normal standing pose yields a sensible (near-straight) knee angle', () {
      final angles = jointAnglesFromPose(_standingPose());
      expect(angles.kneeAngleDeg, isNotNull);
      expect(angles.kneeAngleDeg!, greaterThan(150));
    });

    test('rejects a confidently-detected but anatomically-collapsed knee/ankle reading', () {
      // Knee and ankle landmarks sit a few pixels apart — MediaPipe reporting
      // high confidence for a physically impossible cluster (the real bug
      // this gate was written to catch), rather than reporting low
      // visibility for an occluded joint.
      final angles = jointAnglesFromPose(_standingPose(kneeX: 500, kneeY: 700, ankleX: 505, ankleY: 703));
      expect(angles.kneeAngleDeg, isNull);
    });

    test('does not reject a genuinely deep squat (short but anatomically plausible segments)', () {
      // A believable deep-squat knee: hip-to-knee and knee-to-ankle segments
      // shrink in the image plane as the camera foreshortens them, but stay
      // well above the collapsed-cluster ratio floor.
      final angles = jointAnglesFromPose(_standingPose(kneeX: 500, kneeY: 620, ankleX: 500, ankleY: 780));
      expect(angles.kneeAngleDeg, isNotNull);
    });

    test('skips the gate (falls back to confidence-only) when torso landmarks are not visible', () {
      final pose = Pose(
        landmarks: {
          // Hips are present (the knee angle's triple needs them), but no
          // shoulders -> no torso scale (shoulder-to-hip) to check against.
          PoseLandmarkType.leftHip: _lm(500, 500),
          PoseLandmarkType.rightHip: _lm(520, 500),
          PoseLandmarkType.leftKnee: _lm(500, 700),
          PoseLandmarkType.rightKnee: _lm(520, 700),
          PoseLandmarkType.leftAnkle: _lm(505, 703),
          PoseLandmarkType.rightAnkle: _lm(525, 703),
        },
      );
      final angles = jointAnglesFromPose(pose);
      // Still computed — with no torso reference, an otherwise-implausible
      // reading is not silently dropped; confidence gating alone applies.
      expect(angles.kneeAngleDeg, isNotNull);
    });
  });

  group('jointAnglesFromPose — outOfFrame', () {
    test('flags a landmark sitting within the edge margin of the frame', () {
      final pose = _standingPose().landmarks;
      final edgePose = Pose(
        landmarks: {
          ...pose,
          // Push a tracked landmark (wrist) right up against the left edge.
          PoseLandmarkType.leftWrist: _lm(5, 480),
        },
      );
      final angles = jointAnglesFromPose(edgePose, imageSize: const Size(1000, 1000));
      expect(angles.outOfFrame, isTrue);
    });

    test('does not flag a pose comfortably inside the frame', () {
      final angles = jointAnglesFromPose(_standingPose(), imageSize: const Size(1000, 1000));
      expect(angles.outOfFrame, isFalse);
    });

    test('skips the check entirely when no imageSize is supplied', () {
      final pose = _standingPose().landmarks;
      final edgePose = Pose(landmarks: {...pose, PoseLandmarkType.leftWrist: _lm(1, 1)});
      final angles = jointAnglesFromPose(edgePose);
      expect(angles.outOfFrame, isFalse);
    });
  });
}
