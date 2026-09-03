import CoreVideo
import Flutter
import MediaPipeTasksVision
import UIKit

/// Bridges Flutter to a native MediaPipe Tasks Vision Pose Landmarker,
/// reached from Dart via `forma/pose_landmarker` (see
/// `lib/features/camera_coach/data/mediapipe/mediapipe_pose_detector.dart`).
///
/// The landmarker is a lazily-created singleton, never torn down for the
/// life of the app — reloading its ~9MB model every time a coaching screen
/// opens/closes would be wasteful, and MediaPipe's own samples treat a
/// task instance as long-lived. Every `detect` call is funneled through
/// one serial `DispatchQueue`, which is what actually guarantees two
/// `detect()` calls never run concurrently against the same instance (a
/// documented MediaPipe requirement) — this holds even if two Dart-side
/// `PoseCoachService`s transiently overlap, since the constraint lives
/// here, not per Dart instance. Runs in `IMAGE` (synchronous) mode: one
/// `detect()` call blocks the calling thread until inference finishes, so
/// it must never run on the platform/main thread — hence the queue.
enum MediaPipePoseChannel {
  private enum PoseChannelError: Error {
    case modelNotFound
    case notInitialized
    case imageBuildFailed
  }

  private static let queue = DispatchQueue(label: "forma.pose_landmarker")
  private static var landmarker: PoseLandmarker?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "forma/pose_landmarker", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "init":
        queue.async {
          do {
            try ensureLandmarker()
            DispatchQueue.main.async { result(nil) }
          } catch {
            DispatchQueue.main.async { result(FlutterError(code: "init_failed", message: "\(error)", details: nil)) }
          }
        }
      case "detect":
        guard let args = call.arguments as? [String: Any],
          let bytes = args["bytes"] as? FlutterStandardTypedData,
          let width = args["width"] as? Int,
          let height = args["height"] as? Int,
          let bytesPerRow = args["bytesPerRow"] as? Int,
          let rotationDegrees = args["rotationDegrees"] as? Int
        else {
          result(FlutterError(code: "bad_args", message: "Missing/invalid detect() arguments", details: nil))
          return
        }
        queue.async {
          do {
            try ensureLandmarker()
            let landmarks = try detectPose(
              bytes: bytes.data,
              width: width,
              height: height,
              bytesPerRow: bytesPerRow,
              rotationDegrees: rotationDegrees
            )
            DispatchQueue.main.async { result(landmarks) }
          } catch {
            // A single bad frame should never surface as a crash — report
            // "no pose" for this frame and let the next frame try again.
            // Logged (not surfaced to Dart as an error) so a real, per-frame
            // failure is still visible in the Xcode console instead of
            // looking identical to "no body detected".
            print("MediaPipePoseChannel: detect failed: \(error)")
            DispatchQueue.main.async { result(nil) }
          }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func ensureLandmarker() throws {
    if landmarker != nil { return }
    let key = FlutterDartProject.lookupKey(forAsset: "assets/models/pose_landmarker_full.task")
    guard let modelPath = Bundle.main.path(forResource: key, ofType: nil) else {
      throw PoseChannelError.modelNotFound
    }
    let options = PoseLandmarkerOptions()
    options.baseOptions.modelAssetPath = modelPath
    options.baseOptions.delegate = .CPU
    options.runningMode = .image
    options.numPoses = 1
    landmarker = try PoseLandmarker(options: options)
  }

  /// Builds a `CVPixelBuffer`/`MPImage` directly over [bytes]' backing
  /// storage and runs detection *inside* the `withUnsafeBytes` closure —
  /// `CVPixelBufferCreateWithBytes` (with no release callback) does not
  /// copy the pixel data, so the pointer must stay valid for as long as
  /// the pixel buffer is used, which is only guaranteed for the duration
  /// of this closure.
  private static func detectPose(bytes: Data, width: Int, height: Int, bytesPerRow: Int, rotationDegrees: Int) throws
    -> [[String: Any]]?
  {
    guard let landmarker else { throw PoseChannelError.notInitialized }

    return try bytes.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> [[String: Any]]? in
      guard let baseAddress = raw.baseAddress else { throw PoseChannelError.imageBuildFailed }

      var pixelBuffer: CVPixelBuffer?
      let status = CVPixelBufferCreateWithBytes(
        kCFAllocatorDefault,
        width,
        height,
        kCVPixelFormatType_32BGRA,
        UnsafeMutableRawPointer(mutating: baseAddress),
        bytesPerRow,
        nil,
        nil,
        nil,
        &pixelBuffer
      )
      guard status == kCVReturnSuccess, let pixelBuffer else {
        throw PoseChannelError.imageBuildFailed
      }

      let mpImage = try MPImage(pixelBuffer: pixelBuffer, orientation: orientation(forDegrees: rotationDegrees))
      let result = try landmarker.detect(image: mpImage)
      guard let pose = result.landmarks.first else { return nil }

      // Unlike Android's Bitmap route, MediaPipe's iOS API returns
      // landmarks relative to the *original, unrotated* pixel buffer even
      // though `orientation` was supplied (confirmed against Google's own
      // PoseOverlay.swift sample, which applies this exact per-orientation
      // swap/flip before scaling — e.g. its `.left` case computes
      // `(x: y, y: 1 - x)`, matching the 270° case below). So the
      // normalized coordinates must be rotated into "upright" space here,
      // then scaled by the upright (rotation-swapped) dimensions.
      let normalizedRotation = ((rotationDegrees % 360) + 360) % 360
      let outputWidth = (normalizedRotation == 90 || normalizedRotation == 270) ? height : width
      let outputHeight = (normalizedRotation == 90 || normalizedRotation == 270) ? width : height

      return pose.map { landmark in
        let rawX = Double(landmark.x)
        let rawY = Double(landmark.y)
        let upright: (x: Double, y: Double)
        switch normalizedRotation {
        case 90: upright = (1 - rawY, rawX)
        case 180: upright = (1 - rawX, 1 - rawY)
        case 270: upright = (rawY, 1 - rawX)
        default: upright = (rawX, rawY)
        }

        return [
          "x": upright.x * Double(outputWidth),
          "y": upright.y * Double(outputHeight),
          "z": Double(landmark.z),
          "visibility": landmark.visibility.map { Double(truncating: $0) } ?? 1.0,
        ] as [String: Any]
      }
    }
  }

  /// MediaPipe's `MPImage` takes rotation as a `UIImage.Orientation`
  /// rather than raw degrees — `.right` means "90° clockwise to upright",
  /// matching the same rotation convention `pose_service.dart`'s
  /// `_rotationFor` already computes.
  private static func orientation(forDegrees degrees: Int) -> UIImage.Orientation {
    switch ((degrees % 360) + 360) % 360 {
    case 90: return .right
    case 180: return .down
    case 270: return .left
    default: return .up
    }
  }
}
