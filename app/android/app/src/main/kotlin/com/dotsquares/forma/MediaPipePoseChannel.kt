package com.ds.forma

import android.content.Context
import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarkerResult
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * Bridges Flutter to a native MediaPipe Tasks Vision Pose Landmarker,
 * reached from Dart via `forma/pose_landmarker` (see
 * `lib/features/camera_coach/data/mediapipe/mediapipe_pose_detector.dart`).
 *
 * Mirrors `ios/Runner/MediaPipePoseChannel.swift`. The design follows the
 * GymDemo POC's Android fan-out, minus WebRTC: here the user's own phone
 * camera (Flutter `camera` plugin) is the only frame source, so there is no
 * shared capture pipeline to protect.
 *
 * ## What changed from the first version, and why
 *
 * - **`LIVE_STREAM` instead of `IMAGE`.** In `IMAGE` mode every frame is an
 *   independent full detection. `LIVE_STREAM` keeps tracking state between
 *   frames, so the heavy detector only runs when the pose is lost.
 * - **GPU delegate with CPU fallback.** The fallback is logged, never silent.
 * - **No JPEG round-trip.** The NV21 bytes used to be re-encoded to JPEG,
 *   decoded to a Bitmap and then rotated — two full-resolution copies per
 *   frame. The frame is now scaled, rotated and colour-converted in a single
 *   pass straight into a reusable 256x256 ARGB bitmap, letterboxed (never
 *   cropped, so head and feet stay in shot).
 * - **Model read from assets.** It used to be copied once to `filesDir` and
 *   never refreshed, so an app update that shipped a new `.task` file kept
 *   running the old one.
 *
 * ## The Dart contract is unchanged
 *
 * `detect` still resolves with 33 landmarks in the *upright frame's pixel
 * space* (or `null`), so `PoseCoachService` needs no changes. Internally the
 * result is now delivered by MediaPipe's async listener; the MethodChannel
 * reply is held until then. One detection is in flight at a time — Dart's
 * `_isBusy` gate guarantees it, and [pending] enforces it here, which is also
 * what makes reusing a single [bitmap] safe (MediaPipe reads it
 * asynchronously).
 */
object MediaPipePoseChannel {
    private const val TAG = "MediaPipePoseChannel"
    private const val CHANNEL_NAME = "forma/pose_landmarker"
    private const val MODEL_ASSET_PATH = "assets/models/pose_landmarker_full.task"

    /** Pre-v2 location of the copied model; removed so it cannot go stale. */
    private const val LEGACY_MODEL_FILE_NAME = "pose_landmarker_full.task"

    /** Square edge handed to inference. The model works at 256x256 internally. */
    private const val SIZE = 256

    /**
     * A reply that never arrives would wedge Dart's `_isBusy` gate forever, so
     * a detection is abandoned (reported as "no pose") after this long.
     */
    private const val RESULT_TIMEOUT_MS = 2_000L

    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile private var landmarker: PoseLandmarker? = null

    /** The delegate actually in use; "CPU (fallback)" when GPU failed to init. */
    @Volatile var activeDelegate: String = "none"
        private set

    /** Where the frame sits inside the inference square, in pixels. */
    private class Geometry(
        val uprightWidth: Int,
        val uprightHeight: Int,
        val contentWidth: Int,
        val contentHeight: Int,
        val padX: Int,
        val padY: Int,
    )

    private class Pending(
        val token: Long,
        val timestampMs: Long,
        val result: MethodChannel.Result,
        val geometry: Geometry,
    )

    private val pendingLock = Any()
    private var pending: Pending? = null
    private var nextToken = 0L
    private var lastTimestampMs = 0L

