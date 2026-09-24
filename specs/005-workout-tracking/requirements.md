Status: Approved (Retroactive Baseline — documents behavior as implemented, dated 2026-09-10)
Owner: Engineering team (retroactive)
Related: n/a

## Summary

Module 005 owns the active-workout logging experience: starting a session (from a program day or freestyle), recording sets (weight/reps/RPE or camera-coached reps/form), resting between sets, celebrating PRs, and reviewing what happened afterward (post-workout summary, form report, history calendar). It is the session/set-logging UI and data flow layer — it consumes the pose-detection/rep-counting/voice-coaching engine that lives in module 006 (`app/lib/features/camera_coach/`) but does not implement that ML itself.

Primary files: `app/lib/features/workout/data/workout_repository.dart`, `app/lib/features/workout/domain/workout_session.dart`, `app/lib/features/workout/presentation/*.dart` and `presentation/widgets/*.dart`, `backend/app/api/v1/endpoints/workouts.py`, `backend/app/models/workout.py`, `backend/app/schemas/workout.py`, `backend/app/services/records.py`.

## Background / Problem

A strength-training app needs a way to turn a prescribed program day (or an ad hoc "freestyle" choice) into a live, in-progress session where the lifter records what they actually did — weight, reps, optionally camera-observed form/depth — set by set, with rest timers and progress feedback in between, and a summary/history to look back on. This module implements that loop end to end, in two parallel input flows (manual entry and camera-coached entry) that converge on the same backend set-logging endpoint.

## User Stories

### Flow 1 — Manual set-logging

