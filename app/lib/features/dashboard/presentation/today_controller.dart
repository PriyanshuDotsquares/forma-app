import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../programs/domain/program.dart';
import '../../programs/presentation/programs_providers.dart';
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
    final programsRepository = ref.watch(programsRepositoryProvider);
    final workoutRepository = ref.watch(workoutRepositoryProvider);

    final program = await programsRepository.getActiveProgram();
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
    final programsRepository = ref.read(programsRepositoryProvider);
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await programsRepository.generateProgram();
      return build();
    });
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

final todayControllerProvider = AsyncNotifierProvider<TodayController, TodayData>(TodayController.new);
