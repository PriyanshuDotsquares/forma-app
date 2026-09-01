import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/app_router.dart';
import '../../workout/presentation/workout_providers.dart';
import '../domain/program.dart';
import 'active_program_controller.dart';
import 'widgets/muscle_tag_chip.dart';
import 'widgets/no_active_program_view.dart';

class SessionPreviewScreen extends ConsumerWidget {
  const SessionPreviewScreen({super.key, required this.dayId});

  final String dayId;

  ProgramDay? _findDay(Program? program) {
    if (program == null) return null;
    for (final day in program.days) {
      if (day.id == dayId) return day;
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(activeProgramControllerProvider);
    final day = _findDay(state.valueOrNull);

    return Scaffold(
      appBar: AppBar(title: const Text('SESSION PREVIEW')),
      body: SafeArea(
        child: state.when(
          data: (program) {
            if (program == null) {
              return NoActiveProgramView(
                loading: state.isLoading,
                onGenerate: () => ref.read(activeProgramControllerProvider.notifier).regenerate(),
              );
            }
            if (day == null) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: FormaEmptyState(
                    icon: Icons.help_outline,
                    title: 'Day not found.',
                    message: 'This day may have been removed.',
                  ),
                ),
              );
            }
            return _SessionPreviewContent(day: day);
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: FormaEmptyState(
                icon: Icons.error_outline,
                title: 'Something went wrong.',
                message: error is ApiException ? error.message : 'Could not load this session.',
                primaryLabel: 'RETRY',
                onPrimary: () => ref.invalidate(activeProgramControllerProvider),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SessionPreviewContent extends ConsumerStatefulWidget {
  const _SessionPreviewContent({required this.day});

  final ProgramDay day;

  @override
  ConsumerState<_SessionPreviewContent> createState() => _SessionPreviewContentState();
}

class _SessionPreviewContentState extends ConsumerState<_SessionPreviewContent> {
  int? _selectedMinutes; // null = "as long as it takes"
  late Map<String, bool> _cameraToggles;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    _selectedMinutes = widget.day.estimatedMinutes;
    _cameraToggles = {for (final e in widget.day.exercises) e.id: e.coachWithCamera};
  }

  Future<void> _startWorkout() async {
    setState(() => _starting = true);
    try {
      final session = await ref.read(workoutRepositoryProvider).startSession(programDayId: widget.day.id, label: widget.day.label);
      if (mounted) context.go(AppRoutes.workoutActive(session.id));
    } catch (e) {
      if (!mounted) return;
      setState(() => _starting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : 'Could not start workout. Please try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final day = widget.day;
    final equipment = <String>{};
    for (final e in day.exercises) {
      equipment.addAll(e.exercise.equipment);
    }
    final cameraEligible = day.exercises.where((e) => e.exercise.supportsCamera).toList();

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Text(day.label, style: AppTypography.display(size: 30)),
              const SizedBox(height: AppSpacing.sm),
              Wrap(spacing: 6, runSpacing: 6, children: day.muscleTags.map((m) => MuscleTagChip(titleCaseMuscle(m))).toList()),
              const SizedBox(height: AppSpacing.xl),
              const SectionLabel('TIME AVAILABLE'),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  MuscleTagChip('30 MIN', selected: _selectedMinutes == 30, onTap: () => setState(() => _selectedMinutes = 30)),
                  MuscleTagChip('45 MIN', selected: _selectedMinutes == 45, onTap: () => setState(() => _selectedMinutes = 45)),
                  MuscleTagChip('60 MIN', selected: _selectedMinutes == 60, onTap: () => setState(() => _selectedMinutes = 60)),
                  MuscleTagChip('AS LONG AS IT TAKES', selected: _selectedMinutes == null, onTap: () => setState(() => _selectedMinutes = null)),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              if (cameraEligible.isNotEmpty) ...[
                const SectionLabel('COACH WITH CAMERA'),
                const SizedBox(height: AppSpacing.sm),
                ...day.exercises.map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            e.exercise.name,
                            style: AppTypography.body(size: 14, color: e.exercise.supportsCamera ? AppColors.textPrimary : AppColors.textMuted),
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            (_cameraToggles[e.id] ?? false) ? Icons.videocam : Icons.videocam_off_outlined,
                            color: !e.exercise.supportsCamera
                                ? AppColors.textMuted
                                : ((_cameraToggles[e.id] ?? false) ? AppColors.accentBlue : AppColors.textSecondary),
                          ),
                          onPressed: e.exercise.supportsCamera
                              ? () => setState(() => _cameraToggles[e.id] = !(_cameraToggles[e.id] ?? false))
                              : null,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
              const SectionLabel("TODAY'S WORK"),
              const SizedBox(height: AppSpacing.sm),
              ...day.exercises.map((e) => Padding(padding: const EdgeInsets.only(bottom: AppSpacing.sm), child: _WorkRow(exercise: e))),
              if (equipment.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                const SectionLabel('EQUIPMENT NEEDED'),
                const SizedBox(height: AppSpacing.sm),
                Wrap(spacing: 6, runSpacing: 6, children: equipment.map((eq) => MuscleTagChip(titleCaseMuscle(eq))).toList()),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _starting ? null : _startWorkout,
              child: _starting
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('START WORKOUT →'),
            ),
          ),
        ),
      ],
    );
  }
}

class _WorkRow extends StatelessWidget {
  const _WorkRow({required this.exercise});

  final ProgramExercise exercise;

  String? _targetLabel() {
    final value = exercise.targetValue;
    if (value == null) return null;
    final formatted = value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
    switch (exercise.loadType) {
      case 'percent_1rm':
        return '$formatted% 1RM';
      case 'rpe':
        return 'RPE $formatted';
      default:
        return '${formatted}kg';
    }
  }

  @override
  Widget build(BuildContext context) {
    final targetLabel = _targetLabel();
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceBase,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(exercise.exercise.name, style: AppTypography.body(size: 14, weight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(exercise.exercise.muscleSummary, style: AppTypography.body(size: 12, color: AppColors.textMuted)),
              ],
            ),
          ),
          Text(
            targetLabel != null ? '${exercise.sets} x ${exercise.repRangeLabel} @ $targetLabel' : '${exercise.sets} x ${exercise.repRangeLabel}',
            style: AppTypography.mono(size: 13),
          ),
        ],
      ),
    );
  }
}
