import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'pose_types.dart';

/// Thin Dart-side wrapper around the native MediaPipe Tasks Vision Pose
/// Landmarker, reached via a `MethodChannel` — there is no maintained
/// Flutter plugin for MediaPipe Tasks Vision with live-camera support, so
/// `ios/Runner/MediaPipePoseChannel.swift` and `android/.../
/// MediaPipePoseChannel.kt` implement the native half of this channel
/// directly. The native landmarker itself is a lazily-created singleton
/// per platform (see those files' doc comments for why), so [initialize]
/// is safe to call every time a new [MediaPipePoseDetector] is constructed
/// and [close] is a deliberate no-op — there is nothing per-instance to
/// free natively.
class MediaPipePoseDetector {
  MediaPipePoseDetector() : _channel = const MethodChannel('forma/pose_landmarker');

  final MethodChannel _channel;
  bool _initialized = false;

  /// Loads the pose-landmarker model natively, if not already loaded.
  /// Returns `false` (rather than throwing) on failure — e.g. the model
  /// asset is missing — so callers can fall back to a graceful no-camera
  /// state, matching this app's "never crash on a pose-detection failure"
  /// convention.
  Future<bool> initialize() async {
    if (_initialized) return true;
    try {
      await _channel.invokeMethod<void>('init');
      _initialized = true;
      return true;
    } catch (e) {
      debugPrint('MediaPipePoseDetector: initialize() failed: $e');
      return false;
    }
  }

  /// Runs pose detection on one camera frame. [bytes] is the frame's
  /// single-plane pixel data (nv21 on Android, bgra8888 on iOS — the same
  /// formats `PoseCoachService` already requests from the `camera` plugin);
  /// [rotationDegrees] is a clockwise multiple of 90 describing how far the
  /// sensor's natural orientation differs from upright. Returns `null` when
  /// no body was detected in this frame.
  Future<Pose?> detect({
    required Uint8List bytes,
    required int width,
    required int height,
    required int bytesPerRow,
    required int rotationDegrees,
  }) async {
    final result = await _channel.invokeMethod<List<Object?>>('detect', {
      'bytes': bytes,
      'width': width,
      'height': height,
      'bytesPerRow': bytesPerRow,
      'rotationDegrees': rotationDegrees,
    });
    if (result == null || result.isEmpty) return null;

    final landmarks = <PoseLandmarkType, PoseLandmark>{};
    for (var i = 0; i < result.length && i < PoseLandmarkType.values.length; i++) {
      final entry = result[i];
      if (entry is! Map) continue;
      final type = PoseLandmarkType.values[i];
      landmarks[type] = PoseLandmark(
        type: type,
        x: (entry['x'] as num?)?.toDouble() ?? 0,
        y: (entry['y'] as num?)?.toDouble() ?? 0,
        z: (entry['z'] as num?)?.toDouble() ?? 0,
        likelihood: (entry['visibility'] as num?)?.toDouble() ?? 1.0,
      );
    }
    if (landmarks.isEmpty) return null;
    return Pose(landmarks: landmarks);
  }

  Future<void> close() async {}
}
