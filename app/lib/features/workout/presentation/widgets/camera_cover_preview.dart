import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// Lays [child] out at [aspectRatio] (width / height) and scales it to *cover*
/// the available space, cropping the overflow, instead of stretching it.
///
/// A bare `CameraPreview` inside a `StackFit.expand` is given tight constraints
/// equal to the whole screen, so its own `AspectRatio` is overridden and the
/// 3:4 camera image is stretched to the phone's taller shape. This keeps the
/// image's true proportions; the cost is that the edges of the long side are
/// cropped off-screen (for a portrait phone, a slice of the left and right).
class AspectCover extends StatelessWidget {
  const AspectCover({super.key, required this.aspectRatio, required this.child, this.fit = BoxFit.cover});

  /// Width / height of [child]'s natural shape, as displayed.
  final double aspectRatio;
  final Widget child;

  /// `cover` fills the screen and crops; `contain` shows the whole camera frame
  /// with bars instead.
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: SizedBox.expand(
        child: FittedBox(
          fit: fit,
          child: SizedBox(width: aspectRatio * 100, height: 100, child: child),
        ),
      ),
    );
  }
}

/// The live camera preview, undistorted. Drop-in replacement for
/// `CameraPreview(controller)` in a full-screen stack.
class CameraCoverPreview extends StatelessWidget {
  const CameraCoverPreview(this.controller, {super.key, this.fit = BoxFit.cover});

  final CameraController controller;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    // `controller.value.aspectRatio` is the sensor's landscape ratio (w > h).
    // `CameraPreview` flips it to h/w in portrait, so the box we cover with must
    // use the same displayed ratio or the image is stretched sideways.
    final portrait = MediaQuery.orientationOf(context) == Orientation.portrait;
    final sensorRatio = controller.value.aspectRatio;
    final displayed = portrait ? 1 / sensorRatio : sensorRatio;
    return AspectCover(aspectRatio: displayed, fit: fit, child: CameraPreview(controller));
  }
}
