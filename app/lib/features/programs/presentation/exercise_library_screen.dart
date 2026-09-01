import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/app_router.dart';
import '../../achievements/data/achievements_providers.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/exercise.dart';
import 'exercise_library_controller.dart';
import 'widgets/exercise_body_map.dart';
import 'widgets/muscle_tag_chip.dart';

enum _ViewMode { list, bodyMap }

class ExerciseLibraryScreen extends ConsumerStatefulWidget {
  const ExerciseLibraryScreen({super.key});

  @override
  ConsumerState<ExerciseLibraryScreen> createState() => _ExerciseLibraryScreenState();
}

class _ExerciseLibraryScreenState extends ConsumerState<ExerciseLibraryScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  String? _muscleFilter;
  bool _myEquipmentOnly = false;
  bool _cameraOnly = false;
  _ViewMode _viewMode = _ViewMode.list;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  int get _activeFilterCount => (_muscleFilter != null ? 1 : 0) + (_myEquipmentOnly ? 1 : 0) + (_cameraOnly ? 1 : 0);

  void _clearFilters() {
    setState(() {
      _query = '';
      _searchController.clear();
      _muscleFilter = null;
      _myEquipmentOnly = false;
      _cameraOnly = false;
    });
  }

  void _openFilterSheet(List<String> userEquipment) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('FILTERS', style: AppTypography.display(size: 18)),
              const SizedBox(height: AppSpacing.md),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('My equipment only'),
                value: _myEquipmentOnly,
                onChanged: (v) {
                  setState(() => _myEquipmentOnly = v);
                  setSheetState(() {});
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Camera coaching available'),
                value: _cameraOnly,
                onChanged: (v) {
                  setState(() => _cameraOnly = v);
                  setSheetState(() {});
                },
              ),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {
                    _clearFilters();
                    setSheetState(() {});
                  },
                  child: const Text('CLEAR FILTERS'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(exerciseLibraryControllerProvider);
    final userEquipment = ref.watch(authControllerProvider).valueOrNull?.equipment ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('EXERCISES'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                IconButton(icon: const Icon(Icons.tune), onPressed: () => _openFilterSheet(userEquipment)),
                if (_activeFilterCount > 0)
                  Positioned(
                    right: 4,
                    top: 4,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                      decoration: const BoxDecoration(color: AppColors.accentBlue, shape: BoxShape.circle),
                      child: Text(
                        '$_activeFilterCount',
                        textAlign: TextAlign.center,
                        style: AppTypography.body(size: 10, weight: FontWeight.w700, color: AppColors.accentBlueDark),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: state.when(
          data: (all) => _buildBody(context, all, userEquipment),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: FormaEmptyState(
                icon: Icons.error_outline,
                title: 'Something went wrong.',
                message: error is ApiException ? error.message : 'Could not load exercises.',
                primaryLabel: 'RETRY',
                onPrimary: () => ref.invalidate(exerciseLibraryControllerProvider),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, List<Exercise> all, List<String> userEquipment) {
    var results = all;
    final query = _query.trim().toLowerCase();
    if (query.isNotEmpty) {
      results = results.where((e) => e.name.toLowerCase().contains(query)).toList();
    }
    if (_muscleFilter != null) {
      results = results.where((e) => e.primaryMuscles.contains(_muscleFilter)).toList();
    }
    if (_myEquipmentOnly) {
      results = results.where((e) => e.equipment.every(userEquipment.contains)).toList();
    }
    if (_cameraOnly) {
      results = results.where((e) => e.supportsCamera).toList();
    }

    final allMuscles = <String>{};
    for (final e in all) {
      allMuscles.addAll(e.primaryMuscles);
    }
    final muscles = allMuscles.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
          child: TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: 'Search ${all.length} exercises',
              prefixIcon: const Icon(Icons.search),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: SegmentedButton<_ViewMode>(
            segments: const [
              ButtonSegment(value: _ViewMode.list, label: Text('LIST'), icon: Icon(Icons.view_list_outlined)),
              ButtonSegment(
                value: _ViewMode.bodyMap,
                label: Text('BODY MAP'),
                icon: Icon(Icons.accessibility_new_outlined),
              ),
            ],
            selected: {_viewMode},
            onSelectionChanged: (s) => setState(() => _viewMode = s.first),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            children: [
              MuscleTagChip(
                'My equipment',
                selected: _myEquipmentOnly,
                onTap: () => setState(() => _myEquipmentOnly = !_myEquipmentOnly),
              ),
              const SizedBox(width: 8),
              MuscleTagChip(
                'Camera coaching',
                selected: _cameraOnly,
                onTap: () => setState(() => _cameraOnly = !_cameraOnly),
              ),
              const SizedBox(width: 8),
              ...muscles
                  .take(8)
                  .map(
                    (m) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: MuscleTagChip(
                        titleCaseMuscle(m),
                        selected: _muscleFilter == m,
                        onTap: () => setState(() => _muscleFilter = _muscleFilter == m ? null : m),
                      ),
                    ),
                  ),
            ],
          ),
        ),
        if (_viewMode == _ViewMode.list) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Text(
              '${results.length} exercises',
              style: AppTypography.mono(size: 14, color: AppColors.textSecondary),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        Expanded(
          child: _viewMode == _ViewMode.bodyMap
              ? SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  child: ExerciseBodyMap(
                    availableMuscles: allMuscles,
                    selected: _muscleFilter,
                    onSelect: (m) => setState(() {
                      _muscleFilter = m;
                      _viewMode = _ViewMode.list;
                    }),
                  ),
                )
              : (results.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: FormaEmptyState(
                            icon: Icons.search_off,
                            eyebrow: 'NO SEARCH RESULTS',
                            title: 'No exercises match that.',
                            message: 'Try removing a filter, or search a different name.',
                            primaryLabel: 'CLEAR FILTERS',
                            onPrimary: _clearFilters,
                          ),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xl),
                        children: [
                          const SectionLabel('ALL EXERCISES'),
                          const SizedBox(height: AppSpacing.sm),
                          ...results.map(
                            (e) => Padding(
                              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                              child: _ExerciseListRow(exercise: e),
                            ),
                          ),
                        ],
                      )),
        ),
      ],
    );
  }
}

const _difficultyLevels = ['beginner', 'intermediate', 'advanced'];

class _ExerciseListRow extends ConsumerWidget {
  const _ExerciseListRow({required this.exercise});

  final Exercise exercise;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasPr = ref.watch(personalRecordsProvider).valueOrNull?.any((r) => r.exerciseId == exercise.id) ?? false;
    final filledDots = _difficultyLevels.indexOf(exercise.difficulty) + 1;

    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.card),
      onTap: () => context.push(AppRoutes.planExerciseDetail(exercise.id)),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surfaceBase,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.outlineVariant),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.surfaceHigh,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.outlineVariant),
              ),
              child: const Icon(Icons.fitness_center, size: 20, color: AppColors.textSecondary),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(exercise.name, style: AppTypography.body(size: 14, weight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(exercise.muscleSummary, style: AppTypography.body(size: 12, color: AppColors.textMuted)),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (exercise.supportsCamera && exercise.cameraView != null)
                  BadgePill(exercise.cameraView!.toUpperCase(), color: AppColors.accentGreen)
                else if (hasPr)
                  const BadgePill('PR', color: AppColors.accentAmber),
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < _difficultyLevels.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(left: 2),
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: i < filledDots ? AppColors.accentGreen : AppColors.outline,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}
