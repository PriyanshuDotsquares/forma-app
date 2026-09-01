import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/program.dart';
import 'programs_providers.dart';

/// Single source of truth for the user's active program — shared by the
/// plan overview and day editor screens so a mutation made in one place
/// (add/update/remove an exercise, add/update a day) is reflected in the
/// other without a duplicate network round-trip living in each screen.
class ActiveProgramController extends AsyncNotifier<Program?> {
  @override
  Future<Program?> build() async {
    return ref.watch(programsRepositoryProvider).getActiveProgram();
  }

  /// (Re)generates a program — used both for the very first plan and to
  /// retry after a failed generation, and for the "Regenerate" action on
  /// the plan overview screen. Params let the onboarding plan-preview
  /// screen regenerate with the same quiz answers rather than the
  /// paramless defaults a bare retry would use.
  Future<void> regenerate({
    String? goal,
    String? experienceLevel,
    int? daysPerWeek,
    int? sessionMinutes,
    String? splitPreference,
    List<String>? equipment,
  }) async {
    final repository = ref.read(programsRepositoryProvider);
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => repository.generateProgram(
        goal: goal,
        experienceLevel: experienceLevel,
        daysPerWeek: daysPerWeek,
        sessionMinutes: sessionMinutes,
        splitPreference: splitPreference,
        equipment: equipment,
      ),
    );
  }

  /// Re-fetches the active program from the server — call after any
  /// mutation made through [ProgramsRepository] so this cache stays fresh.
  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

final activeProgramControllerProvider = AsyncNotifierProvider<ActiveProgramController, Program?>(
  ActiveProgramController.new,
);