1. As a lifter, I can start a workout against today's program day, or go freestyle with no plan, so I have a session to log sets into. (`CoachEntryScreen._startWorkout`, `presentation/coach_entry_screen.dart:23`; `showStartWorkoutSheet`, `presentation/widgets/start_workout_sheet.dart`)
2. As a lifter, I can resume an in-progress (unfinished) session instead of starting a new one. (`CoachEntryScreen.build`, `presentation/coach_entry_screen.dart:93-99`, `_ResumeCard`)
3. As a lifter, I can see my plan for the current exercise (target reps, target weight/RPE, set count) seeded from the program day, or build up a freestyle plan by adding exercises and sets manually. (`_ActiveWorkoutScreenState._initializePlan`, `presentation/active_workout_screen.dart:125-216`; `_addFreestyleExercise`, line 221; `showExercisePickerSheet`, `presentation/widgets/exercise_picker_sheet.dart`)
4. As a lifter, I can tap a set row to type in the exact weight and reps I did, pick NORMAL/WARM-UP/DROP set type, and see the plate-math breakdown for barbell exercises. (`showSetEntrySheet`/`SetEntrySheet`, `presentation/widgets/set_entry_sheet.dart`; `computePlateBreakdown`, `presentation/widgets/plate_math.dart:38`)
5. As a lifter, I can log the current set, which posts it to the backend, shows a post-set summary, and (if it's a PR) a celebration screen first. (`_ActiveWorkoutScreenState._logCurrentSet`, `presentation/active_workout_screen.dart:324-437`)
6. As a lifter, after logging a set I get a rest timer with a preview of my next set and (when applicable) a coaching note, before continuing. (`showRestTimerSheet`, `presentation/widgets/rest_timer_sheet.dart`)
7. As a lifter, finishing my last set automatically finishes the workout and takes me to the summary screen. (`_finishWorkout`, `presentation/active_workout_screen.dart:439-452`)
8. As a lifter, I can end the workout early or delete it entirely from the top-bar menu, and I'm asked to confirm before leaving an in-progress workout. (`_TopBar` menu + `_handleMenu`, lines 502-514; `_confirmExit`, lines 483-500)
9. As a lifter, I can review a finished workout's totals (duration, volume, sets, reps, calories, avg form), any PRs, an exercise-by-exercise breakdown, a muscles-trained diagram, and record RPE/mood/notes for it. (`WorkoutSummaryScreen`/`_Body`, `presentation/workout_summary_screen.dart`)
10. As a lifter, I can browse a calendar heatmap and grouped list of past sessions, with PR and form-score badges. (`WorkoutHistoryScreen`, `presentation/workout_history_screen.dart`)

### Flow 2 — Camera-coached set-logging

11. As a lifter, from an exercise that supports camera coaching, I can open a camera precheck screen that live-evaluates framing (full body in frame, side view, too close, lighting) before I start the set. (`CameraPrecheckScreen`/`_evaluate`, `presentation/camera_precheck_screen.dart:36-78`)
12. As a lifter, if the camera or permission isn't available, I can still fall back to logging the set manually instead of being blocked. (`PoseServiceInitResult.permissionDenied` / `.noCameraAvailable` branches, `presentation/camera_precheck_screen.dart:182-220`)
13. As a lifter, once I confirm I'm ready, the app hands off to a full-screen live tracking view that overlays my skeleton, counts reps, shows a rolling ROM ring, flags joints in red when form breaks down, and speaks cues/encouragement. (`LiveTrackingOverlay`, `presentation/widgets/live_tracking_overlay.dart`; `PoseSkeletonPainter`, `presentation/widgets/pose_painter.dart`)
14. As a lifter, when I finish the camera-coached set, its rep count / form score / good-bad rep split / flagged joint prefill the normal (still-editable) set-entry row rather than being logged automatically. (`LiveSetResult`, `presentation/widgets/live_tracking_overlay.dart:20-46`; `_handleLiveSetFinished`, `presentation/active_workout_screen.dart:459-476`)
15. As a lifter, I still tap LOG SET to actually submit that camera-assisted set — the camera flow never calls the workout API directly. (comment, `presentation/widgets/live_tracking_overlay.dart:16-19`; `_logCurrentSet`, `presentation/active_workout_screen.dart:324`)
16. As a lifter, after a camera-coached session I can open a form report that shows my form score trend, depth-by-rep, and "what came up" cues (fatigue effect, depth consistency) for whichever exercise I coached. (`FormReportScreen`, `presentation/form_report_screen.dart`)

## Acceptance Criteria (EARS format: "WHEN/IF ... THE SYSTEM SHALL ...")

**Session lifecycle**
- WHEN the user starts a workout with a chosen program day, THE SYSTEM SHALL POST to `/workouts/sessions` with `program_day_id` and a label, and create a `WorkoutSession` row. (`workouts.py:38-48`, `workout_repository.dart:12-22`)
- WHEN the user starts a workout without a program day (freestyle) or the active program fails to load, THE SYSTEM SHALL still create a session with `program_day_id` unset and build an empty, addable exercise plan. (`_startWorkout`, `coach_entry_screen.dart:23-53`; `_initializePlan` freestyle branch, `active_workout_screen.dart:155-187`)
- WHEN an unfinished session (`ended_at` is null) already exists for the user, THE SYSTEM SHALL surface a "Resume workout" card instead of prompting a new start. (`coach_entry_screen.dart:93-117`)
- WHEN the active-workout screen loads a session whose `endedAt` is already set, THE SYSTEM SHALL redirect to the workout-summary screen instead of rendering the logging UI. (`active_workout_screen.dart:540-545`)
- WHEN the user confirms "LEAVE" on the exit dialog, THE SYSTEM SHALL navigate away without deleting or finishing the session (progress stays saved server-side per already-logged sets). (`_confirmExit`, `active_workout_screen.dart:483-500`)
- WHEN the user selects "Delete workout" from the menu, THE SYSTEM SHALL DELETE `/workouts/sessions/{id}`, which cascades to delete all of its sets. (`_handleMenu`, `active_workout_screen.dart:505-513`; `WorkoutSession.sets` cascade, `models/workout.py:33-35`; `delete_session`, `workouts.py:79-87`)

**Set logging (both flows)**
- WHEN the user logs a set, THE SYSTEM SHALL POST to `/workouts/sessions/{id}/sets` with exercise id, set index, set type, target/actual weight, target/actual reps, and (if present) RPE placeholder fields, form score, and depth percentage. (`logSet`, `workout_repository.dart:50-83`; `WorkoutSetCreate`, `schemas/workout.py:9-19`)
- IF the exercise's equipment list contains `barbell` and the plan's load type is `weight`, THEN THE SYSTEM SHALL show the plate-math breakdown in the set-entry sheet. (`_editRow`, `active_workout_screen.dart:253-262`; `computePlateBreakdown`, `plate_math.dart:38-55`)
- WHEN a barbell target weight is below the bar weight, THE SYSTEM SHALL clamp the plate remainder to zero rather than compute a negative per-side weight. (`computePlateBreakdown`, `plate_math.dart:39`)
- WHEN every set for the current exercise is done and it is the last exercise in the plan, THE SYSTEM SHALL treat the just-logged set as the workout's final set and call finish-session instead of opening a rest timer. (`_logCurrentSet`, `active_workout_screen.dart:377-420`)
- WHEN a logged set is not the workout's final set, THE SYSTEM SHALL show the rest-timer sheet (defaulting to the user's `restTimerDefaultS`, else 90s) before returning control to the lifter. (`active_workout_screen.dart:422-429`)
- WHEN the backend's PR check flags a set as a PR (`is_pr = true`), THE SYSTEM SHALL show the full-screen PR celebration before the post-set summary sheet. (`_logCurrentSet`, `active_workout_screen.dart:380-402`)

