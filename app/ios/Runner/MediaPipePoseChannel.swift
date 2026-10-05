import Accelerate
import CoreVideo
import Flutter
import MediaPipeTasksVision
import UIKit

/// Bridges Flutter to a native MediaPipe Tasks Vision Pose Landmarker,
/// reached from Dart via `forma/pose_landmarker` (see
/// `lib/features/camera_coach/data/mediapipe/mediapipe_pose_detector.dart`).
///
/// Mirrors `android/.../MediaPipePoseChannel.kt`. The design follows the
/// GymDemo POC's iOS fan-out, minus WebRTC: here the user's own phone camera
/// (Flutter `camera` plugin) is the only frame source, so there is no shared
/// capture pipeline to protect.
///
/// ## What changed from the first version, and why
///
/// - **`.liveStream` instead of `.image`.** In `.image` mode every frame is an
///   independent full detection. `.liveStream` keeps tracking state between
///   frames, so the heavy detector only runs when the pose is lost.
/// - **GPU delegate with CPU fallback.** The fallback is logged, never silent.
/// - **Pixels are rotated and letterboxed by us, not by MediaPipe.** The frame
///   is scaled, rotated upright and padded into a reusable 256x256 BGRA buffer
///   with vImage, so the landmarks come back in a space we constructed. The
///   first version passed an `orientation` and *assumed* MediaPipe returned
///   landmarks in the unrotated buffer's space, then rotated them back by
///   hand — an assumption that was never verified on hardware.
///
/// ## The Dart contract is unchanged
///
/// `detect` still resolves with 33 landmarks in the *upright frame's pixel
/// space* (or `nil`), so `PoseCoachService` needs no changes. The result now
/// arrives through MediaPipe's live-stream delegate; the Flutter reply is held
/// until then. One detection is in flight at a time — Dart's `_isBusy` gate
/// guarantees it and `pending` enforces it here, which is also what makes
/// reusing one pixel buffer safe (MediaPipe reads it asynchronously).
enum MediaPipePoseChannel {
  private enum PoseChannelError: Error {
    case modelNotFound
    case landmarkerUnavailable
    case imageBuildFailed
    case conversionFailed(String)
  }

  /// Square edge handed to inference. The model works at 256x256 internally.
  private static let size = 256

  /// A reply that never arrives would wedge Dart's `_isBusy` gate forever, so a
  /// detection is abandoned (reported as "no pose") after this long.
  private static let resultTimeout: TimeInterval = 2.0

  private static let queue = DispatchQueue(label: "forma.pose_landmarker")
  private static var landmarker: PoseLandmarker?
  private static let liveStreamDelegate = LiveStreamDelegate()

  /// The delegate actually in use; "CPU (fallback)" when GPU failed to init.
  private(set) static var activeDelegate = "none"

  /// Where the frame sits inside the inference square, in pixels.
  private struct Geometry {
    let uprightWidth: Int
    let uprightHeight: Int
    let contentWidth: Int
    let contentHeight: Int
    let padX: Int
    let padY: Int
  }

  private struct Pending {
    let token: Int
    let timestampMs: Int
    let reply: FlutterResult
    let geometry: Geometry
  }

  private static let stateLock = NSLock()
  private static var pending: Pending?
  private static var nextToken = 0
  private static var lastTimestampMs = 0

  // Reused across frames. Touched only on `queue` while a detection is claimed,
  // and read by MediaPipe only until the delegate fires.
  private static var squareBuffer: CVPixelBuffer?
  private static var scaledStorage: UnsafeMutableRawPointer?
  private static var scaledCapacity = 0

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
          submit(
            bytes: bytes.data,
            width: width,
            height: height,
            bytesPerRow: bytesPerRow,
            rotationDegrees: rotationDegrees,
            reply: result
          )
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // MARK: - Landmarker lifecycle

  private static func ensureLandmarker() throws {
    if landmarker != nil { return }
    let key = FlutterDartProject.lookupKey(forAsset: "assets/models/pose_landmarker_full.task")
    guard let modelPath = Bundle.main.path(forResource: key, ofType: nil) else {
      throw PoseChannelError.modelNotFound
    }

    if let built = tryBuild(modelPath: modelPath, delegate: .GPU) {
      landmarker = built
      activeDelegate = "GPU"
    } else {
      print("MediaPipePoseChannel: GPU delegate failed to initialise; falling back to CPU")
      guard let built = tryBuild(modelPath: modelPath, delegate: .CPU) else {
        activeDelegate = "none"
        throw PoseChannelError.landmarkerUnavailable
      }
      landmarker = built
      activeDelegate = "CPU (fallback)"
    }
    print("MediaPipePoseChannel: landmarker ready delegate=\(activeDelegate)")
  }

  private static func tryBuild(modelPath: String, delegate: Delegate) -> PoseLandmarker? {
    let options = PoseLandmarkerOptions()
    options.baseOptions.modelAssetPath = modelPath
    options.baseOptions.delegate = delegate
    options.runningMode = .liveStream
    options.numPoses = 1
    options.poseLandmarkerLiveStreamDelegate = liveStreamDelegate
    do {
      return try PoseLandmarker(options: options)
    } catch {
      print("MediaPipePoseChannel: landmarker build failed for \(delegate): \(error)")
      return nil
    }
  }

