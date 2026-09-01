import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/network/api_exception.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/exercise.dart';
import '../domain/program.dart';
import 'active_program_controller.dart';
import 'programs_providers.dart';
import 'widgets/muscle_tag_chip.dart';
import 'widgets/no_active_program_view.dart';

class DayEditorScreen extends ConsumerWidget {
  const DayEditorScreen({super.key, required this.dayId});

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
      appBar: AppBar(
        title: Text((day?.label ?? 'DAY').toUpperCase()),
        actions: [
          if (day != null)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _showRenameDialog(context, ref, day),
            ),
        ],
      ),
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
            return _DayEditorContent(day: day);
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: FormaEmptyState(
                icon: Icons.error_outline,
                title: 'Something went wrong.',
                message: error is ApiException ? error.message : 'Could not load this day.',
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

void _showRenameDialog(BuildContext context, WidgetRef ref, ProgramDay day) {
  final controller = TextEditingController(text: day.label);
  showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Rename day'),
      content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: 'NAME')),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
        TextButton(
          onPressed: () async {
            final label = controller.text.trim();
            Navigator.of(dialogContext).pop();
            if (label.isEmpty || label == day.label) return;
            try {
              await ref.read(programsRepositoryProvider).updateDay(day.id, {'label': label});
              await ref.read(activeProgramControllerProvider.notifier).refresh();
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(e is ApiException ? e.message : 'Could not rename this day.')),
                );
              }
            }
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

// The exercise library's own muscle vocabulary — matches `_muscleAbbreviations`
// in `plan_overview_screen.dart` minus the delt/trap split that chip doesn't
// need here.
const _muscleOptions = [
  'chest',
  'back',
  'shoulders',
  'biceps',
  'triceps',
  'quads',
  'hamstrings',
  'glutes',
  'calves',
  'core',
  'forearms',
  'lats',
];

void _showAddMuscleTagSheet(BuildContext context, WidgetRef ref, ProgramDay day) {
  final available = _muscleOptions.where((m) => !day.muscleTags.contains(m)).toList();
  showModalBottomSheet(
    context: context,
    builder: (sheetContext) => Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ADD MUSCLE TAG', style: AppTypography.display(size: 18)),
          const SizedBox(height: AppSpacing.md),
          if (available.isEmpty)
            Text('Every muscle tag is already on this day.', style: AppTypography.body(color: AppColors.textMuted))
          else
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final muscle in available)
                  MuscleTagChip(
                    titleCaseMuscle(muscle),
                    onTap: () async {
                      Navigator.of(sheetContext).pop();
                      try {
                        await ref.read(programsRepositoryProvider).updateDay(day.id, {
                          'muscle_tags': [...day.muscleTags, muscle],
                        });
                        await ref.read(activeProgramControllerProvider.notifier).refresh();
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(e is ApiException ? e.message : 'Could not add that tag.')),
                          );
                        }
                      }
                    },
                  ),
              ],
            ),
        ],
      ),
    ),
  );
}

class _DayEditorContent extends ConsumerStatefulWidget {
  const _DayEditorContent({required this.day});

  final ProgramDay day;

  @override
  ConsumerState<_DayEditorContent> createState() => _DayEditorContentState();
}

class _DayEditorContentState extends ConsumerState<_DayEditorContent> {
  late List<ProgramExercise> _exercises;
  bool _aiFilling = false;

