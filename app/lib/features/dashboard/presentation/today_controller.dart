import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../programs/domain/program.dart';
import '../../programs/presentation/active_program_controller.dart';
import '../../progress/data/progress_providers.dart';
import '../../progress/domain/progress_models.dart';
import '../../workout/domain/workout_session.dart';
import '../../workout/presentation/workout_providers.dart';

/// Everything the "Today" tab needs in one round-trip: the active program
/// (to find today's/tomorrow's day), recent sessions (for the week strip,
/// streak/volume/form stats, and the "Recent" list), and best-effort
/// recovery data for the rest-day card.
class TodayData {
  const TodayData({required this.program, required this.sessions, required this.recovery});

  final Program? program;
  final List<WorkoutSession> sessions;
  final List<RecoveryItem> recovery;
}

class TodayController extends AsyncNotifier<TodayData> {
  @override
  Future<TodayData> build() async {
    final workoutRepository = ref.watch(workoutRepositoryProvider);

    // Derived from `activeProgramControllerProvider` — the Plan tab's
    // documented "single source of truth for the user's active program" —
    // instead of independently calling `getActiveProgram()`. This used to
    // fetch its own copy, which meant a regenerate from the Plan tab (or
    // onboarding) never reached this screen: both tabs stay alive in the
    // app's persistent shell, so Today's independently-fetched `Program`
    // just sat there stale until a pull-to-refresh or app restart, while
    // the Plan tab correctly showed the newest program — watching the
    // shared provider means any regenerate, from anywhere, is reflected
    // here automatically too.
    final program = await ref.watch(activeProgramControllerProvider.future);
    final sessions = await workoutRepository.listSessions(limit: 30);

    // Recovery is a nice-to-have on the rest-day card, not core to this
    // screen — don't let it block the rest of the dashboard from loading.
    List<RecoveryItem> recovery = const [];
    try {
      recovery = await ref.watch(recoveryProvider.future);
    } catch (_) {
      recovery = const [];
    }

    return TodayData(program: program, sessions: sessions, recovery: recovery);
  }

  /// There's no active program, but onboarding is already complete — the
  /// first generation attempt must have failed, so retry it.
  Future<void> regenerateProgram() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(activeProgramControllerProvider.notifier).regenerate();
      return build();
    });
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

final todayControllerProvider = AsyncNotifierProvider<TodayController, TodayData>(TodayController.new);
