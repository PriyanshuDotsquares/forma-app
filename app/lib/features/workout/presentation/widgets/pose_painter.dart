import 'package:flutter/material.dart';
import '../../../camera_coach/data/mediapipe/pose_types.dart';

import '../../../../core/design_system/design_system.dart';

enum _JointGroup { elbow, hip, knee, other }

class _Bone {
  const _Bone(this.a, this.b, this.group);
  final PoseLandmarkType a;
  final PoseLandmarkType b;
  final _JointGroup group;
}

/// Line segments making up a simple stick-figure skeleton, tagged with
/// which joint group (matching `FormSnapshot`'s flagged-joint booleans)
/// governs that segment's color.
const _skeleton = <_Bone>[
  _Bone(PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder, _JointGroup.other),
  _Bone(PoseLandmarkType.leftHip, PoseLandmarkType.rightHip, _JointGroup.other),
  _Bone(PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip, _JointGroup.hip),
  _Bone(PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip, _JointGroup.hip),
  _Bone(PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow, _JointGroup.elbow),
  _Bone(PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist, _JointGroup.elbow),
  _Bone(PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow, _JointGroup.elbow),
  _Bone(PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist, _JointGroup.elbow),
  _Bone(PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee, _JointGroup.knee),
  _Bone(PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle, _JointGroup.knee),
  _Bone(PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee, _JointGroup.knee),
  _Bone(PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle, _JointGroup.knee),
];

/// Draws a simple skeleton overlay from a [Pose]'s landmarks: straight line
/// segments between joint pairs, colored red where form heuristics flagged
/// that joint group this frame, green otherwise — with small blue dots at
/// every confident landmark.
///
/// This is a coaching overlay, not a pixel-exact reprojection: landmark
/// x/y (in the "upright" coordinate space the pose detector reports for the
/// rotation it was given) are scaled independently per axis to
/// fill [size], which assumes the preview beneath it fills its bounds the
/// same way. Good enough for "does the line roughly track the limb", not
/// meant to survive scrutiny at the pixel level.
class PoseSkeletonPainter extends CustomPainter {
  const PoseSkeletonPainter({
    required this.pose,
    required this.imageSize,
    required this.mirror,
    this.flaggedElbow = false,
    this.flaggedHip = false,
    this.flaggedKnee = false,
  });

  final Pose? pose;
  final Size imageSize;
  final bool mirror;
  final bool flaggedElbow;
  final bool flaggedHip;
  final bool flaggedKnee;

  Offset _project(PoseLandmark landmark, Size canvasSize) {
    final scaleX = canvasSize.width / imageSize.width;
    final scaleY = canvasSize.height / imageSize.height;
    final x = mirror ? canvasSize.width - landmark.x * scaleX : landmark.x * scaleX;
    return Offset(x, landmark.y * scaleY);
  }

  bool _isFlagged(_JointGroup group) {
    switch (group) {
      case _JointGroup.elbow:
        return flaggedElbow;
      case _JointGroup.hip:
        return flaggedHip;
      case _JointGroup.knee:
        return flaggedKnee;
      case _JointGroup.other:
        return false;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final pose = this.pose;
    if (pose == null || imageSize.isEmpty) return;

    for (final bone in _skeleton) {
      final la = pose.landmarks[bone.a];
      final lb = pose.landmarks[bone.b];
      if (la == null || lb == null || la.likelihood < 0.4 || lb.likelihood < 0.4) continue;
      final paint = Paint()
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..color = _isFlagged(bone.group) ? AppColors.accentRed : AppColors.accentGreen;
      canvas.drawLine(_project(la, size), _project(lb, size), paint);
    }

    final dotPaint = Paint()..color = AppColors.accentBlue;
    for (final landmark in pose.landmarks.values) {
      if (landmark.likelihood < 0.4) continue;
      canvas.drawCircle(_project(landmark, size), 3, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant PoseSkeletonPainter oldDelegate) =>
      oldDelegate.pose != pose ||
      oldDelegate.flaggedElbow != flaggedElbow ||
      oldDelegate.flaggedHip != flaggedHip ||
      oldDelegate.flaggedKnee != flaggedKnee;
}
