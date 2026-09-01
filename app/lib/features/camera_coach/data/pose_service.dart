import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:permission_handler/permission_handler.dart';

/// Outcome of [PoseCoachService.initialize].
enum PoseServiceInitResult {
  /// Camera permission granted and a camera controller is ready.
  ready,

  /// The user denied (or has permanently denied) camera permission.
  permissionDenied,

  /// Permission was granted but no usable camera was found, or the
  /// controller failed to initialize (e.g. running on a simulator/emulator
  /// with no working camera feed). Callers should fall back to a
  /// no-camera state rather than crash.
  noCameraAvailable,
}

/// Wraps the `camera` plugin and ML Kit's on-device [PoseDetector] into one
/// engine object: own a [PoseCoachService], call [initialize], then
/// [startStream] to get a pose on every camera frame. Pure UI is
/// deliberately kept out of this file — screens own a `CameraPreview` /
/// `CustomPainter` themselves and just read [controller] and the pose
/// callback.
class PoseCoachService {
  PoseCoachService({PoseDetector? detector})
    : _detector =
          detector ??
          PoseDetector(
            options: PoseDetectorOptions(
              // `base` (the package default) is tuned for close-up, fast
              // detection; `accurate` costs some latency but tracks a
              // full body much more reliably at the couple-of-metres
              // distance a propped-up coaching phone is shot from — this
              // is exactly the scenario Google's own ML Kit guidance
              // recommends `accurate` for.
              model: PoseDetectionModel.accurate,
              mode: PoseDetectionMode.stream,
            ),
          );

  final PoseDetector _detector;

  CameraController? _controller;
  CameraDescription? _cameraDescription;
  List<CameraDescription> _availableCameras = const [];
  bool _isStreaming = false;
  bool _isBusy = false;
  void Function(Pose? pose)? _onPose;

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

  /// Requests camera permission and opens a [CameraController].
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
      // ML Kit's InputImage.fromBytes only understands nv21 on Android and
      // bgra8888 on iOS (see InputImageMetadata's doc comment in
      // google_mlkit_commons) — requesting anything else here would make
      // every frame fail to decode on-device.
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
    // ML Kit's processImage is async and frames arrive faster than it can
    // keep up on most devices — drop any frame that arrives while we're
    // still processing the previous one instead of queuing them up.
    if (_isBusy) return;
    _isBusy = true;
    try {
      final inputImage = _toInputImage(image);
      if (inputImage == null) {
        _onPose?.call(null);
        return;
      }
      final poses = await _detector.processImage(inputImage);
      _onPose?.call(poses.isNotEmpty ? poses.first : null);
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
  /// table Google's own ML Kit + camera example apps use to build
  /// [InputImageRotation] from a live camera stream.
  static const Map<DeviceOrientation, int> _orientationDegrees = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  InputImage? _toInputImage(CameraImage image) {
    final camera = _cameraDescription;
    final controller = _controller;
    if (camera == null || controller == null) return null;

    final rotation = _rotationFor(camera, controller);
    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw as int);
    // The camera controller was opened with an explicit imageFormatGroup
    // above, so on a correctly-behaving platform this should always match;
    // bail out (report "no pose" for this frame) rather than hand ML Kit a
    // buffer it doesn't know how to interpret.
    final expected = Platform.isAndroid ? InputImageFormat.nv21 : InputImageFormat.bgra8888;
    if (format == null || format != expected) return null;

    // Both nv21 (Android) and bgra8888 (iOS) frames from `camera` arrive as
    // a single plane; anything else isn't a shape ML Kit's fromBytes API
    // supports.
    if (image.planes.length != 1) return null;
    final plane = image.planes.first;

    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  InputImageRotation? _rotationFor(CameraDescription camera, CameraController controller) {
    // iOS: the sensor orientation alone is the rotation ML Kit wants.
    if (Platform.isIOS) {
      return InputImageRotationValue.fromRawValue(camera.sensorOrientation);
    }
    // Android: combine the sensor orientation with the current device
    // orientation, and flip the sign for a front-facing sensor (its image
    // is mirrored relative to a back-facing one).
    if (Platform.isAndroid) {
      final deviceDegrees = _orientationDegrees[controller.value.deviceOrientation];
      if (deviceDegrees == null) return null;
      final rotationCompensation = camera.lensDirection == CameraLensDirection.front
          ? (camera.sensorOrientation + deviceDegrees) % 360
          : (camera.sensorOrientation - deviceDegrees + 360) % 360;
      return InputImageRotationValue.fromRawValue(rotationCompensation);
    }
    return InputImageRotationValue.fromRawValue(camera.sensorOrientation);
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
/// buffer that [PoseCoachService._toInputImage] would otherwise reject.
Uint8List concatenatePlanes(Iterable<Uint8List> planes) {
  final builder = BytesBuilder();
  for (final bytes in planes) {
    builder.add(bytes);
  }
  return builder.toBytes();
}
