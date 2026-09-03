import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'mediapipe/mediapipe_pose_detector.dart';
import 'mediapipe/pose_types.dart';

/// Outcome of [PoseCoachService.initialize].
enum PoseServiceInitResult {
  /// Camera permission granted and a camera controller is ready.
  ready,

  /// The user denied (or has permanently denied) camera permission.
  permissionDenied,

  /// Permission was granted but no usable camera was found, the pose
  /// detector failed to load its model, or the controller failed to
  /// initialize (e.g. running on a simulator/emulator with no working
  /// camera feed). Callers should fall back to a no-camera state rather
  /// than crash.
  noCameraAvailable,
}

/// Wraps the `camera` plugin and a native MediaPipe Tasks Vision Pose
/// Landmarker into one engine object: own a [PoseCoachService], call
/// [initialize], then [startStream] to get a pose on every camera frame.
/// Pure UI is deliberately kept out of this file — screens own a
/// `CameraPreview` / `CustomPainter` themselves and just read [controller]
/// and the pose callback.
class PoseCoachService {
  PoseCoachService() : _detector = MediaPipePoseDetector();

  final MediaPipePoseDetector _detector;

  CameraController? _controller;
  CameraDescription? _cameraDescription;
  List<CameraDescription> _availableCameras = const [];
  bool _isStreaming = false;
  bool _isBusy = false;
  void Function(Pose? pose)? _onPose;
  Size? _lastFrameSize;

  /// The active camera controller. Only valid after [initialize] returns
  /// [PoseServiceInitResult.ready].
  CameraController get controller {
    final controller = _controller;
    if (controller == null) {
      throw StateError('PoseCoachService.initialize() must succeed before reading controller.');
    }
    return controller;
  }

  bool get isInitialized => _controller?.value.isInitialized ?? false;

  /// The most recently processed frame's *display* (upright, rotation-
  /// applied) size — i.e. exactly the width/height the native pose
  /// detector actually scaled its landmarks against (see
  /// `MediaPipePoseChannel`'s rotation handling on both platforms). `null`
  /// until the first frame has been processed.
  ///
  /// Callers scaling landmark positions for display (`PoseSkeletonPainter`)
  /// must use this, not `controller.value.previewSize` — CameraX (Android)
  /// negotiates the preview surface and the image-analysis stream as
  /// separate use cases, which frequently end up at different actual
  /// resolutions even when configured with the same target size, so
  /// `previewSize` is not a reliable stand-in for the frame size pose
  /// landmarks are actually reported in.
  Size? get lastFrameSize => _lastFrameSize;

