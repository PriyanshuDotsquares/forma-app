Status: Approved (Retroactive Baseline — documents behavior as implemented, dated 2026-09-10)
Owner: Engineering team (retroactive)
Related: n/a

## Summary
The camera-coach engine (`app/lib/features/camera_coach/`) is a fully on-device, client-side pipeline that watches a live camera feed during a lift, detects the lifter's body pose every frame using Google's MediaPipe Tasks Vision Pose Landmarker (reached via a hand-written platform channel, not a Flutter plugin), derives joint angles, counts reps with a hysteresis state machine, scores form against a per-movement-pattern heuristic rule table, and speaks corrective/encouraging cues through `flutter_tts`. It has no backend component: no `camera_coach`-specific API endpoint exists anywhere in `backend/`, and none of the six files in this module import `dio`/`http`. The only place its output touches the network is indirect — module 005 (`workout` feature)'s `ActiveWorkoutScreen` copies the finished set's `formScore`/ROM into the same generic `POST /workouts/sessions/{id}/sets` call used for manually-logged sets, and only when the user explicitly taps "LOG SET".

## Background / Problem
FORMA coaches lifters through sets without a human trainer or wearable hardware. For camera-coachable exercises, the app needs to (a) count reps automatically instead of the lifter self-reporting, (b) give real-time form feedback without requiring the lifter to look at the screen (hence spoken cues), and (c) do all of this with a privacy guarantee — the camera feed is never uploaded (`NSCameraUsageDescription` in `app/ios/Runner/Info.plist:30`: "Video is processed on your device and is never uploaded."). This module is the engine that makes that possible; module 005's `camera_precheck_screen.dart` and `active_workout_screen.dart`/`live_tracking_overlay.dart` own the surrounding workout-logging UI and call into it.

## User Stories
- As a lifter doing a camera-coachable exercise, I tap "COACH SET" and go through a framing precheck (full body in frame, side view, distance, lighting) before the set starts, so I know the camera can actually see me.
- As a lifter mid-set, I see a live skeleton overlay on my camera feed that turns red on the joint that's currently out of form, so I get immediate visual feedback.
- As a lifter mid-set, I hear spoken corrections ("Tuck your elbows in") and rep-count callouts, so I don't have to watch the screen while lifting.
- As a lifter, my reps are counted automatically as I move through the full range of motion, rather than me tapping a counter.
- As a lifter, when I finish a set, I see how many reps were "good" vs. "needs work" and an overall 0-100 form score, prefilled into the normal set-entry row so I can still edit/confirm before logging.
- As a lifter, if camera permission is denied or no camera is available, I can still log the set manually rather than being blocked.
- As a lifter, I can control how chatty the voice coach is (off/minimal/standard/detailed) and whether it announces rep counts, via my account's `VoiceCoachSettings`.

