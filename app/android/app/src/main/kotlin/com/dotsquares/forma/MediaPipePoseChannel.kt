package com.ds.forma

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageFormat
import android.graphics.Matrix
import android.graphics.Rect
import android.graphics.YuvImage
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.framework.image.MPImage
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors

/**
 * Bridges Flutter to a native MediaPipe Tasks Vision Pose Landmarker,
 * reached from Dart via `forma/pose_landmarker` (see
 * `lib/features/camera_coach/data/mediapipe/mediapipe_pose_detector.dart`).
 *
 * Mirrors `ios/Runner/MediaPipePoseChannel.swift` — see its doc comment
 * for why the landmarker is a lazily-created, never-torn-down singleton
 * and why every `detect` call is serialized onto one background executor
 * (MediaPipe forbids concurrent `detect()` calls against the same
 * instance; `detect()` also blocks the calling thread, so it must never
 * run on the platform/main thread).
 */
object MediaPipePoseChannel {
    private const val CHANNEL_NAME = "forma/pose_landmarker"
    private const val MODEL_ASSET_PATH = "assets/models/pose_landmarker_full.task"
    private const val MODEL_FILE_NAME = "pose_landmarker_full.task"

    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var landmarker: PoseLandmarker? = null

    fun register(flutterEngine: FlutterEngine, context: Context) {
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "init" ->
                    executor.execute {
                        try {
                            ensureLandmarker(context)
                            mainHandler.post { result.success(null) }
                        } catch (e: Exception) {
                            mainHandler.post { result.error("init_failed", e.message, null) }
                        }
                    }
                "detect" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    val width = call.argument<Int>("width")
                    val height = call.argument<Int>("height")
                    val rotationDegrees = call.argument<Int>("rotationDegrees")
                    if (bytes == null || width == null || height == null || rotationDegrees == null) {
                        result.error("bad_args", "Missing/invalid detect() arguments", null)
                        return@setMethodCallHandler
                    }
                    executor.execute {
                        try {
                            ensureLandmarker(context)
                            val landmarks = detectPose(bytes, width, height, rotationDegrees)
                            mainHandler.post { result.success(landmarks) }
                        } catch (e: Exception) {
                            // A single bad frame should never surface as a crash —
                            // report "no pose" for this frame and let the next
                            // frame try again. Logged (not surfaced to Dart as an
                            // error) so a real, per-frame failure is still visible
                            // in logcat instead of looking identical to "no body
                            // detected".
                            Log.w("MediaPipePoseChannel", "detect failed", e)
                            mainHandler.post { result.success(null) }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun ensureLandmarker(context: Context) {
        if (landmarker != null) return

        val modelFile = File(context.filesDir, MODEL_FILE_NAME)
        if (!modelFile.exists()) {
            val assetKey = FlutterInjector.instance().flutterLoader().getLookupKeyForAsset(MODEL_ASSET_PATH)
            context.assets.open(assetKey).use { input ->
                FileOutputStream(modelFile).use { output -> input.copyTo(output) }
            }
        }

        val baseOptions = BaseOptions.builder().setDelegate(Delegate.CPU).setModelAssetPath(modelFile.absolutePath).build()
        val options =
            PoseLandmarker.PoseLandmarkerOptions.builder()
                .setBaseOptions(baseOptions)
                .setRunningMode(RunningMode.IMAGE)
                .setNumPoses(1)
                .build()
        landmarker = PoseLandmarker.createFromOptions(context, options)
    }

    private fun detectPose(bytes: ByteArray, width: Int, height: Int, rotationDegrees: Int): List<Map<String, Any>>? {
        val landmarker = landmarker ?: return null

        // MediaPipe's Android `detect()` only accepts RGB-family MPImages
        // (ByteBuffer RGB/RGBA/ALPHA, an ARGB_8888 Bitmap, or an RGBA_8888
        // android.media.Image) — NV21/YUV is not supported by
        // `AndroidPacketCreator.createImage()` despite `MPImage.
        // IMAGE_FORMAT_NV21` existing as a constant (confirmed via a real
        // `UnsupportedOperationException: Unsupported MediaPipe Image
        // image format: 4` at runtime), so the nv21 bytes the `camera`
        // plugin hands us must be converted to a Bitmap first.
        val rawBitmap = nv21ToBitmap(bytes, width, height)

        // Rotate the bitmap itself to upright *before* detection, exactly
        // like Google's own official PoseLandmarkerHelper.kt sample — this
        // (deliberately, not `ImageProcessingOptions.setRotationDegrees`,
        // whose output coordinate-space contract isn't documented and
        // isn't used by that sample either) means the returned landmarks
        // are already relative to the upright, correctly-oriented bitmap,
        // so no further coordinate transform is needed: just scale by the
        // rotated bitmap's own (possibly width/height-swapped) dimensions.
        val normalizedRotation = ((rotationDegrees % 360) + 360) % 360
        val uprightBitmap =
            if (normalizedRotation == 0) {
                rawBitmap
            } else {
                val matrix = Matrix().apply { postRotate(normalizedRotation.toFloat()) }
                Bitmap.createBitmap(rawBitmap, 0, 0, rawBitmap.width, rawBitmap.height, matrix, true)
            }

        val mpImage: MPImage = BitmapImageBuilder(uprightBitmap).build()
        val result = landmarker.detect(mpImage)
        val pose = result.landmarks().firstOrNull() ?: return null

        val outputWidth = uprightBitmap.width
        val outputHeight = uprightBitmap.height

        return pose.map { landmark ->
            mapOf(
                "x" to (landmark.x() * outputWidth).toDouble(),
                "y" to (landmark.y() * outputHeight).toDouble(),
                "z" to landmark.z().toDouble(),
                "visibility" to if (landmark.visibility().isPresent) landmark.visibility().get().toDouble() else 1.0,
            )
        }
    }

    private fun nv21ToBitmap(nv21: ByteArray, width: Int, height: Int): Bitmap {
        val out = ByteArrayOutputStream()
        YuvImage(nv21, ImageFormat.NV21, width, height, null).compressToJpeg(Rect(0, 0, width, height), 90, out)
        val jpegBytes = out.toByteArray()
        return BitmapFactory.decodeByteArray(jpegBytes, 0, jpegBytes.size)
    }
}