  /// Requests camera permission, loads the native pose-detector model, and
  /// opens a [CameraController].
  ///
  /// Camera choice: for coaching a lift, the **rear** camera is the more
  /// useful default — the phone gets propped up across the room (on a
  /// bench, in a phone stand at the end of the rack) and the lifter steps
  /// back into frame, which the wider, higher-quality rear sensor handles
  /// much better than a selfie camera meant for arm's-length framing. We
  /// still fall back to whatever camera *is* available (some tablets and
  /// most emulators only expose a front camera) rather than failing when
  /// there's no rear camera to pick.
  Future<PoseServiceInitResult> initialize() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      return PoseServiceInitResult.permissionDenied;
    }

    final detectorReady = await _detector.initialize();
    if (!detectorReady) {
      debugPrint('PoseCoachService: MediaPipePoseDetector.initialize() failed');
      return PoseServiceInitResult.noCameraAvailable;
    }

    try {
      _availableCameras = await availableCameras();
    } catch (e) {
      debugPrint('PoseCoachService: availableCameras() failed: $e');
      return PoseServiceInitResult.noCameraAvailable;
    }
    if (_availableCameras.isEmpty) return PoseServiceInitResult.noCameraAvailable;

    final camera = _availableCameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => _availableCameras.first,
    );

    return _open(camera);
  }

  /// Switches between the front and back camera, if more than one is
  /// available. No-op if only one camera exists.
  Future<PoseServiceInitResult> switchCamera() async {
    if (_availableCameras.length < 2 || _cameraDescription == null || _controller == null) {
      return _cameraDescription == null ? PoseServiceInitResult.noCameraAvailable : PoseServiceInitResult.ready;
    }
    final wasStreaming = _isStreaming;
    final onPose = _onPose;
    await stopStream();
    await _controller!.dispose();
    _controller = null;

    final next = _availableCameras.firstWhere(
      (c) => c.lensDirection != _cameraDescription!.lensDirection,
      orElse: () => _cameraDescription!,
    );
    final result = await _open(next);
    if (result == PoseServiceInitResult.ready && wasStreaming && onPose != null) {
      startStream(onPose);
    }
    return result;
  }

  Future<PoseServiceInitResult> _open(CameraDescription camera) async {
    _cameraDescription = camera;

    final controller = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
      // The native pose landmarker only understands a single-plane buffer
      // per frame: nv21 on Android, bgra8888 on iOS (see `_frameFor`) —
      // requesting anything else here would make every frame fail to
      // decode on-device.
      imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
    );

    try {
      await controller.initialize();
    } catch (e) {
      debugPrint('PoseCoachService: camera initialize() failed: $e');
      await controller.dispose();
      return PoseServiceInitResult.noCameraAvailable;
    }

    _controller = controller;
    return PoseServiceInitResult.ready;
  }

  /// Starts streaming camera frames through the pose detector. [onPose] is
  /// invoked on (approximately) every processed frame with the first
  /// detected pose, or `null` when no body was found in that frame (e.g.
  /// the lifter stepped out of shot) — callers should treat `null` as "no
  /// data this frame", not an error.
  void startStream(void Function(Pose? pose) onPose) {
    final controller = _controller;
    if (controller == null || _isStreaming) return;
    _onPose = onPose;
    _isStreaming = true;
    controller.startImageStream(_handleImage);
  }

  Future<void> stopStream() async {
    _isStreaming = false;
    final controller = _controller;
    if (controller != null && controller.value.isStreamingImages) {
      await controller.stopImageStream();
    }
  }

  Future<void> _handleImage(CameraImage image) async {
    // Frames arrive faster than the native detector can keep up on most
    // devices — drop any frame that arrives while we're still processing
    // the previous one instead of queuing them up.
    if (_isBusy) return;
    _isBusy = true;
    try {
      final frame = _frameFor(image);
      if (frame == null) {
        _onPose?.call(null);
        return;
      }
      final pose = await _detector.detect(
        bytes: frame.bytes,
        width: frame.width,
        height: frame.height,
        bytesPerRow: frame.bytesPerRow,
        rotationDegrees: frame.rotationDegrees,
      );
      _onPose?.call(pose);
    } catch (e) {
      // A single bad frame (e.g. mid-rotation, or the platform channel
      // hiccups) should never crash the session — just report "no pose"
      // for this frame and keep streaming.
      debugPrint('PoseCoachService: frame processing failed: $e');
      _onPose?.call(null);
    } finally {
      _isBusy = false;
    }
  }

  /// Maps a device orientation to the clockwise rotation (in degrees) of
  /// the display relative to the sensor's natural orientation — the same
  /// table Google's own ML Kit + camera example apps use to build a
  /// rotation value from a live camera stream.
  static const Map<DeviceOrientation, int> _orientationDegrees = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  _CameraFrame? _frameFor(CameraImage image) {
    final camera = _cameraDescription;
    final controller = _controller;
    if (camera == null || controller == null) return null;

    final rotationDegrees = _rotationFor(camera, controller);
    if (rotationDegrees == null) {
      debugPrint('PoseCoachService: dropping frame — could not resolve device orientation');
      return null;
    }

    // Recorded from the raw buffer's own dimensions (not `previewSize` —
    // see `lastFrameSize`'s doc comment) regardless of whether this frame
    // passes the checks below, since width/height/rotation are already
    // known and this is the authoritative size the native detector will
    // scale landmarks against for *this* frame.
    _lastFrameSize = (rotationDegrees == 90 || rotationDegrees == 270)
        ? Size(image.height.toDouble(), image.width.toDouble())
        : Size(image.width.toDouble(), image.height.toDouble());

    // Deliberately checking the *raw* platform format code, not
    // `image.format.group`: `camera_platform_interface`'s own group
    // derivation (`_imageFormatGroupFromPlatformData`) has no case for
    // Android's NV21 raw code (17) — exactly the format requested below —
    // and silently falls back to `ImageFormatGroup.unknown` for it, which
    // would make this check reject every single frame on Android. The raw
    // code is stable platform API (`android.graphics.ImageFormat.NV21` /
    // `kCVPixelFormatType_32BGRA`), so check that instead of trusting `.group`.
    const androidNv21Raw = 17;
    const iosBgra8888Raw = 1111970369;
    final expectedRaw = Platform.isAndroid ? androidNv21Raw : iosBgra8888Raw;
    if (image.format.raw != expectedRaw) {
      debugPrint('PoseCoachService: dropping frame — unexpected format raw=${image.format.raw} (expected $expectedRaw)');
      return null;
    }

    // Both nv21 (Android) and bgra8888 (iOS) frames from `camera` arrive as
    // a single plane; anything else isn't a shape the native detector
    // supports.
    if (image.planes.length != 1) {
      debugPrint('PoseCoachService: dropping frame — expected 1 plane, got ${image.planes.length}');
      return null;
    }
    final plane = image.planes.first;

    return _CameraFrame(
      bytes: plane.bytes,
      width: image.width,
      height: image.height,
      bytesPerRow: plane.bytesPerRow,
      rotationDegrees: rotationDegrees,
    );
  }

  /// iOS: the sensor orientation alone is the rotation the detector wants.
  /// Android: combine the sensor orientation with the current device
  /// orientation, and flip the sign for a front-facing sensor (its image
  /// is mirrored relative to a back-facing one).
  int? _rotationFor(CameraDescription camera, CameraController controller) {
    if (Platform.isIOS) {
      return camera.sensorOrientation;
    }
    if (Platform.isAndroid) {
      final deviceDegrees = _orientationDegrees[controller.value.deviceOrientation];
      if (deviceDegrees == null) return null;
      return camera.lensDirection == CameraLensDirection.front
          ? (camera.sensorOrientation + deviceDegrees) % 360
          : (camera.sensorOrientation - deviceDegrees + 360) % 360;
    }
    return camera.sensorOrientation;
  }

  Future<void> dispose() async {
    await stopStream();
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      await controller.dispose();
    }
    await _detector.close();
  }
}

