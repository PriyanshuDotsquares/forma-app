import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/app_router.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/workout_session.dart';
import 'workout_providers.dart';

double _volumeKg(WorkoutSession s) => s.sets.fold(0.0, (sum, set) => sum + (set.actualWeightKg ?? 0) * (set.actualReps ?? 0));

int _totalReps(WorkoutSession s) => s.sets.fold(0, (sum, set) => sum + (set.actualReps ?? 0));

double? _avgForm(WorkoutSession s) {
  final scored = s.sets.where((set) => set.formScore != null).toList();
  if (scored.isEmpty) return s.avgFormScore;
  return scored.map((set) => set.formScore!).reduce((a, b) => a + b) / scored.length;
}

String _fmtWeight(double v) => v == v.truncateToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

String _fmtElapsed(int? totalSeconds) {
  if (totalSeconds == null) return '—';
  final h = totalSeconds ~/ 3600;
  final m = (totalSeconds % 3600) ~/ 60;
  final s = totalSeconds % 60;
  if (h > 0) return '${h}h ${m}m';
  return '${m}m ${s.toString().padLeft(2, '0')}s';
}

/// XP needed to reach the *next* level, given a total [xp] — a simple,
/// intentionally coarse curve: level N requires N*100 total xp, so the
/// next threshold above any amount is `(xp ~/ 100 + 1) * 100`. FORMA has no
/// real leveling curve defined yet; this keeps the progress bar's math
/// simple and consistent rather than guessing at a design that doesn't
/// exist.
int _nextLevelXp(int xp) => ((xp ~/ 100) + 1) * 100;

int _levelFloorXp(int xp) => (xp ~/ 100) * 100;

/// Post-workout summary — and, when opened later from history on an
/// already-finished session, a read-only-but-still-editable view of the
/// same data (RPE/mood/notes stay editable; saving them just calls
/// `finishSession` again, which is idempotent enough for this purpose).
class WorkoutSummaryScreen extends ConsumerStatefulWidget {
  const WorkoutSummaryScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<WorkoutSummaryScreen> createState() => _WorkoutSummaryScreenState();
}

class _WorkoutSummaryScreenState extends ConsumerState<WorkoutSummaryScreen> {
  final _notesController = TextEditingController();
  bool _initialized = false;
  bool _saving = false;
  double? _rpe;
  int? _mood;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  void _initFrom(WorkoutSession session) {
    _initialized = true;
    _rpe = session.rpe;
    _mood = session.mood;
    _notesController.text = session.notes ?? '';
  }