  Future<void> _fillWithAi() async {
    setState(() => _aiFilling = true);
    try {
      await ref.read(programsRepositoryProvider).fillDay(widget.day.id);
      await ref.read(activeProgramControllerProvider.notifier).refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e is ApiException ? e.message : 'Could not fill this day.')),
        );
      }
    } finally {
      if (mounted) setState(() => _aiFilling = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _exercises = List.of(widget.day.exercises)..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
  }

  @override
  void didUpdateWidget(covariant _DayEditorContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.day.exercises, widget.day.exercises)) {
      _exercises = List.of(widget.day.exercises)..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    }
  }

  Future<void> _persistReorder(List<ProgramExercise> reordered) async {
    final repository = ref.read(programsRepositoryProvider);
    try {
      for (var i = 0; i < reordered.length; i++) {
        if (reordered[i].orderIndex != i) {
          await repository.updateProgramExercise(reordered[i].id, {'order_index': i});
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e is ApiException ? e.message : 'Could not reorder exercises.')),
        );
      }
    } finally {
      await ref.read(activeProgramControllerProvider.notifier).refresh();
    }
  }

  void _openEditSheet(ProgramExercise exercise) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EditExerciseSheet(exercise: exercise),
    );
  }

  void _openAddExerciseSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddExerciseSheet(
        dayId: widget.day.id,
        nextOrderIndex: _exercises.length,
        dayMuscleTags: widget.day.muscleTags,
      ),
    );
  }

  Future<void> _removeMuscleTag(String muscle) async {
    final updated = List<String>.of(widget.day.muscleTags)..remove(muscle);
    try {
      await ref.read(programsRepositoryProvider).updateDay(widget.day.id, {'muscle_tags': updated});
      await ref.read(activeProgramControllerProvider.notifier).refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : 'Could not update tags.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final day = widget.day;
    final totalSets = _exercises.fold<int>(0, (sum, e) => sum + e.sets);
    final totalMinutes = day.estimatedMinutes ?? (totalSets * 2 + 15);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ...day.muscleTags.map(
                    (m) => _RemovableMuscleTagChip(label: titleCaseMuscle(m), onRemove: () => _removeMuscleTag(m)),
                  ),
                  MuscleTagChip('+ ADD', onTap: () => _showAddMuscleTagSheet(context, ref, widget.day)),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text('$totalMinutes min estimated', style: AppTypography.body(size: 13, color: AppColors.accentBlue)),
            ],
          ),
        ),
        Expanded(
          child: _exercises.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: FormaEmptyState(
                      icon: Icons.fitness_center,
                      title: 'No exercises yet.',
                      message: 'Add your first exercise to this day.',
                    ),
                  ),
                )
              : ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xl),
                  itemCount: _exercises.length,
                  onReorder: (oldIndex, newIndex) {
                    setState(() {
                      if (oldIndex < newIndex) newIndex -= 1;
                      final item = _exercises.removeAt(oldIndex);
                      _exercises.insert(newIndex, item);
                    });
                    _persistReorder(_exercises);
                  },
                  itemBuilder: (context, index) {
                    final exercise = _exercises[index];
                    final previousGroup = index > 0 ? _exercises[index - 1].supersetGroup : null;
                    final nextGroup = index < _exercises.length - 1 ? _exercises[index + 1].supersetGroup : null;
                    final inSuperset = exercise.supersetGroup != null;
                    final startsSupersetLabel = inSuperset && exercise.supersetGroup != previousGroup;
                    final isLastInGroup = inSuperset && exercise.supersetGroup != nextGroup;
                    final content = Padding(
                      padding: EdgeInsets.only(left: inSuperset ? 12 : 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (startsSupersetLabel)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                'SUPERSET',
                                style: AppTypography.body(size: 10, weight: FontWeight.w700, color: AppColors.accentBlue).copyWith(letterSpacing: 1.0),
                              ),
                            ),
                          _ExerciseRow(exercise: exercise, onTap: () => _openEditSheet(exercise)),
                        ],
                      ),
                    );
                    return Padding(
                      key: ValueKey(exercise.id),
                      // Grouped rows sit close together (a continuous divider bar reads as one
                      // bracket down the group) — only the last member gets the normal gap.
                      padding: EdgeInsets.only(bottom: inSuperset && !isLastInGroup ? AppSpacing.xs : AppSpacing.sm),
                      child: inSuperset
                          ? Stack(
                              children: [
                                Positioned(
                                  left: 0,
                                  top: 0,
                                  bottom: 0,
                                  child: Container(
                                    width: 2,
                                    decoration: BoxDecoration(color: AppColors.accentBlue, borderRadius: BorderRadius.circular(2)),
                                  ),
                                ),
                                content,
                              ],
                            )
                          : content,
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.md),
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('ADD EXERCISE'),
                  onPressed: _openAddExerciseSheet,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextButton(
                onPressed: _aiFilling ? null : _fillWithAi,
                child: _aiFilling
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('✨ Let AI fill this day'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ExerciseRow extends StatelessWidget {
  const _ExerciseRow({required this.exercise, required this.onTap});

  final ProgramExercise exercise;
  final VoidCallback onTap;

  String? _targetLabel() {
    final value = exercise.targetValue;
    if (value == null) return null;
    final formatted = value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
    switch (exercise.loadType) {
      case 'percent_1rm':
        return '@ $formatted% 1RM';
      case 'rpe':
        return '@ RPE $formatted';
      default:
        return '@ ${formatted}kg';
    }
  }

  @override
  Widget build(BuildContext context) {
    final targetLabel = _targetLabel();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surfaceBase,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.outlineVariant),
          ),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
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
                  if (exercise.exercise.supportsCamera)
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                        width: 16,
                        height: 16,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.accentBlue,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.surfaceBase, width: 2),
                        ),
                        child: const Icon(Icons.videocam, size: 9, color: AppColors.accentBlueDark),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: AppSpacing.sm),
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
              const SizedBox(width: AppSpacing.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${exercise.sets} x ${exercise.repRangeLabel}', style: AppTypography.mono(size: 13)),
                  if (targetLabel != null) Text(targetLabel, style: AppTypography.mono(size: 12, color: AppColors.textSecondary)),
                ],
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, color: AppColors.textMuted, size: 20),
              const Icon(Icons.drag_handle, color: AppColors.textMuted, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

/// A [MuscleTagChip] visual with a trailing remove affordance — the day's own
/// muscle-tag chips are removable, unlike the shared chip's read-only usages.
class _RemovableMuscleTagChip extends StatelessWidget {
  const _RemovableMuscleTagChip({required this.label, required this.onRemove});

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: AppSpacing.sm, right: 6, top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: AppTypography.body(size: 12, weight: FontWeight.w600, color: AppColors.textSecondary)),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(Icons.close, size: 12, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _EditExerciseSheet extends ConsumerStatefulWidget {
  const _EditExerciseSheet({required this.exercise});

  final ProgramExercise exercise;

  @override
  ConsumerState<_EditExerciseSheet> createState() => _EditExerciseSheetState();
}

class _EditExerciseSheetState extends ConsumerState<_EditExerciseSheet> {
  late int _sets;
  late RangeValues _repRange;
  late final TextEditingController _targetController;
  double? _rpeValue;
  late final TextEditingController _tempoController;
  late final TextEditingController _notesController;
  late String _loadType;
  late bool _coachWithCamera;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.exercise;
    _sets = e.sets.clamp(1, 12);
    // Clamp defensively — the slider's track only covers 1-30 reps, but the
    // persisted value has no such bound enforced server-side.
    _repRange = RangeValues(
      e.repRangeLow.toDouble().clamp(1, 30),
      e.repRangeHigh.toDouble().clamp(1, 30),
    );
    _targetController = TextEditingController(text: e.targetValue != null ? _formatNum(e.targetValue!) : '');
    _rpeValue = e.loadType == 'rpe' ? e.targetValue : null;
    _tempoController = TextEditingController(text: e.tempo ?? '');
    _notesController = TextEditingController(text: e.notes ?? '');
    _loadType = e.loadType;
    _coachWithCamera = e.coachWithCamera;
  }

  String _formatNum(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';

  void _adjustTarget(double delta) {
    final current = double.tryParse(_targetController.text.trim()) ?? 0;
    final next = (current + delta).clamp(0, 999).toDouble();
    setState(() => _targetController.text = _formatNum(next));
  }

  @override
  void dispose() {
    _targetController.dispose();
    _tempoController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final targetValue = _loadType == 'rpe'
        ? _rpeValue
        : (_targetController.text.trim().isEmpty ? null : double.tryParse(_targetController.text.trim()));
    final patch = <String, dynamic>{
      'sets': _sets,
      'rep_range_low': _repRange.start.round(),
      'rep_range_high': _repRange.end.round(),
      'load_type': _loadType,
      'target_value': targetValue,
      'tempo': _tempoController.text.trim().isEmpty ? null : _tempoController.text.trim(),
      'notes': _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      'coach_with_camera': _coachWithCamera,
    };
    try {
      await ref.read(programsRepositoryProvider).updateProgramExercise(widget.exercise.id, patch);
      await ref.read(activeProgramControllerProvider.notifier).refresh();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is ApiException ? e.message : 'Could not save changes.')));
    }
  }

  Future<void> _remove() async {
    setState(() => _saving = true);
    try {
      await ref.read(programsRepositoryProvider).removeProgramExercise(widget.exercise.id);
      await ref.read(activeProgramControllerProvider.notifier).refresh();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is ApiException ? e.message : 'Could not remove exercise.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.exercise.exercise.name, style: AppTypography.display(size: 20)),
            const SizedBox(height: 4),
            Text(widget.exercise.exercise.muscleSummary, style: AppTypography.body(size: 13, color: AppColors.textSecondary)),
            const SizedBox(height: AppSpacing.lg),
            const SectionLabel('SETS'),
            const SizedBox(height: AppSpacing.sm),
            _Stepper(value: _sets, min: 1, max: 12, onChanged: (v) => setState(() => _sets = v)),
            const SizedBox(height: AppSpacing.md),
            SectionLabel('REP RANGE · ${_repRange.start.round()}-${_repRange.end.round()}'),
            RangeSlider(
              values: _repRange,
              min: 1,
              max: 30,
              divisions: 29,
              labels: RangeLabels('${_repRange.start.round()}', '${_repRange.end.round()}'),
              onChanged: (v) => setState(() => _repRange = v),
            ),
            const SizedBox(height: AppSpacing.sm),
            const SectionLabel('LOAD TYPE'),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                _LoadTypeChip(label: 'WEIGHT', value: 'weight', groupValue: _loadType, onSelect: (v) => setState(() => _loadType = v)),
                _LoadTypeChip(label: '% 1RM', value: 'percent_1rm', groupValue: _loadType, onSelect: (v) => setState(() => _loadType = v)),
                _LoadTypeChip(label: 'RPE', value: 'rpe', groupValue: _loadType, onSelect: (v) => setState(() => _loadType = v)),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            if (_loadType == 'rpe') ...[
              const SectionLabel('TARGET RPE'),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (var r = 6.0; r <= 10.0; r += 0.5)
                    _RpeChip(value: r, selected: _rpeValue == r, onSelect: () => setState(() => _rpeValue = r)),
                ],
              ),
            ] else ...[
              SectionLabel(_loadType == 'percent_1rm' ? '% OF 1RM' : 'TARGET WEIGHT'),
              const SizedBox(height: AppSpacing.sm),
              _NumberField(
                label: _loadType == 'percent_1rm' ? '% OF 1RM' : 'WEIGHT (KG)',
                controller: _targetController,
                allowDecimal: true,
              ),
              if (_loadType == 'weight') ...[
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  children: [
                    _QuickAdjustChip(label: '−2.5', onTap: () => _adjustTarget(-2.5)),
                    _QuickAdjustChip(label: '+2.5', onTap: () => _adjustTarget(2.5)),
                    _QuickAdjustChip(label: '+5', onTap: () => _adjustTarget(5)),
                  ],
                ),
              ],
            ],
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _tempoController,
              decoration: const InputDecoration(labelText: 'TEMPO', hintText: 'e.g. 3-1-1-0 (ecc-pause-con-hold)'),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(controller: _notesController, maxLines: 2, decoration: const InputDecoration(labelText: 'NOTES')),
            if (widget.exercise.exercise.supportsCamera) ...[
              const SizedBox(height: AppSpacing.md),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Coach with camera'),
                subtitle: widget.exercise.exercise.cameraView != null
                    ? Text(
                        '${titleCaseMuscle(widget.exercise.exercise.cameraView!)} view',
                        style: AppTypography.body(size: 12, color: AppColors.textMuted),
                      )
                    : null,
                value: _coachWithCamera,
                onChanged: (v) => setState(() => _coachWithCamera = v),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('SAVE'),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _saving ? null : _remove,
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.error, side: const BorderSide(color: AppColors.error)),
                child: const Text('REMOVE FROM DAY'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.value, required this.min, required this.max, required this.onChanged});

  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StepperButton(icon: Icons.remove, onTap: value > min ? () => onChanged(value - 1) : null),
        Expanded(child: Center(child: Text('$value', style: AppTypography.mono(size: 20, weight: FontWeight.w600)))),
        _StepperButton(icon: Icons.add, onTap: value < max ? () => onChanged(value + 1) : null),
      ],
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.field),
        side: const BorderSide(color: AppColors.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.field),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Icon(icon, size: 20, color: onTap == null ? AppColors.textMuted : AppColors.textPrimary),
        ),
      ),
    );
  }
}

