import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../programs/domain/exercise.dart';
import '../../../programs/presentation/programs_providers.dart';

final _exerciseLibraryProvider = FutureProvider.autoDispose<List<Exercise>>(
  (ref) => ref.watch(programsRepositoryProvider).listExercises(),
);

/// Opens a searchable exercise picker (used by freestyle workouts to add an
/// exercise that isn't part of a program day). Returns the chosen
/// [Exercise], or `null` if dismissed.
Future<Exercise?> showExercisePickerSheet(BuildContext context) {
  return showModalBottomSheet<Exercise>(context: context, isScrollControlled: true, builder: (context) => const ExercisePickerSheet());
}

class ExercisePickerSheet extends ConsumerStatefulWidget {
  const ExercisePickerSheet({super.key});

  @override
  ConsumerState<ExercisePickerSheet> createState() => _ExercisePickerSheetState();
}

class _ExercisePickerSheetState extends ConsumerState<ExercisePickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final exercisesAsync = ref.watch(_exerciseLibraryProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('ADD EXERCISE', style: AppTypography.display(size: 18)),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _searchController,
                decoration: const InputDecoration(hintText: 'Search exercises', prefixIcon: Icon(Icons.search)),
                onChanged: (value) => setState(() => _query = value.trim().toLowerCase()),
              ),
              const SizedBox(height: AppSpacing.md),
              Expanded(
                child: exercisesAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (error, stack) =>
                      Center(child: Text('Could not load exercises.', style: AppTypography.body(color: AppColors.textSecondary))),
                  data: (exercises) {
                    final filtered = _query.isEmpty
                        ? exercises
                        : exercises.where((e) => e.name.toLowerCase().contains(_query)).toList();
                    if (filtered.isEmpty) {
                      return Center(child: Text('No matches.', style: AppTypography.body(color: AppColors.textSecondary)));
                    }
                    return ListView.separated(
                      controller: scrollController,
                      itemCount: filtered.length,
                      separatorBuilder: (context, i) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final exercise = filtered[i];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(exercise.name, style: AppTypography.body(size: 15, weight: FontWeight.w600)),
                          subtitle: Text(exercise.muscleSummary, style: AppTypography.body(size: 12, color: AppColors.textSecondary)),
                          trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
                          onTap: () => Navigator.of(context).pop(exercise),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
