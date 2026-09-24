Status: Approved (Retroactive Baseline — documents behavior as implemented, dated 2026-09-10)
Owner: Engineering team (retroactive)
Related: n/a

## Approach
`TodayScreen` is a thin presentation layer over a single aggregate `AsyncNotifier`, `TodayController` (`todayControllerProvider`), whose `TodayData` bundles everything the screen needs (`Program?`, `List<WorkoutSession>`, `List<RecoveryItem>`) in one `build()`. The controller does not own state — it composes three other features' providers/repositories on each build, so it has no independent cache to go stale: watching `activeProgramControllerProvider` in particular means any regenerate triggered elsewhere (Plan tab, onboarding) is picked up automatically since both tabs live in the same persistent `StatefulShellRoute`.

## Architecture / Data Flow
1. `TodayScreen` (`app/lib/features/dashboard/presentation/today_screen.dart:32`) watches `todayControllerProvider` and `authControllerProvider` (for the header greeting/avatar).
2. `TodayController.build()` (`today_controller.dart:24`) runs on load/refresh:
   a. `workoutRepositoryProvider` → `WorkoutRepository` (`app/lib/features/workout/presentation/workout_providers.dart:7`).
   b. `await ref.watch(activeProgramControllerProvider.future)` — the Plan tab's shared active-program controller (`app/lib/features/programs/presentation/active_program_controller.dart:51`), itself backed by `ProgramsRepository.getActiveProgram()`.
   c. `await workoutRepository.listSessions(limit: 30)` — most-recent-first sessions.
   d. `await ref.watch(recoveryProvider.future)` (`app/lib/features/progress/data/progress_providers.dart:32`), wrapped in try/catch — falls back to `const []` on any error so recovery never blocks the rest of the load.
3. Result is `TodayData(program, sessions, recovery)`; `TodayScreen` renders via `AsyncValue.when` (loading spinner / error empty-state with retry / `_Content`).
4. `_Content` derives today's `ProgramDay` by matching `DateTime.now().weekday` (converted from Dart's 1=Mon..7=Sun to the API's 0=Mon..6=Sun) against `program.days`, then branches: workout-day card (`_WorkoutDayCard`) vs. rest-day card (`_RestDayCard`) vs. no-program empty state (`_NoProgramCard`).
5. Client-side derived stats (`_ThisWeekSection`) — streak, weekly volume, weekly average form score, and the Mon–Sun trained strip — are computed locally from the 30 loaded `sessions`, not fetched from a dedicated stats endpoint (no dependency on `progressSummaryProvider`/`ProgressSummary`).
6. Actions dispatch into other features' repositories directly from the screen: `WorkoutRepository.startSession(programDayId, label)` (workout-day "START WORKOUT", rest-day "TRAIN ANYWAY") navigates to `AppRoutes.workoutActive(session.id)`; "Preview"/"Swap today's session" navigate to `AppRoutes.planSessionPreview`/`planDay`; the recent-session rows navigate to `AppRoutes.workoutSummary`; the coach banner navigates to `AppRoutes.coach`.
7. `refresh()` / `regenerateProgram()` on the controller call `ref.invalidateSelf()` + re-`build()`, or `activeProgramControllerProvider.notifier.regenerate()` followed by `build()`, respectively; both are wired to pull-to-refresh and the "GENERATE MY PLAN" button.

### Cross-module dependencies (cited, not re-documented here)
- **Programs** (`app/lib/features/programs/`): `activeProgramControllerProvider` (`presentation/active_program_controller.dart`) supplies the active `Program` (id, split, days-per-week, and `List<ProgramDay>` with weekday/label/muscleTags/isRest/exercises) — Today reads it to pick today's day and render the workout/rest card; also used for `ProgramDay`/`ProgramExercise` display fields.
- **Workout** (`app/lib/features/workout/`): `workoutRepositoryProvider` (`presentation/workout_providers.dart`) supplies `WorkoutRepository.listSessions()` (recent `WorkoutSession`s, used for the week strip, streak/volume/form stats, in-progress load detection, and the Recent list) and `.startSession()` (used to start today's or a freestyle workout).
- **Progress** (`app/lib/features/progress/`): `recoveryProvider` (`data/progress_providers.dart`) supplies `List<RecoveryItem>` (per-muscle-group `recoveredPct`/`setsLastSession`) used for the rest-day recovery breakdown and the compact recovery card.
- **Auth** (`app/lib/features/auth/`): `authControllerProvider` (`presentation/auth_controller.dart`) supplies the current `User?` (fullName, avatarUrl, onboardingCompleted) for the header greeting/avatar and to decide the no-program empty-state's call to action.

## Data / Schema
No new schema — this screen introduces no persisted model or endpoint of its own. `TodayData` (`today_controller.dart:14`) is a transient, in-memory composition of three other features' domain models (`Program`/`ProgramDay`, `WorkoutSession`/`WorkoutSet`, `RecoveryItem`), plus locally-derived, non-persisted view state: weekly streak (consecutive trained days ending today or yesterday), weekly volume (`Σ actualWeightKg × actualReps` for sets since Monday), and weekly average form score (`avg(avgFormScore)` over sessions since Monday). A synthesized "legs" `RecoveryItem` (`_legsRecoveryItem`, `today_screen.dart:294`) is computed client-side from the worst-recovered of `quads/hamstrings/glutes/calves` for the coarse chest/legs/back recovery bars, since the API tracks 10 finer muscle groups with no single "legs" entry.

## Alternatives Considered
N/A — retroactive baseline.

## Testing Strategy
No automated tests — gap. No test file references `TodayController`/`TodayScreen`/`today_controller`/`today_screen` anywhere under `app/test`.

## Risks / Edge Cases
- In-progress load detection (`_WorkoutDayCard`, `today_screen.dart:213-225`) only matches an unfinished session by same `programDayId` + started today; a freestyle session ("TRAIN ANYWAY") on what later becomes a workout day, or a session started just before midnight, would not be picked up as "in progress" for that day's strip.
- The coach banner's dismissed state (`_coachBannerDismissed`) is held in `_TodayScreenState` only — it resets on every screen rebuild/navigation away-and-back-into-shell, not persisted across app restarts.
- Notification bell icon (`today_screen.dart:143-146`) has an empty `onPressed: () {}` — present in the UI with no wired behavior.
- "10-MIN MOBILITY" action (`today_screen.dart:477`) only shows a "Coming soon." snackbar.
- Weekly stats and the trained-day strip are computed from only the last 30 fetched sessions; a user who trains more than 30 times without the app being reopened (unlikely in practice) could see an understated streak once sessions older than the 30-item window roll off.

## Backlog / Known Gaps
None found — no TODO/FIXME comments or dead code identified in `today_controller.dart` or `today_screen.dart` beyond the wired-but-inert notification bell and "Coming soon." mobility action noted above under Risks / Edge Cases.