class _RpeChip extends StatelessWidget {
  const _RpeChip({required this.value, required this.selected, required this.onSelect});

  final double value;
  final bool selected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final label = value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
    return ChoiceChip(label: Text(label), selected: selected, onSelected: (_) => onSelect());
  }
}

class _QuickAdjustChip extends StatelessWidget {
  const _QuickAdjustChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6), minimumSize: Size.zero),
      child: Text(label, style: AppTypography.mono(size: 13)),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({required this.label, required this.controller, this.allowDecimal = false});

  final String label;
  final TextEditingController controller;
  final bool allowDecimal;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.numberWithOptions(decimal: allowDecimal),
      decoration: InputDecoration(labelText: label),
    );
  }
}

class _LoadTypeChip extends StatelessWidget {
  const _LoadTypeChip({required this.label, required this.value, required this.groupValue, required this.onSelect});

  final String label;
  final String value;
  final String groupValue;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: value == groupValue,
      onSelected: (_) => onSelect(value),
    );
  }
}

class _AddExerciseSheet extends ConsumerStatefulWidget {
  const _AddExerciseSheet({required this.dayId, required this.nextOrderIndex, required this.dayMuscleTags});

  final String dayId;
  final int nextOrderIndex;
  final List<String> dayMuscleTags;

