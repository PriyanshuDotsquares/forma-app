import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/providers.dart';
import '../data/workout_repository.dart';
import '../domain/workout_session.dart';

final workoutRepositoryProvider = Provider<WorkoutRepository>((ref) => WorkoutRepository(ref.watch(apiClientProvider)));

/// Recent sessions (most-recent-first), used by the coach entry screen to
/// decide between "resume workout" / "start a workout" / the empty state,
/// and by history views elsewhere.
final sessionListProvider = FutureProvider.autoDispose<List<WorkoutSession>>((ref) async {
  final repo = ref.watch(workoutRepositoryProvider);
  return repo.listSessions(limit: 20);
});

/// A larger, separate page of sessions for the workout-history screen's
/// calendar + grouped list, which need more than the 20 `sessionListProvider`
/// fetches for its "vs last time" baselines — kept as its own provider so
/// that screen's fetch size doesn't change what those callers see.
final workoutHistoryProvider = FutureProvider.autoDispose<List<WorkoutSession>>((ref) async {
  final repo = ref.watch(workoutRepositoryProvider);
  return repo.listSessions(limit: 200);
});

/// A single session by id, re-fetched whenever invalidated (e.g. after
/// logging a set or finishing the session).
final sessionProvider = FutureProvider.autoDispose.family<WorkoutSession, String>((ref, sessionId) async {
  final repo = ref.watch(workoutRepositoryProvider);
  return repo.getSession(sessionId);
});

/// Handoff for "the user just confirmed camera setup and is back on the
/// active-workout screen" — holds the `sessionId` (or `null`) whose active-
/// workout screen should show the live-tracking overlay for its *current*
/// set. Set by `CameraPrecheckScreen` right before it pops; read (and
/// cleared) by `ActiveWorkoutScreen`.
///
/// Keyed by session rather than by program-exercise id so it works
/// uniformly for freestyle sets too (which have no `ProgramExercise`, and
/// so no id to key on) — `ActiveWorkoutScreen` already knows which
/// exercise/set is "current" from its own state, it just needs to know
/// *whether* to switch into live-tracking mode.
///
/// This exists because the `/workout/active/:sessionId` route (defined in
/// `core/router/app_router.dart`, which this feature must not edit) only
/// ever builds `ActiveWorkoutScreen(sessionId: ...)` — its builder doesn't
/// read `GoRouterState.extra`, so there's no way to thread "start live
/// coaching" through the route itself. A tiny shared provider is the
/// simplest way to pass that one bit of intent between the two screens
/// without touching the router.
final pendingCameraCoachProvider = StateProvider<String?>((ref) => null);