    // Reused across frames. Touched only on [executor] while a detection is
    // claimed, and read by MediaPipe only until the result listener fires.
    private val pixels = IntArray(SIZE * SIZE)
    private val bitmap: Bitmap = Bitmap.createBitmap(SIZE, SIZE, Bitmap.Config.ARGB_8888)

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
                    executor.execute { submit(context, bytes, width, height, rotationDegrees, result) }
                }
                else -> result.notImplemented()
            }
        }
    }

    // ---- Landmarker lifecycle ------------------------------------------------

    @Synchronized
    private fun ensureLandmarker(context: Context) {
        if (landmarker != null) return

        // Drop the copy the first version made; the model now loads from assets.
        File(context.filesDir, LEGACY_MODEL_FILE_NAME).takeIf { it.exists() }?.delete()

        val assetKey = FlutterInjector.instance().flutterLoader().getLookupKeyForAsset(MODEL_ASSET_PATH)

        var built = tryBuild(context, assetKey, Delegate.GPU)
        if (built != null) {
            activeDelegate = "GPU"
        } else {
            Log.w(TAG, "GPU delegate failed to initialise; falling back to CPU")
            built = tryBuild(context, assetKey, Delegate.CPU)
            activeDelegate = if (built != null) "CPU (fallback)" else "none"
        }
        landmarker = built ?: throw IllegalStateException("pose landmarker failed to initialise")
        Log.i(TAG, "landmarker ready delegate=$activeDelegate")
    }

    private fun tryBuild(context: Context, assetKey: String, delegate: Delegate): PoseLandmarker? =
        try {
            val baseOptions = BaseOptions.builder().setModelAssetPath(assetKey).setDelegate(delegate).build()
            val options =
                PoseLandmarker.PoseLandmarkerOptions.builder()
                    .setBaseOptions(baseOptions)
                    .setRunningMode(RunningMode.LIVE_STREAM)
                    .setNumPoses(1)
                    .setResultListener { result, _ -> onResult(result) }
                    .setErrorListener { e -> onError(e) }
                    .build()
            PoseLandmarker.createFromOptions(context, options)
        } catch (e: Throwable) {
            // Throwable, not Exception: a missing GPU delegate surfaces as
            // UnsatisfiedLinkError / NoClassDefFoundError on some devices.
            Log.e(TAG, "landmarker build failed for $delegate", e)
            null
        }

    // ---- One detection -------------------------------------------------------

    private fun submit(
        context: Context,
        bytes: ByteArray,
        width: Int,
        height: Int,
        rotationDegrees: Int,
        result: MethodChannel.Result,
    ) {
        var token = -1L
        try {
            ensureLandmarker(context)
            val lm = landmarker ?: throw IllegalStateException("landmarker not ready")
            if (bytes.size < width * height * 3 / 2) {
                throw IllegalArgumentException("NV21 buffer too small: ${bytes.size} for ${width}x$height")
            }

            val rotation = ((rotationDegrees % 360) + 360) % 360
            val geometry = geometryFor(width, height, rotation)

            val claimed: Pending
            synchronized(pendingLock) {
                if (pending != null) {
                    // Should be unreachable: Dart drops frames while busy. Refuse
                    // rather than overwrite the bitmap MediaPipe is still reading.
                    mainHandler.post { result.success(null) }
                    return
                }
                var ts = SystemClock.uptimeMillis()
                if (ts <= lastTimestampMs) ts = lastTimestampMs + 1 // must strictly increase
                lastTimestampMs = ts
                token = ++nextToken
                claimed = Pending(token, ts, result, geometry)
                pending = claimed
            }
            mainHandler.postDelayed({ complete(claimed.token, null) }, RESULT_TIMEOUT_MS)

            nv21ToSquare(bytes, width, height, rotation, geometry)
            bitmap.setPixels(pixels, 0, SIZE, 0, 0, SIZE, SIZE)
            lm.detectAsync(BitmapImageBuilder(bitmap).build(), claimed.timestampMs)
        } catch (e: Exception) {
            // A single bad frame should never surface as a crash — report "no
            // pose" for this frame and let the next frame try again. Logged (not
            // surfaced to Dart as an error) so a real per-frame failure is still
            // visible in logcat instead of looking identical to "no body".
            Log.w(TAG, "detect failed", e)
            if (token >= 0) complete(token, null) else mainHandler.post { result.success(null) }
        }
    }

    /** MediaPipe's callback thread. Delivers the held reply. */
    private fun onResult(result: PoseLandmarkerResult) {
        val claimed = synchronized(pendingLock) { pending } ?: return
        // A late result for a frame we already gave up on must not be handed to
        // the next frame, whose geometry may differ.
        if (result.timestampMs() != claimed.timestampMs) return

        val pose = result.landmarks().firstOrNull()
        val payload = pose?.map { landmark ->
            val g = claimed.geometry
            // Landmarks are normalised to the whole square, letterbox padding
            // included — undo the pad, then scale to the upright frame's pixels.
            val ux = (landmark.x() * SIZE - g.padX) / g.contentWidth
            val uy = (landmark.y() * SIZE - g.padY) / g.contentHeight
            mapOf(
                "x" to (ux * g.uprightWidth).toDouble(),
                "y" to (uy * g.uprightHeight).toDouble(),
                "z" to landmark.z().toDouble(),
                "visibility" to if (landmark.visibility().isPresent) landmark.visibility().get().toDouble() else 1.0,
            )
        }
        complete(claimed.token, payload)
    }

    private fun onError(e: RuntimeException) {
        Log.e(TAG, "inference error", e)
        // MUST release the held reply, or Dart's `_isBusy` never clears and the
        // coach looks healthy (camera live, UI up) with pose detection dead.
        val claimed = synchronized(pendingLock) { pending } ?: return
        complete(claimed.token, null)
    }

    /** Idempotent: only the first completion for a token replies. */
    private fun complete(token: Long, payload: List<Map<String, Any>>?) {
        val claimed =
            synchronized(pendingLock) {
                val p = pending
                if (p == null || p.token != token) return
                pending = null
                p
            }
        mainHandler.post { claimed.result.success(payload) }
    }

    // ---- Frame conversion ----------------------------------------------------

    /**
     * Largest upright rectangle with the frame's aspect ratio that fits the
     * square. Even dimensions only, so the chroma arithmetic stays simple.
     * Letterboxed rather than centre-cropped: a crop on a portrait phone
     * discards the head and feet of a standing person.
     */
    private fun geometryFor(width: Int, height: Int, rotation: Int): Geometry {
        val quarterTurn = rotation == 90 || rotation == 270
        val uprightW = if (quarterTurn) height else width
        val uprightH = if (quarterTurn) width else height
        val longEdge = maxOf(uprightW, uprightH)
        val contentW = even(SIZE * uprightW / longEdge)
        val contentH = even(SIZE * uprightH / longEdge)
        return Geometry(uprightW, uprightH, contentW, contentH, (SIZE - contentW) / 2, (SIZE - contentH) / 2)
    }

    private fun even(v: Int): Int = if (v < 2) 2 else v and 1.inv()

    /**
     * NV21 -> upright, letterboxed 256x256 ARGB in [pixels], in one pass.
     *
     * For each destination pixel the matching source position is found by
     * inverting the rotation, so scaling, rotation and colour conversion share
     * one loop over ~50k pixels instead of two full-resolution copies. Luma is
     * a 2x2 average to soften the ~2.5x downscale; chroma is nearest.
     * BT.601 limited range, same coefficients as the GymDemo converter.
     */
    private fun nv21ToSquare(nv21: ByteArray, w: Int, h: Int, rotation: Int, g: Geometry) {
        java.util.Arrays.fill(pixels, 0xFF000000.toInt())
        val vuBase = w * h

        for (cy in 0 until g.contentHeight) {
            val v = (cy + 0.5f) / g.contentHeight
            for (cx in 0 until g.contentWidth) {
                val u = (cx + 0.5f) / g.contentWidth
                // Upright (u, v) -> source (a, b), inverting the clockwise rotation.
                val a: Float
                val b: Float
                when (rotation) {
                    90 -> { a = v; b = 1f - u }
                    180 -> { a = 1f - u; b = 1f - v }
                    270 -> { a = 1f - v; b = u }
                    else -> { a = u; b = v }
                }
                val sx = (a * w).toInt().coerceIn(0, w - 1)
                val sy = (b * h).toInt().coerceIn(0, h - 1)
                val sx1 = minOf(sx + 1, w - 1)
                val sy1 = minOf(sy + 1, h - 1)

                val luma =
                    ((nv21[sy * w + sx].toInt() and 0xFF) +
                        (nv21[sy * w + sx1].toInt() and 0xFF) +
                        (nv21[sy1 * w + sx].toInt() and 0xFF) +
                        (nv21[sy1 * w + sx1].toInt() and 0xFF)) shr 2

                val uvIndex = minOf(vuBase + (sy shr 1) * w + (sx and 1.inv()), nv21.size - 2)
                val cr = (nv21[uvIndex].toInt() and 0xFF) - 128 // NV21 is V then U
                val cb = (nv21[uvIndex + 1].toInt() and 0xFF) - 128

                val y1192 = 1192 * (luma - 16)
                val r = (y1192 + 1634 * cr) shr 10
                val gr = (y1192 - 833 * cr - 400 * cb) shr 10
                val bl = (y1192 + 2066 * cb) shr 10

                pixels[(g.padY + cy) * SIZE + g.padX + cx] =
                    0xFF000000.toInt() or (clamp(r) shl 16) or (clamp(gr) shl 8) or clamp(bl)
            }
        }
    }

    private fun clamp(v: Int): Int = if (v < 0) 0 else if (v > 255) 255 else v
}