  @override
  ConsumerState<_AddExerciseSheet> createState() => _AddExerciseSheetState();
}

class _AddExerciseSheetState extends ConsumerState<_AddExerciseSheet> {
  final _searchController = TextEditingController();
  List<Exercise> _results = const [];
  final Set<String> _selectedIds = {};
  String? _muscleFilter;
  bool _myEquipmentOnly = false;
  bool _cameraOnly = false;
  bool _loading = false;
  bool _adding = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  int get _activeFilterCount => (_myEquipmentOnly ? 1 : 0) + (_cameraOnly ? 1 : 0);

  Future<void> _search(String query) async {
    setState(() => _loading = true);
    try {
      final results = await ref.read(programsRepositoryProvider).listExercises(search: query.isEmpty ? null : query);
      if (!mounted) return;
      setState(() {
        _results = results;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is ApiException ? e.message : 'Could not load exercises.';
      });
    }
  }

  void _toggleSelected(String exerciseId) {
    setState(() {
      if (!_selectedIds.remove(exerciseId)) _selectedIds.add(exerciseId);
    });
  }

  Future<void> _addSelected(List<Exercise> selected) async {
    setState(() => _adding = true);
    final repository = ref.read(programsRepositoryProvider);
    try {
      for (var i = 0; i < selected.length; i++) {
        await repository.addExerciseToDay(widget.dayId, exerciseId: selected[i].id, orderIndex: widget.nextOrderIndex + i);
      }
      await ref.read(activeProgramControllerProvider.notifier).refresh();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _adding = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is ApiException ? e.message : 'Could not add exercises.')));
    }
  }

  void _openFilterSheet() {
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
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userEquipment = ref.watch(authControllerProvider).valueOrNull?.equipment ?? const [];

    var filtered = _results;
    if (_muscleFilter != null) {
      filtered = filtered.where((e) => e.primaryMuscles.contains(_muscleFilter)).toList();
    }
    if (_myEquipmentOnly) {
      filtered = filtered.where((e) => e.equipment.every(userEquipment.contains)).toList();
    }
    if (_cameraOnly) {
      filtered = filtered.where((e) => e.supportsCamera).toList();
    }
    // "Good fit" is a real signal (this day's own muscle tags vs. the
    // exercise's primary muscles) — with no tags on the day there is nothing
    // honest to recommend, so the section simply doesn't appear.
    final recommended = widget.dayMuscleTags.isEmpty
        ? const <Exercise>[]
        : filtered.where((e) => e.primaryMuscles.any(widget.dayMuscleTags.contains)).toList();
    final recommendedIds = recommended.map((e) => e.id).toSet();
    final rest = filtered.where((e) => !recommendedIds.contains(e.id)).toList();
    final selected = _results.where((e) => _selectedIds.contains(e.id)).toList();

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('ADD EXERCISE', style: AppTypography.display(size: 18)),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
              ],
            ),
            TextField(
              controller: _searchController,
              autofocus: true,
              onSubmitted: _search,
              decoration: InputDecoration(
                hintText: 'Search exercises',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: () => _search(_searchController.text)),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _FilterButtonChip(activeCount: _activeFilterCount, onTap: _openFilterSheet),
                  const SizedBox(width: 8),
                  ...widget.dayMuscleTags.map(
                    (m) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: MuscleTagChip(
                        titleCaseMuscle(m),
                        selected: _muscleFilter == m,
                        onTap: () => setState(() => _muscleFilter = _muscleFilter == m ? null : m),
                      ),
                    ),
                  ),
                  MuscleTagChip('My equipment', selected: _myEquipmentOnly, onTap: () => setState(() => _myEquipmentOnly = !_myEquipmentOnly)),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(child: _buildResults(recommended, rest)),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: (_selectedIds.isEmpty || _adding) ? null : () => _addSelected(selected),
                child: _adding
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(
                        _selectedIds.isEmpty
                            ? 'SELECT EXERCISES TO ADD'
                            : 'ADD ${_selectedIds.length} EXERCISE${_selectedIds.length == 1 ? '' : 'S'}',
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(List<Exercise> recommended, List<Exercise> rest) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!, style: AppTypography.body(color: AppColors.error)));
    if (recommended.isEmpty && rest.isEmpty) {
      return Center(child: Text('No exercises match that.', style: AppTypography.body(color: AppColors.textMuted)));
    }
    return ListView(
      children: [
        if (recommended.isNotEmpty) ...[
          const SectionLabel('RECOMMENDED FOR THIS DAY'),
          const SizedBox(height: AppSpacing.sm),
          ...recommended.map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: _ExercisePickRow(exercise: e, goodFit: true, selected: _selectedIds.contains(e.id), onTap: () => _toggleSelected(e.id)),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (rest.isNotEmpty) ...[
          SectionLabel('ALL EXERCISES · ${rest.length}'),
          const SizedBox(height: AppSpacing.sm),
          ...rest.map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: _ExercisePickRow(exercise: e, goodFit: false, selected: _selectedIds.contains(e.id), onTap: () => _toggleSelected(e.id)),
            ),
          ),
        ],
      ],
    );
  }
}