  Future<void> _submit(WorkoutSession session) async {
    setState(() => _saving = true);
    try {
      await ref
          .read(workoutRepositoryProvider)
          .finishSession(
            widget.sessionId,
            durationS: session.durationS,
            calories: session.calories,
            rpe: _rpe,
            mood: _mood,
            notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
          );
      ref.invalidate(sessionProvider(widget.sessionId));
      ref.invalidate(sessionListProvider);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessionAsync = ref.watch(sessionProvider(widget.sessionId));

    return Scaffold(
      body: sessionAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: FormaEmptyState(
                icon: Icons.error_outline,
                title: "That didn't work.",
                message: error is ApiException ? error.message : 'Could not load this workout.',
                primaryLabel: 'RETRY',
                onPrimary: () => ref.invalidate(sessionProvider(widget.sessionId)),
              ),
            ),
          ),
        ),
        data: (session) {
          if (!_initialized) _initFrom(session);
          return _Body(
            session: session,
            rpe: _rpe,
            mood: _mood,
            notesController: _notesController,
            saving: _saving,
            onRpeChanged: (v) {
              setState(() => _rpe = v);
              _submit(session);
            },
            onMoodChanged: (v) {
              setState(() => _mood = v);
              _submit(session);
            },
            onNotesSubmitted: () => _submit(session),
          );
        },
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.session,
    required this.rpe,
    required this.mood,
    required this.notesController,
    required this.saving,
    required this.onRpeChanged,
    required this.onMoodChanged,
    required this.onNotesSubmitted,
  });

  final WorkoutSession session;
  final double? rpe;
  final int? mood;
  final TextEditingController notesController;
  final bool saving;
  final ValueChanged<double> onRpeChanged;
  final ValueChanged<int> onMoodChanged;
  final VoidCallback onNotesSubmitted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final volume = _volumeKg(session);
    final avgForm = _avgForm(session);
    final prSets = session.sets.where((s) => s.isPr).toList();

    // A rough "vs your last similar workout" comparison, when one exists in
    // the already-fetched recent-sessions list — omitted entirely (StatTile
    // deltas are optional) when there's nothing finished to compare against.
    final recent = ref.watch(sessionListProvider).valueOrNull ?? const [];
    WorkoutSession? baseline;
    for (final other in recent) {
      if (other.id != session.id && other.isFinished && other.label == session.label) {
        baseline = other;
        break;
      }
    }
    final volumeDelta = baseline == null || _volumeKg(baseline) == 0
        ? null
        : ((volume - _volumeKg(baseline)) / _volumeKg(baseline) * 100);
    final baselineAvgForm = baseline == null ? null : _avgForm(baseline);
    final formDelta = (baseline == null || avgForm == null || baselineAvgForm == null) ? null : (avgForm - baselineAvgForm);

    final user = ref.watch(authControllerProvider).valueOrNull;
    final xp = user?.xp ?? 0;
    final levelFloor = _levelFloorXp(xp);
    final levelCeiling = _nextLevelXp(xp);
    final levelProgress = levelCeiling == levelFloor ? 0.0 : (xp - levelFloor) / (levelCeiling - levelFloor);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Text(
            '${session.label.toUpperCase()} — DONE.',
            style: AppTypography.display(size: 26),
          ),
          const SizedBox(height: 4),
          Text(
            DateFormat('MMM d, h:mm a').format(session.startedAt),
            style: AppTypography.body(size: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),
          _SetQualityStrip(sets: session.sets),
          const SizedBox(height: AppSpacing.xl),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: AppSpacing.sm,
            crossAxisSpacing: AppSpacing.sm,
            childAspectRatio: 1.7,
            children: [
              StatTile(label: 'Duration', value: _fmtElapsed(session.durationS)),
              StatTile(
                label: 'Volume',
                value: _fmtWeight(volume),
                unit: 'kg',
                delta: volumeDelta == null ? null : '${volumeDelta >= 0 ? '+' : ''}${volumeDelta.toStringAsFixed(0)}%',
                deltaPositive: (volumeDelta ?? 0) >= 0,
              ),
              StatTile(label: 'Sets', value: '${session.sets.length}'),
              StatTile(label: 'Reps', value: '${_totalReps(session)}'),
              StatTile(label: 'Calories', value: session.calories?.toString() ?? '—'),
              StatTile(
                label: 'Avg Form',
                value: avgForm == null ? '—' : avgForm.round().toString(),
                delta: formDelta == null ? null : '${formDelta >= 0 ? '+' : ''}${formDelta.toStringAsFixed(0)}',
                deltaPositive: (formDelta ?? 0) >= 0,
              ),
            ],
          ),
          if (prSets.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            _PrBanner(sets: prSets),
          ],
          const SizedBox(height: AppSpacing.xl),
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: () => context.go(AppRoutes.today), child: const Text('DONE')),
          ),
          const SizedBox(height: AppSpacing.sm),
          Center(
            child: TextButton(
              onPressed: () => context.push(AppRoutes.workoutFormReport(session.id)),
              child: const Text('SEE FORM REPORT'),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surfaceBase,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: AppColors.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const SectionLabel('LEVEL PROGRESS'),
                    Text('$xp XP', style: AppTypography.mono(size: 12, weight: FontWeight.w600, color: AppColors.textSecondary)),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: levelProgress.clamp(0.0, 1.0),
                    minHeight: 8,
                    backgroundColor: AppColors.surfaceHighest,
                    color: AppColors.accentBlue,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$xp / $levelCeiling XP to next level',
                  style: AppTypography.body(size: 11, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          const SectionLabel('EXERCISE BREAKDOWN'),
          const SizedBox(height: AppSpacing.sm),
          _ExerciseBreakdownList(sets: session.sets),
          const SizedBox(height: AppSpacing.xl),
          const SectionLabel('MUSCLES TRAINED'),
          const SizedBox(height: AppSpacing.sm),
          _MusclesTrainedDiagram(sets: session.sets),
          const SizedBox(height: AppSpacing.xl),
          const SectionLabel('HOW DID IT FEEL?'),
          const SizedBox(height: AppSpacing.sm),
          _RpeRow(value: rpe, onChanged: onRpeChanged),
          const SizedBox(height: AppSpacing.md),
          _MoodRow(value: mood, onChanged: onMoodChanged),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: notesController,
            minLines: 2,
            maxLines: 4,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(hintText: 'Notes about this session (optional)'),
            onSubmitted: (_) => onNotesSubmitted(),
            onEditingComplete: onNotesSubmitted,
          ),
          if (saving) ...[
            const SizedBox(height: AppSpacing.xs),
            Text('Saving…', style: AppTypography.body(size: 11, color: AppColors.textMuted)),
          ],
        ],
      ),
    );
  }
}

