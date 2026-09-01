import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/router/app_router.dart';
import '../../camera_coach/data/pose_service.dart';
import 'workout_providers.dart';

/// Live-computed checklist status for the precheck screen, derived from the
/// most recent detected pose against the current camera frame — not a
/// hardcoded set of green checks. Each signal is a simplified heuristic
/// (documented per-field below), not a precise measurement.
class _PrecheckStatus {
  const _PrecheckStatus({
    required this.fullBodyInFrame,
    required this.sideViewDetected,
    required this.tooClose,
    required this.lightingGood,
  });

  final bool fullBodyInFrame;
  final bool sideViewDetected;
  final bool tooClose;
  final bool lightingGood;

  static const none = _PrecheckStatus(fullBodyInFrame: false, sideViewDetected: false, tooClose: false, lightingGood: false);
}

_PrecheckStatus _evaluate(Pose? pose, Size imageSize) {
  if (pose == null || imageSize.isEmpty) return _PrecheckStatus.none;

  final confident = pose.landmarks.values.where((l) => l.likelihood >= 0.5).toList();
  if (confident.length < 15) return _PrecheckStatus.none;

  final minY = confident.map((l) => l.y).reduce(math.min);
  final maxY = confident.map((l) => l.y).reduce(math.max);
  // "Full body in frame": the confident landmarks' vertical bounding box
  // spans at least 60% of the frame height, with a small margin from the
  // top/bottom edges (a body cropped at the edges reads as "too close").
  final heightFraction = ((maxY - minY) / imageSize.height).clamp(0.0, 2.0);
  final nearTopEdge = minY <= imageSize.height * 0.02;
  final nearBottomEdge = maxY >= imageSize.height * 0.98;
  final spansFrame = heightFraction >= 0.6;

  // "Side view": in profile, the left/right shoulders (and hips) project
  // close together on the horizontal axis relative to the body's height,
  // since both sides sit at roughly the same depth from the camera.
  final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
  final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];
  var sideView = false;
  if (leftShoulder != null &&
      rightShoulder != null &&
      leftShoulder.likelihood >= 0.5 &&
      rightShoulder.likelihood >= 0.5 &&
      (maxY - minY) > 0) {
    final shoulderWidth = (leftShoulder.x - rightShoulder.x).abs();
    sideView = (shoulderWidth / (maxY - minY)) < 0.22;
  }

  // "Lighting looks good": ML Kit's per-landmark confidence tends to drop
  // in poor lighting/high noise even when the subject is fully in frame —
  // a proxy for image quality, not a true lux measurement.
  final avgLikelihood = confident.map((l) => l.likelihood).reduce((a, b) => a + b) / confident.length;

  return _PrecheckStatus(
    fullBodyInFrame: spansFrame && !nearTopEdge && !nearBottomEdge,
    sideViewDetected: sideView,
    tooClose: spansFrame && (nearTopEdge || nearBottomEdge),
    lightingGood: avgLikelihood >= 0.7,
  );
}

class CameraPrecheckScreen extends ConsumerStatefulWidget {
  const CameraPrecheckScreen({super.key, required this.sessionId, this.programExerciseId});

  final String sessionId;
  final String? programExerciseId;

  @override
  ConsumerState<CameraPrecheckScreen> createState() => _CameraPrecheckScreenState();
}

class _CameraPrecheckScreenState extends ConsumerState<CameraPrecheckScreen> {
  final PoseCoachService _poseService = PoseCoachService();
  bool _initializing = true;
  PoseServiceInitResult? _initResult;
  Pose? _latestPose;
  Size? _imageSize;
  // Set the instant we start tearing down the camera, on any exit path.
  // `CameraController.dispose()` posts a value-change notification that
  // `CameraPreview`'s `ValueListenableBuilder` is still subscribed to
  // until the widget is actually unmounted — without this guard, a stray
  // rebuild in that window calls `buildPreview()` on an already-disposed
  // controller and crashes with `CameraException(Disposed
  // CameraController, ...)`. Also guards against disposing twice (once
  // from an explicit `_leave()` call, once from `State.dispose()`'s
  // fallback for exits that don't go through `_leave()`, e.g. a
  // system back-swipe).
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final result = await _poseService.initialize();
    if (!mounted) return;