class _FilterButtonChip extends StatelessWidget {
  const _FilterButtonChip({required this.activeCount, required this.onTap});

  final int activeCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(AppRadius.chip),
          border: Border.all(color: AppColors.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.tune, size: 14, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Text('FILTERS', style: AppTypography.body(size: 12, weight: FontWeight.w600, color: AppColors.textSecondary)),
            if (activeCount > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.all(3),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                decoration: const BoxDecoration(color: AppColors.accentBlue, shape: BoxShape.circle),
                child: Text(
                  '$activeCount',
                  textAlign: TextAlign.center,
                  style: AppTypography.body(size: 10, weight: FontWeight.w700, color: AppColors.accentBlueDark),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ExercisePickRow extends StatelessWidget {
  const _ExercisePickRow({required this.exercise, required this.goodFit, required this.selected, required this.onTap});

  final Exercise exercise;
  final bool goodFit;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: selected ? AppColors.accentBlue : Colors.transparent),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.surfaceHigh, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.outlineVariant)),
                child: const Icon(Icons.fitness_center, size: 16, color: AppColors.textSecondary),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            exercise.name,
                            style: AppTypography.body(size: 14, weight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (goodFit) ...[const SizedBox(width: 6), const BadgePill('GOOD FIT', color: AppColors.accentBlue, outlined: true)],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(exercise.muscleSummary, style: AppTypography.body(size: 12, color: AppColors.textMuted)),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? AppColors.accentBlue : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(color: selected ? AppColors.accentBlue : AppColors.textMuted),
                ),
                child: selected ? const Icon(Icons.check, size: 14, color: AppColors.accentBlueDark) : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