/// One camera frame's worth of data handed to [MediaPipePoseDetector.detect]
/// — the boundary between `camera`'s [CameraImage] and the platform channel.
class _CameraFrame {
  const _CameraFrame({required this.bytes, required this.width, required this.height, required this.bytesPerRow, required this.rotationDegrees});

  final Uint8List bytes;
  final int width;
  final int height;
  final int bytesPerRow;
  final int rotationDegrees;
}

/// Best-effort check for whether a [pose]'s landmarks look usable — many
/// landmarks present, each with reasonable confidence — vs. a mostly-empty
/// detection (e.g. the lifter is only partially in frame). Used by the
/// precheck screen's "full body in frame" heuristic; not a hard guarantee,
/// just a signal.
bool poseLooksUsable(Pose? pose, {int minLandmarks = 20, double minLikelihood = 0.5}) {
  if (pose == null) return false;
  final confident = pose.landmarks.values.where((l) => l.likelihood >= minLikelihood).length;
  return confident >= minLandmarks;
}

/// Bytes helper kept here (rather than inline) purely so it's easy to spot
/// in a diff if a future platform ever hands back a multi-plane nv21/bgra
/// buffer that [PoseCoachService._frameFor] would otherwise reject.
Uint8List concatenatePlanes(Iterable<Uint8List> planes) {
  final builder = BytesBuilder();
  for (final bytes in planes) {
    builder.add(bytes);
  }
  return builder.toBytes();
}