    if (result == PoseServiceInitResult.ready) {
      final previewSize = _poseService.controller.value.previewSize;
      final sensorOrientation = _poseService.controller.description.sensorOrientation;
      setState(() {
        _initResult = result;
        _initializing = false;
        _imageSize = previewSize == null
            ? null
            : (sensorOrientation % 180 == 90 ? Size(previewSize.height, previewSize.width) : previewSize);
      });
      _poseService.startStream((pose) {
        if (!mounted) return;
        setState(() => _latestPose = pose);
      });
    } else {
      setState(() {
        _initResult = result;
        _initializing = false;
      });
    }
  }

  Future<void> _switchCamera() async {
    await _poseService.switchCamera();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    // Fallback for exits that skip `_leave()` (e.g. a system back-swipe).
    // If `_leave()` already started the async teardown, `_leaving` is
    // already true and `_poseService.dispose()` is safe to call again —
    // it no-ops once `_controller` is already null.
    if (!_leaving) unawaited(_poseService.dispose());
    super.dispose();
  }

  Future<void> _leave() async {
    if (_leaving) return;
    setState(() => _leaving = true);
    await _poseService.dispose();
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.workoutActive(widget.sessionId));
    }
  }

  void _confirmAndContinue() {
    // `programExerciseId` is threaded through purely so a future backend
    // integration can log which prescribed exercise this coached set
    // belongs to; the live-tracking handoff itself is keyed by session —
    // see `pendingCameraCoachProvider`'s doc comment for why.
    ref.read(pendingCameraCoachProvider.notifier).state = widget.sessionId;
    _leave();
  }

  @override
  Widget build(BuildContext context) {
    if (_initializing || _leaving) {
      return const Scaffold(backgroundColor: AppColors.surfaceLowest, body: Center(child: CircularProgressIndicator()));
    }

    if (_initResult == PoseServiceInitResult.permissionDenied) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: FormaEmptyState(
                icon: Icons.videocam_off_outlined,
                title: 'Camera access is off.',
                message: 'FORMA needs the camera to count your reps. Nothing is ever uploaded.',
                primaryLabel: 'OPEN SETTINGS',
                onPrimary: () => openAppSettings(),
                secondaryLabel: 'KEEP LOGGING MANUALLY',
                onSecondary: _leave,
              ),
            ),
          ),
        ),
      );
    }

    if (_initResult == PoseServiceInitResult.noCameraAvailable) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: FormaEmptyState(
                icon: Icons.videocam_off_outlined,
                title: 'No camera available.',
                message: "We couldn't find a working camera on this device. You can still log this set manually.",
                primaryLabel: 'KEEP LOGGING MANUALLY',
                onPrimary: _leave,
              ),
            ),
          ),
        ),
      );
    }

    final status = _evaluate(_latestPose, _imageSize ?? Size.zero);

    return Scaffold(
      backgroundColor: AppColors.surfaceLowest,
      body: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(_poseService.controller),
          const Positioned.fill(child: CustomPaint(painter: _SilhouetteGuidePainter())),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                  child: Row(
                    children: [
                      IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: _leave),
                      const Spacer(),
                      IconButton(icon: const Icon(Icons.cameraswitch_outlined, color: Colors.white), onPressed: _switchCamera),
                    ],
                  ),
                ),
                const Spacer(),
                Container(
                  margin: const EdgeInsets.all(AppSpacing.md),
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    border: Border.all(color: AppColors.outlineVariant),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ChecklistRow(label: 'Full body in frame', ok: status.fullBodyInFrame),
                      _ChecklistRow(label: 'Side view detected', ok: status.sideViewDetected),
                      if (status.tooClose) const _ChecklistRow(label: 'Move back about one step', ok: false, isWarning: true),
                      _ChecklistRow(label: 'Lighting looks good', ok: status.lightingGood),
                      const SizedBox(height: AppSpacing.md),
                      FilledButton(onPressed: _confirmAndContinue, child: const Text("I'M READY")),
                      const SizedBox(height: AppSpacing.xs),
                      Center(child: TextButton(onPressed: _leave, child: const Text('Skip camera for this set'))),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChecklistRow extends StatelessWidget {
  const _ChecklistRow({required this.label, required this.ok, this.isWarning = false});

  final String label;
  final bool ok;
  final bool isWarning;

  @override
  Widget build(BuildContext context) {
    final color = isWarning ? AppColors.accentAmber : (ok ? AppColors.accentGreen : AppColors.textMuted);
    final icon = isWarning ? Icons.warning_amber_rounded : (ok ? Icons.check_circle : Icons.radio_button_unchecked);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(label, style: AppTypography.body(size: 13, color: isWarning ? AppColors.accentAmber : AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}

/// A static dashed body-silhouette guide (head + torso capsule) — purely a
/// framing aid, not derived from the live pose.
class _SilhouetteGuidePainter extends CustomPainter {
  const _SilhouetteGuidePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.textMuted.withValues(alpha: 0.6)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final centerX = size.width / 2;
    final headRadius = size.width * 0.09;
    final headCenterY = size.height * 0.22;
    final bodyTop = headCenterY + headRadius * 1.2;
    final bodyBottom = size.height * 0.86;
    final bodyWidth = size.width * 0.42;

    final headPath = Path()..addOval(Rect.fromCircle(center: Offset(centerX, headCenterY), radius: headRadius));
    final bodyRect = Rect.fromLTRB(centerX - bodyWidth / 2, bodyTop, centerX + bodyWidth / 2, bodyBottom);
    final bodyPath = Path()..addRRect(RRect.fromRectAndRadius(bodyRect, Radius.circular(bodyWidth * 0.3)));

    _drawDashed(canvas, headPath, paint);
    _drawDashed(canvas, bodyPath, paint);
  }

  void _drawDashed(Canvas canvas, Path path, Paint paint, {double dashLength = 8, double gapLength = 6}) {
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = math.min(distance + dashLength, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SilhouetteGuidePainter oldDelegate) => false;
}