class _SetQualityStrip extends StatelessWidget {
  const _SetQualityStrip({required this.sets});
  final List<WorkoutSet> sets;

  Color _colorFor(int? score) {
    if (score == null) return AppColors.surfaceHighest;
    if (score >= 80) return AppColors.accentGreen;
    if (score >= 60) return AppColors.accentAmber;
    return AppColors.accentRed;
  }

  @override
  Widget build(BuildContext context) {
    if (sets.isEmpty) return const SizedBox.shrink();
    int? worstScore;
    for (final s in sets) {
      if (s.formScore != null && (worstScore == null || s.formScore! < worstScore)) worstScore = s.formScore;
    }
    return SizedBox(
      height: 36,
      child: Row(
        children: sets.map((set) {
          final isWorst = worstScore != null && set.formScore == worstScore;
          return Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              decoration: BoxDecoration(
                color: _colorFor(set.formScore),
                borderRadius: BorderRadius.circular(3),
                border: isWorst ? Border.all(color: AppColors.textPrimary, width: 1.5) : null,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _PrBanner extends StatelessWidget {
  const _PrBanner({required this.sets});
  final List<WorkoutSet> sets;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.accentRed.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.accentRed),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PERSONAL RECORD',
            style: AppTypography.body(size: 11, weight: FontWeight.w700, color: AppColors.accentRed).copyWith(letterSpacing: 1.2),
          ),
          const SizedBox(height: 6),
          for (final set in sets)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '${set.exercise.name} — ${_fmtWeight(set.actualWeightKg ?? 0)}kg × ${set.actualReps ?? 0}',
                style: AppTypography.body(size: 13, weight: FontWeight.w600),
              ),
            ),
        ],
      ),
    );
  }
}

class _ExerciseBreakdownList extends StatelessWidget {
  const _ExerciseBreakdownList({required this.sets});
  final List<WorkoutSet> sets;