  // MARK: - One detection

  private static func submit(
    bytes: Data,
    width: Int,
    height: Int,
    bytesPerRow: Int,
    rotationDegrees: Int,
    reply: @escaping FlutterResult
  ) {
    var token = -1
    do {
      try ensureLandmarker()
      guard let landmarker else { throw PoseChannelError.landmarkerUnavailable }

      let rotation = ((rotationDegrees % 360) + 360) % 360
      let geometry = geometryFor(width: width, height: height, rotation: rotation)

      stateLock.lock()
      if pending != nil {
        stateLock.unlock()
        // Should be unreachable: Dart drops frames while busy. Refuse rather
        // than overwrite the buffer MediaPipe is still reading.
        DispatchQueue.main.async { reply(nil) }
        return
      }
      var timestamp = Int(ProcessInfo.processInfo.systemUptime * 1000)
      if timestamp <= lastTimestampMs { timestamp = lastTimestampMs + 1 }  // must strictly increase
      lastTimestampMs = timestamp
      nextToken += 1
      token = nextToken
      pending = Pending(token: token, timestampMs: timestamp, reply: reply, geometry: geometry)
      stateLock.unlock()

      let claimed = token
      DispatchQueue.main.asyncAfter(deadline: .now() + resultTimeout) { complete(token: claimed, payload: nil) }

      let buffer = try convert(
        bytes: bytes, width: width, height: height, bytesPerRow: bytesPerRow, rotation: rotation, geometry: geometry)
      let image = try MPImage(pixelBuffer: buffer)
      // Throws if the frame is refused; reaching the next line means MediaPipe
      // now owns the buffer until the delegate fires.
      try landmarker.detectAsync(image: image, timestampInMilliseconds: timestamp)
    } catch {
      // A single bad frame should never surface as a crash — report "no pose"
      // for this frame and let the next frame try again. Logged (not surfaced
      // to Dart as an error) so a real per-frame failure is still visible in
      // the Xcode console instead of looking identical to "no body detected".
      print("MediaPipePoseChannel: detect failed: \(error)")
      if token >= 0 {
        complete(token: token, payload: nil)
      } else {
        DispatchQueue.main.async { reply(nil) }
      }
    }
  }

  /// Delegate thread. Delivers the held reply.
  fileprivate static func finish(result: PoseLandmarkerResult?, timestampMs: Int, error: Error?) {
    stateLock.lock()
    let claimed = pending
    stateLock.unlock()
    guard let claimed else { return }
    // A late result for a frame we already gave up on must not be handed to the
    // next frame, whose geometry may differ.
    guard claimed.timestampMs == timestampMs else { return }

    if let error {
      print("MediaPipePoseChannel: inference error: \(error)")
      complete(token: claimed.token, payload: nil)  // MUST release the reply, or Dart's _isBusy never clears
      return
    }
    guard let pose = result?.landmarks.first else {
      complete(token: claimed.token, payload: nil)
      return
    }

    let g = claimed.geometry
    let payload: [[String: Any]] = pose.map { landmark in
      // Landmarks are normalised to the whole square, letterbox padding
      // included — undo the pad, then scale to the upright frame's pixels.
      let ux = (Double(landmark.x) * Double(size) - Double(g.padX)) / Double(g.contentWidth)
      let uy = (Double(landmark.y) * Double(size) - Double(g.padY)) / Double(g.contentHeight)
      return [
        "x": ux * Double(g.uprightWidth),
        "y": uy * Double(g.uprightHeight),
        "z": Double(landmark.z),
        "visibility": landmark.visibility.map { Double(truncating: $0) } ?? 1.0,
      ]
    }
    complete(token: claimed.token, payload: payload)
  }

  /// Idempotent: only the first completion for a token replies.
  private static func complete(token: Int, payload: [[String: Any]]?) {
    stateLock.lock()
    guard let claimed = pending, claimed.token == token else {
      stateLock.unlock()
      return
    }
    pending = nil
    stateLock.unlock()
    DispatchQueue.main.async { claimed.reply(payload) }
  }

  // MARK: - Frame conversion

  /// Largest upright rectangle with the frame's aspect ratio that fits the
  /// square. Even dimensions only. Letterboxed rather than centre-cropped: a
  /// crop on a portrait phone discards the head and feet of a standing person.
  private static func geometryFor(width: Int, height: Int, rotation: Int) -> Geometry {
    let quarterTurn = rotation == 90 || rotation == 270
    let uprightW = quarterTurn ? height : width
    let uprightH = quarterTurn ? width : height
    let longEdge = max(uprightW, uprightH)
    let contentW = even(size * uprightW / longEdge)
    let contentH = even(size * uprightH / longEdge)
    return Geometry(
      uprightWidth: uprightW, uprightHeight: uprightH,
      contentWidth: contentW, contentHeight: contentH,
      padX: (size - contentW) / 2, padY: (size - contentH) / 2)
  }