**PR detection (backend)**
- WHEN a set is logged with both an actual weight and actual reps, THE SYSTEM SHALL compute an estimated 1RM via the Epley formula and compare it against the user's best `PersonalRecord` for that exercise. (`estimate_1rm_kg`, `maybe_record_pr`, `services/records.py:10-54`)
- IF the new estimated 1RM exceeds the stored best (or none exists), THEN THE SYSTEM SHALL insert a new `PersonalRecord` row and set `workout_set.is_pr = true`. (`services/records.py:40-54`)
- IF a set has no actual weight or a falsy actual reps, THEN THE SYSTEM SHALL skip PR evaluation entirely. (`services/records.py:29-30`)

**Session finishing**
- WHEN a session is finished, THE SYSTEM SHALL stamp `ended_at`, compute `duration_s` from the client value or elapsed wall time, and average all logged sets' `form_score` into `avg_form_score`. (`finish_session`, `workouts.py:128-147`)
- WHEN a session is finished, THE SYSTEM SHALL award XP to the user: `50 + 5 × (number of sets) + 20 × (number of PR sets)`. (`workouts.py:148-149`)
- WHEN a session is finished, THE SYSTEM SHALL re-evaluate achievements for the user. (`evaluate_achievements`, `workouts.py:152`)
- WHEN the workout-summary screen's RPE, mood, or notes controls change, THE SYSTEM SHALL re-call finish-session with the updated field(s), which is safe to call repeatedly (idempotent for this purpose). (`_submit`, `workout_summary_screen.dart:77-97`; comment at `workout_summary_screen.dart:44-47`)

