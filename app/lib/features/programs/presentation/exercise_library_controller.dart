import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/exercise.dart';
import 'programs_providers.dart';

/// The full exercise catalog (unfiltered) — the library screen applies
/// search/muscle/equipment filters client-side against this list so
/// filtering feels instant rather than round-tripping per keystroke.
class ExerciseLibraryController extends AsyncNotifier<List<Exercise>> {
  @override
  Future<List<Exercise>> build() {
    return ref.watch(programsRepositoryProvider).listExercises();
  }
}

final exerciseLibraryControllerProvider = AsyncNotifierProvider<ExerciseLibraryController, List<Exercise>>(
  ExerciseLibraryController.new,
);