  private static func even(_ n: Int) -> Int { max(2, n & ~1) }

  /// BGRA frame -> upright, letterboxed 256x256 BGRA, with vImage.
  ///
  /// Scale first (in buffer orientation) so the rotate and pad run on a small
  /// image rather than the full camera frame, then rotate straight into the
  /// content sub-rect of the square. `rotation` is clockwise-to-upright, the
  /// same convention `PoseCoachService._rotationFor` produces.
  private static func convert(
    bytes: Data, width: Int, height: Int, bytesPerRow: Int, rotation: Int, geometry g: Geometry
  ) throws -> CVPixelBuffer {
    guard bytes.count >= bytesPerRow * height, bytesPerRow >= width * 4 else {
      throw PoseChannelError.conversionFailed("frame buffer smaller than \(bytesPerRow)x\(height)")
    }
    let square = try ensureSquareBuffer()

    let quarterTurn = rotation == 90 || rotation == 270
    let scaledW = quarterTurn ? g.contentHeight : g.contentWidth
    let scaledH = quarterTurn ? g.contentWidth : g.contentHeight
    let scaledBytes = scaledW * scaledH * 4
    if scaledCapacity < scaledBytes {
      scaledStorage?.deallocate()
      scaledStorage = UnsafeMutableRawPointer.allocate(byteCount: scaledBytes, alignment: 16)
      scaledCapacity = scaledBytes
    }
    guard let scaledBase = scaledStorage else { throw PoseChannelError.imageBuildFailed }

    CVPixelBufferLockBaseAddress(square, [])
    defer { CVPixelBufferUnlockBaseAddress(square, []) }
    guard let squareBase = CVPixelBufferGetBaseAddress(square) else { throw PoseChannelError.imageBuildFailed }
    let squareRowBytes = CVPixelBufferGetBytesPerRow(square)

    try bytes.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
      guard let base = raw.baseAddress else { throw PoseChannelError.imageBuildFailed }

      var src = vImage_Buffer(
        data: UnsafeMutableRawPointer(mutating: base),
        height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: bytesPerRow)
      var scaled = vImage_Buffer(
        data: scaledBase,
        height: vImagePixelCount(scaledH), width: vImagePixelCount(scaledW), rowBytes: scaledW * 4)
      let scaleErr = vImageScale_ARGB8888(&src, &scaled, nil, vImage_Flags(kvImageHighQualityResampling))
      guard scaleErr == kvImageNoError else { throw PoseChannelError.conversionFailed("scale \(scaleErr)") }

      // Opaque black padding, rewritten every frame so a stale border never
      // becomes a moving edge for the model to latch onto.
      var whole = vImage_Buffer(
        data: squareBase, height: vImagePixelCount(size), width: vImagePixelCount(size), rowBytes: squareRowBytes)
      var black: [UInt8] = [0, 0, 0, 255]
      let fillErr = vImageBufferFill_ARGB8888(&whole, &black, vImage_Flags(kvImageNoFlags))
      guard fillErr == kvImageNoError else { throw PoseChannelError.conversionFailed("fill \(fillErr)") }

      var dst = vImage_Buffer(
        data: squareBase.advanced(by: g.padY * squareRowBytes + g.padX * 4),
        height: vImagePixelCount(g.contentHeight), width: vImagePixelCount(g.contentWidth),
        rowBytes: squareRowBytes)
      let turn: UInt8
      switch rotation {
      case 90: turn = UInt8(kRotate90DegreesClockwise)
      case 180: turn = UInt8(kRotate180DegreesClockwise)
      case 270: turn = UInt8(kRotate270DegreesClockwise)
      default: turn = UInt8(kRotate0DegreesClockwise)
      }
      let rotateErr = vImageRotate90_ARGB8888(&scaled, &dst, turn, &black, vImage_Flags(kvImageNoFlags))
      guard rotateErr == kvImageNoError else { throw PoseChannelError.conversionFailed("rotate \(rotateErr)") }
    }
    return square
  }

  private static func ensureSquareBuffer() throws -> CVPixelBuffer {
    if let squareBuffer { return squareBuffer }
    // IOSurface-backed so MPImage can wrap it without a copy.
    let attrs: [CFString: Any] = [
      kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
      kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
    ]
    var out: CVPixelBuffer?
    let status = CVPixelBufferCreate(
      kCFAllocatorDefault, size, size, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &out)
    guard status == kCVReturnSuccess, let buffer = out else { throw PoseChannelError.imageBuildFailed }
    squareBuffer = buffer
    return buffer
  }
}

/// MediaPipe delivers live-stream results on its own private queue.
private final class LiveStreamDelegate: NSObject, PoseLandmarkerLiveStreamDelegate {
  func poseLandmarker(
    _ poseLandmarker: PoseLandmarker,
    didFinishDetection result: PoseLandmarkerResult?,
    timestampInMilliseconds: Int,
    error: Error?
  ) {
    MediaPipePoseChannel.finish(result: result, timestampMs: timestampInMilliseconds, error: error)
  }
}