  @override
  Widget build(BuildContext context) {
    final byExercise = <String, List<WorkoutSet>>{};
    final order = <String>[];
    for (final set in sets) {
      if (!byExercise.containsKey(set.exerciseId)) order.add(set.exerciseId);
      byExercise.putIfAbsent(set.exerciseId, () => []).add(set);
    }
    if (order.isEmpty) {
      return Text('No sets logged.', style: AppTypography.body(size: 13, color: AppColors.textSecondary));
    }

    return Column(
      children: order.map((id) {
        final exerciseSets = byExercise[id]!;
        final exercise = exerciseSets.first.exercise;
        final volume = exerciseSets.fold(0.0, (sum, s) => sum + (s.actualWeightKg ?? 0) * (s.actualReps ?? 0));
        final scored = exerciseSets.where((s) => s.formScore != null).toList();
        final avgForm = scored.isEmpty ? null : scored.map((s) => s.formScore!).reduce((a, b) => a + b) / scored.length;

        return Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
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
                    Text(exercise.name, style: AppTypography.body(size: 14, weight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      '${exerciseSets.length} sets · ${_fmtWeight(volume)}kg volume',
                      style: AppTypography.body(size: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              if (avgForm != null)
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: avgForm >= 80 ? AppColors.accentGreen : (avgForm >= 60 ? AppColors.accentAmber : AppColors.accentRed), width: 2),
                  ),
                  child: Text(avgForm.round().toString(), style: AppTypography.mono(size: 11, weight: FontWeight.w700)),
                ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

/// Roughly which body-diagram silhouette a muscle group lights up on, and
/// where — fractional (dx, dy) coordinates within that silhouette's
/// bounding box. This is a simplified, stylized diagram (a handful of dots
/// on two outlines), not anatomy — good enough to show "these areas got
/// worked" at a glance.
const Map<String, (double dx, double dy, bool front)> _muscleDiagramPoints = {
  'chest': (0.5, 0.26, true),
  'shoulders': (0.26, 0.2, true),
  'front_delts': (0.26, 0.2, true),
  'biceps': (0.22, 0.34, true),
  'forearms': (0.18, 0.48, true),
  'core': (0.5, 0.4, true),
  'quads': (0.4, 0.62, true),
  'calves': (0.42, 0.88, false),
  'back': (0.5, 0.3, false),
  'lats': (0.36, 0.32, false),
  'triceps': (0.78, 0.34, false),
  'hamstrings': (0.42, 0.66, false),
  'glutes': (0.5, 0.48, false),
};

class _MusclesTrainedDiagram extends StatelessWidget {
  const _MusclesTrainedDiagram({required this.sets});
  final List<WorkoutSet> sets;

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{};
    for (final set in sets) {
      for (final m in set.exercise.primaryMuscles) {
        counts[m] = (counts[m] ?? 0) + 1;
      }
      for (final m in set.exercise.secondaryMuscles) {
        counts[m] = (counts[m] ?? 0) + 1;
      }
    }

    return Row(
      children: [
        Expanded(child: _SilhouetteView(label: 'FRONT', front: true, counts: counts)),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: _SilhouetteView(label: 'BACK', front: false, counts: counts)),
      ],
    );
  }
}

class _SilhouetteView extends StatelessWidget {
  const _SilhouetteView({required this.label, required this.front, required this.counts});

  final String label;
  final bool front;
  final Map<String, int> counts;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AspectRatio(
          aspectRatio: 0.6,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(constraints.maxWidth, constraints.maxHeight);
              return Stack(
                children: [
                  CustomPaint(size: size, painter: const _SilhouetteOutlinePainter()),
                  for (final entry in _muscleDiagramPoints.entries)
                    if (entry.value.$3 == front)
                      Positioned(
                        left: entry.value.$1 * size.width - 6,
                        top: entry.value.$2 * size.height - 6,
                        child: _MuscleDot(active: (counts[entry.key] ?? 0) > 0),
                      ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: AppTypography.body(size: 10, weight: FontWeight.w700, color: AppColors.textMuted).copyWith(letterSpacing: 1.0)),
      ],
    );
  }
}

class _MuscleDot extends StatelessWidget {
  const _MuscleDot({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? AppColors.accentGreen : AppColors.surfaceHighest,
        border: Border.all(color: active ? AppColors.accentGreen : AppColors.outline),
      ),
    );
  }
}

class _SilhouetteOutlinePainter extends CustomPainter {
  const _SilhouetteOutlinePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.outline
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final centerX = size.width / 2;
    final headRadius = size.width * 0.16;
    final headCenterY = size.height * 0.12;
    final bodyTop = headCenterY + headRadius * 1.1;
    final bodyBottom = size.height * 0.94;
    final bodyWidth = size.width * 0.6;

    canvas.drawOval(Rect.fromCircle(center: Offset(centerX, headCenterY), radius: headRadius), paint);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(centerX - bodyWidth / 2, bodyTop, centerX + bodyWidth / 2, bodyBottom),
        Radius.circular(bodyWidth * 0.22),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _SilhouetteOutlinePainter oldDelegate) => false;
}

class _RpeRow extends StatelessWidget {
  const _RpeRow({required this.value, required this.onChanged});
  final double? value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('RPE'),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: List.generate(10, (i) {
            final rpe = i + 1;
            final selected = value?.round() == rpe;
            return GestureDetector(
              onTap: () => onChanged(rpe.toDouble()),
              child: Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? AppColors.accentBlue : AppColors.surfaceHigh,
                  shape: BoxShape.circle,
                  border: Border.all(color: selected ? AppColors.accentBlue : AppColors.outlineVariant),
                ),
                child: Text(
                  '$rpe',
                  style: AppTypography.mono(size: 13, weight: FontWeight.w600, color: selected ? AppColors.accentBlueDark : AppColors.textPrimary),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _MoodRow extends StatelessWidget {
  const _MoodRow({required this.value, required this.onChanged});
  final int? value;
  final ValueChanged<int> onChanged;

  static const _icons = [
    Icons.sentiment_very_dissatisfied,
    Icons.sentiment_dissatisfied,
    Icons.sentiment_neutral,
    Icons.sentiment_satisfied,
    Icons.sentiment_very_satisfied,
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('MOOD'),
        const SizedBox(height: AppSpacing.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(5, (i) {
            final mood = i + 1;
            final selected = value == mood;
            return IconButton(
              onPressed: () => onChanged(mood),
              icon: Icon(_icons[i], size: 28, color: selected ? AppColors.accentBlue : AppColors.textMuted),
            );
          }),
        ),
      ],
    );
  }
}