**Camera-coached flow**
- WHEN camera permission is denied or no camera is available, THE SYSTEM SHALL present a fallback that lets the user continue logging the set manually rather than blocking the workout. (`camera_precheck_screen.dart:182-220`)
- WHEN the live-tracking overlay's pose stream produces confident landmarks for a joint group whose angle crosses the configured bottom-then-top thresholds, THE SYSTEM SHALL count one rep for that exercise's movement pattern. (`RepCounter` config selection, `pose_angle_mapper.dart:127-150`, consumed by `live_tracking_overlay.dart:93-98` — counting logic itself is module 006)
- WHEN the user taps "FINISH SET" in the live-tracking overlay, THE SYSTEM SHALL stop the pose stream and return a `LiveSetResult` (reps, form score, ROM%, good/bad rep counts, dominant flagged joint) to the caller without logging anything itself. (`_finish`, `live_tracking_overlay.dart:165-178`)
- WHEN a `LiveSetResult` is returned, THE SYSTEM SHALL prefill the current set row's reps (if >0), form-score hint, ROM hint, good/bad rep hints, and flagged-joint hint, leaving the row still editable and unlogged. (`_handleLiveSetFinished`, `active_workout_screen.dart:459-476`)
- WHEN the user cancels out of the camera precheck or live tracking without finishing, THE SYSTEM SHALL clear the pending-camera-coach handoff state and return to the manual set row unchanged. (`_leave`/skip options, `camera_precheck_screen.dart:155-165,196,214,263`; `_handleLiveTrackingCancel`, `active_workout_screen.dart:478-481`)

**History / form report**
- WHEN the workout-history screen loads, THE SYSTEM SHALL fetch up to 200 recent sessions and derive the calendar heatmap and grouped list entirely client-side (no server-side date-range endpoint exists). (`workoutHistoryProvider`, `workout_providers.dart:21-24`; comment, `workout_history_screen.dart:45-50`)
- IF a session's sets include a PR, THEN THE SYSTEM SHALL mark that calendar day with an amber PR outline and the session row with a "N PR" badge. (`_CalendarCard`/`_DayCell`, `workout_history_screen.dart:172-259`; `_SessionRow`, lines 296-347)
- WHEN the form-report screen has no set with a form score or depth percentage for the session, THE SYSTEM SHALL show an empty state instead of an empty chart. (`_Body.build`, `form_report_screen.dart:113-124`)

## Out of Scope

- The pose-detection/ML inference, rep-counting state machine, form-heuristics scoring, and voice-coach TTS themselves — owned by module 006 (`app/lib/features/camera_coach/`); this module only consumes their public types (`PoseCoachService`, `RepCounter`, `FormHeuristics`, `VoiceCoach`, `Pose`) and renders their output (`pose_painter.dart`, `pose_angle_mapper.dart`).
- Program/exercise authoring, active-program selection logic — owned by the `programs` feature (`programs_providers.dart`, `programs_repository`), only read here.
- Achievements definitions and evaluation logic — owned by `services/achievements.py`, only invoked here on session finish.
- Per-rep tempo curves or named form-fault video clips — explicitly not captured anywhere in the data model; the form report only ever uses `formScore`/`depthPct` per set (comment, `form_report_screen.dart:27-31`).
- RPE is accepted as a request field on both set-logging (`WorkoutSetCreate.rpe`) and session-finish (`WorkoutSessionFinish.rpe`), but the active-workout UI has no control that sets a per-set RPE value — only the post-workout summary screen's RPE selector, which writes to the session, not a set.

## Non-Functional Requirements

- Set-logging round trip: the active-workout screen blocks further interaction on the specific set row until `logSet` resolves, surfacing `ApiException.message` via a `SnackBar` on failure rather than silently failing. (`_logCurrentSet` try/catch, `active_workout_screen.dart:434-436`)
- The elapsed-time ticker (`Timer.periodic`, 1s) is purely a local UI clock seeded from `DateTime.now().difference(session.startedAt)` on load and is not persisted or synced against the server during the session. (`active_workout_screen.dart:113-117,127`)
- List endpoints cap `limit` at 100 server-side regardless of what the client requests. (`list_sessions`, `workouts.py:58`)
- The precheck screen's framing heuristics (full-body-in-frame, side-view, lighting) are explicitly approximate proxies, not precise measurements, per their own doc comments. (`camera_precheck_screen.dart:16-19,44,52-53,67-69`)
- Camera teardown on the precheck screen is guarded against duplicate/overlapping `dispose()` calls via a `_leaving` flag (see design.md's Risks/Edge Cases for the full mechanism).

## Open Questions

- None recorded in code comments beyond what's captured as Out of Scope above; this baseline documents only what the existing code and its own comments state.