## Acceptance Criteria (EARS format: "WHEN/IF ... THE SYSTEM SHALL ...")
- WHEN `PoseCoachService.initialize()` is called, THE SYSTEM SHALL request camera permission via `permission_handler` and return `PoseServiceInitResult.permissionDenied` if it is not granted (`data/pose_service.dart:86-89`).
- WHEN permission is granted, THE SYSTEM SHALL load the native MediaPipe pose-landmarker model and return `noCameraAvailable` if that load fails, rather than throwing (`data/pose_service.dart:91-95`).
- WHEN the detector is ready, THE SYSTEM SHALL enumerate available cameras, prefer the rear (back) camera, and fall back to whatever camera is available (e.g. front-only devices/emulators) or return `noCameraAvailable` if none exist (`data/pose_service.dart:97-110`).
- WHEN a camera is opened, THE SYSTEM SHALL configure it at `ResolutionPreset.medium` with audio disabled and platform-specific single-plane image format (`nv21` on Android, `bgra8888` on iOS) (`data/pose_service.dart:139-148`).
- WHEN `startStream` is running and a new camera frame arrives while the previous frame is still being processed, THE SYSTEM SHALL drop the new frame rather than queue it (`data/pose_service.dart:186-188`).
- IF a frame's raw pixel format or plane count doesn't match what the native detector expects, or device orientation can't be resolved, THE SYSTEM SHALL drop that frame (log it, report `null` pose) instead of crashing (`data/pose_service.dart:231-267`).
- IF native pose detection throws for a given frame (platform-channel hiccup, mid-rotation, etc.), THE SYSTEM SHALL catch it and report `null` pose for that frame only, continuing to stream (`data/pose_service.dart:203-211`).
- WHEN a pose is detected, THE SYSTEM SHALL derive `JointAngles` (elbow, hip, knee interior angles in degrees, plus a normalized bar-height proxy) from landmarks with `likelihood >= 0.5`, averaging left/right sides when both are confident and falling back to whichever single side is confident (`workout/presentation/widgets/pose_angle_mapper.dart:13-111`).
- WHEN `FormHeuristics.evaluateFrame()` runs on a frame's `JointAngles`, THE SYSTEM SHALL compare each active movement-pattern rule's joint value against a coach-authored ideal `[low, high]` degree range and emit a spoken-style cue plus a joint flag for every rule outside that range (`domain/form_heuristics.dart:198-221`).
- WHEN `RepCounter.addSample()` runs, THE SYSTEM SHALL count a rep only when the driving joint's value crosses below a bottom threshold and then back above a top threshold (two-line hysteresis, not a single midpoint) AND the resulting excursion is at least `minAngleDelta` (15°), filtering out shallow half-reps and jitter (`domain/rep_counter.dart:105-156`).
- WHEN a rep completes, THE SYSTEM SHALL grade it via `FormHeuristics.repLookedGood` (every rule's joint reached its ideal range at least once during that rep), reset per-rep tracking, and have `VoiceCoach` announce the rep number and, if the rep wasn't flagged, speak an encouragement line (`workout/presentation/widgets/live_tracking_overlay.dart:142-154`).
- WHEN a frame produces one or more active cues, THE SYSTEM SHALL speak the first cue through `VoiceCoach.speak()`, subject to a verbosity-based rate limiter (off: never; minimal: first cue of the set only; standard: ~once per 8s; detailed: ~once per 2s with de-duplication) (`data/voice_coach.dart:113-130`).
- IF `VoiceCoachSettings.enabled` is false or `verbosity` is `off`, THE SYSTEM SHALL speak nothing at all, including rep-count announcements (`data/voice_coach.dart:73-76, 92-96`).
- WHEN the lifter taps "FINISH SET", THE SYSTEM SHALL stop the camera stream and hand back a `LiveSetResult` (rep count, 0-100 average form score across every sampled frame, the last completed rep's ROM%, good/bad rep counts, and the most-flagged joint) to the calling screen — this module does not itself write to the backend (`workout/presentation/widgets/live_tracking_overlay.dart:165-178`).
- WHEN the camera-precheck screen evaluates the current pose, THE SYSTEM SHALL derive "full body in frame" (landmark bounding-box height ≥60% of frame, not touching top/bottom edges), "side view detected" (shoulder width small relative to body height), "too close" (spans frame but touches an edge), and "lighting looks good" (avg landmark confidence ≥0.7) as approximate signals, showing all as unmet if fewer than 15 landmarks are confidently visible (`workout/presentation/camera_precheck_screen.dart:36-77`).
- IF camera permission is denied, THE SYSTEM SHALL show an empty state offering "OPEN SETTINGS" (`openAppSettings()`) or "KEEP LOGGING MANUALLY" (`workout/presentation/camera_precheck_screen.dart:182-201`).
- IF no working camera is available (e.g. simulator/emulator), THE SYSTEM SHALL show a fallback allowing the lifter to keep logging manually rather than blocking the workout (`workout/presentation/camera_precheck_screen.dart:203-220`).
- WHEN the lifter switches cameras mid-session, THE SYSTEM SHALL stop the stream, dispose the old controller, open the new camera, and resume streaming automatically if it was previously streaming (`data/pose_service.dart:115-134`).
- WHEN the precheck screen or the live-tracking overlay is disposed, THE SYSTEM SHALL stop the image stream, dispose the `CameraController`, and stop any in-flight speech, guarding against double-disposal on non-standard exit paths (e.g. a system back-swipe) (`workout/presentation/camera_precheck_screen.dart:96-153`, `live_tracking_overlay.dart:191-196`).

## Out of Scope
- Any backend endpoint or server-side storage for pose/rep/form data — confirmed absent (`grep` across `backend/` for pose/rep/camera-coach terms returns only a comment referencing this module's own disclaimer text, in `backend/app/services/ai_plan_generator.py:107`).
- Video/frame recording or upload — frames are consumed in memory per-frame and discarded.
- Per-exercise-tuned ideal joint-angle ranges — scoring is keyed by one of 6 coarse `MovementPattern`s (press/squat/hinge/pull/bentOverRow/generic) shared across FORMA's ~46 seeded exercises, not tuned per exercise.
- GPU-accelerated inference — both platforms explicitly configure the MediaPipe CPU delegate.
- True 3D or biomechanically-validated form assessment — see Non-Functional Requirements; this is an explicitly-disclaimed 2D heuristic.
- Ducking other apps' background audio — `VoiceCoach.duckMusic` exists as a settings passthrough only; the class deliberately does not attempt real audio ducking (`data/voice_coach.dart:45-52`).
- Logging the set to the backend — persistence stays module 005's `WorkoutRepository.logSet()` responsibility, triggered only by an explicit "LOG SET" tap, not automatically on set finish.

## Non-Functional Requirements
- A single bad camera frame, a native-channel error, or a missing model asset must never crash the app — every native/platform-channel call site catches and degrades to "no pose"/an init-failure result (documented explicitly as a convention in `data/mediapipe/mediapipe_pose_detector.dart:22-26`).
- Frame processing is best-effort and drop-newest-when-busy rather than queued, so live coaching latency stays bounded on slower devices at the cost of not processing every frame.
- Pose detection must run entirely on-device with no network calls from this module (verified: no `dio`/`http` import in any of the 6 module files).
- Native `detect()` calls are serialized onto one dedicated background thread per platform (a `DispatchQueue` on iOS, a single-thread `Executor` on Android) because MediaPipe forbids concurrent calls against one landmarker instance and `detect()` blocks its calling thread.
- The native pose-landmarker instance is a process-lifetime singleton on both platforms, deliberately never torn down between coaching sessions, to avoid repeatedly reloading the ~9.4MB model (`ios/Runner/MediaPipePoseChannel.swift:10-20`, mirrored in `MediaPipePoseChannel.kt:27-38`).
- Spoken feedback is rate-limited per the user's verbosity setting so the coach doesn't talk over every rep or repeat itself back-to-back.

## Open Questions
None recorded — no TODO/FIXME comments or unresolved design notes found in any of the six module files, the native platform-channel implementations, or the module-005 call sites read for this baseline.
