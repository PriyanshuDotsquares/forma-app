import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/app_router.dart';
import '../../programs/domain/program.dart';
import '../../programs/presentation/active_program_controller.dart';
import '../../programs/presentation/widgets/muscle_tag_chip.dart';
import 'onboarding_controller.dart';

/// Shown once, right after `Step9Building` successfully generates the
/// first plan — a chance to see the week before landing on `/today`.
/// Pushed with a plain `MaterialPageRoute` rather than a GoRouter route
/// since it's a one-off detour off the onboarding flow, not a destination.
class PlanPreviewScreen extends ConsumerStatefulWidget {
  const PlanPreviewScreen({super.key});

  @override
  ConsumerState<PlanPreviewScreen> createState() => _PlanPreviewScreenState();
}

class _PlanPreviewScreenState extends ConsumerState<PlanPreviewScreen> {
  final Set<String> _toggledDayIds = {};

  void _toggleDay(String dayId) {
    setState(() {
      if (!_toggledDayIds.add(dayId)) _toggledDayIds.remove(dayId);
    });
  }

  // Same quiz answers the original generation used — a paramless retry
  // would fall back to whatever defaults `/programs/generate` picks.
  Future<void> _regenerate() async {
    final answers = ref.read(onboardingControllerProvider);
    await ref
        .read(activeProgramControllerProvider.notifier)
        .regenerate(
          goal: answers.goal,
          experienceLevel: answers.experienceLevel,
          daysPerWeek: answers.daysPerWeek,
          sessionMinutes: answers.sessionMinutes,
          splitPreference: answers.splitPreference,
          equipment: answers.canonicalEquipment,
        );
  }

  void _tweakIt() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('You can fine-tune your plan any time from Settings.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(activeProgramControllerProvider);
    final answers = ref.watch(onboardingControllerProvider);
    final activeProgram = state.value;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const _Header(),
            Expanded(
              child: state.when(
                data: (program) => program == null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: FormaEmptyState(
                            icon: Icons.auto_awesome_outlined,
                            title: 'No plan yet.',
                            message: "We couldn't find the plan we just built — try generating it again.",
                            primaryLabel: 'BUILD MY PLAN',
                            onPrimary: _regenerate,
                          ),
                        ),
                      )
                    : _PlanBody(
                        program: program,
                        answers: answers,
                        toggledDayIds: _toggledDayIds,
                        onToggleDay: _toggleDay,
                      ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: FormaEmptyState(
                      icon: Icons.error_outline,
                      title: 'Something went wrong.',
                      message: error is ApiException ? error.message : 'Could not load your plan.',
                      primaryLabel: 'RETRY',
                      onPrimary: () => ref.invalidate(activeProgramControllerProvider),
                    ),
                  ),
                ),
              ),
            ),
            if (activeProgram != null) _BottomBar(onRegenerate: _regenerate, onTweakIt: _tweakIt),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.sm, AppSpacing.lg, AppSpacing.sm),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.of(context).maybePop()),
          ),
          Expanded(
            child: Text('Your plan', textAlign: TextAlign.center, style: AppTypography.display(size: 20)),
          ),
          const SizedBox(width: 40),
        ],
      ),
    );
  }
}

class _PlanBody extends StatelessWidget {
  const _PlanBody({required this.program, required this.answers, required this.toggledDayIds, required this.onToggleDay});

  final Program program;
  final OnboardingAnswers answers;
  final Set<String> toggledDayIds;
  final ValueChanged<String> onToggleDay;

  @override
  Widget build(BuildContext context) {
    final volume = _volumeByMuscle(program).entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final maxSets = volume.isEmpty ? 1 : volume.first.value;
    final firstTrainingDayId = _firstTrainingDay(program)?.id;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        _HeroCard(program: program, answers: answers),
        const SizedBox(height: AppSpacing.lg),
        _WeekDayStrip(program: program),
        const SizedBox(height: AppSpacing.xl),
        const SectionLabel('WEEK 1'),
        const SizedBox(height: AppSpacing.md),
        ...program.days.map((day) {
          final isFirstDay = day.id == firstTrainingDayId;
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: day.isRest
                ? _RestDayRow(day: day)
                : _DayCard(
                    day: day,
                    isFirstDay: isFirstDay,
                    expanded: isFirstDay != toggledDayIds.contains(day.id),
                    onToggle: () => onToggleDay(day.id),
                  ),
          );
        }),
        const SizedBox(height: AppSpacing.md),
        if (volume.isNotEmpty) _WeeklyVolumeCard(entries: volume, maxSets: maxSets),
      ],
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.program, required this.answers});

  final Program program;
  final OnboardingAnswers answers;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.surfaceHigh, AppColors.surfaceBase],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _eyebrowFor(program),
            style: AppTypography.body(size: 11, weight: FontWeight.w700, color: AppColors.textMuted).copyWith(letterSpacing: 1.0),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(_headlineForGoal(answers.goal), style: AppTypography.display(size: 30)),
          const SizedBox(height: AppSpacing.sm),
          Text(_descriptionFor(program, answers), style: AppTypography.body(size: 14, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

class _WeekDayStrip extends StatelessWidget {
  const _WeekDayStrip({required this.program});

  final Program program;

  static const _labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(7, (i) {
        ProgramDay? day;
        for (final d in program.days) {
          if (d.weekday == i) {
            day = d;
            break;
          }
        }
        final trained = day != null && !day.isRest && day.label.trim().isNotEmpty;
        final code = trained ? day.label.trim().substring(0, 1).toUpperCase() : '';
        return Expanded(
          child: Column(
            children: [
              Text(_labels[i], style: AppTypography.body(size: 11, weight: FontWeight.w700, color: AppColors.textMuted)),
              const SizedBox(height: 6),
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: trained ? AppColors.accentBlue : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                  border: trained ? null : Border.all(color: AppColors.outlineVariant),
                ),
                child: trained
                    ? Text(code, style: AppTypography.mono(size: 13, weight: FontWeight.w700, color: AppColors.accentBlueDark))
                    : null,
              ),
            ],
          ),
        );
      }),
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({required this.day, required this.isFirstDay, required this.expanded, required this.onToggle});

  final ProgramDay day;
  final bool isFirstDay;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final position = day.orderIndex + 1;
    final note = day.exercises.isNotEmpty ? day.exercises.first.notes : null;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceBase,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'DAY $position · ${day.estimatedMinutes ?? 45} MIN',
                style: AppTypography.body(size: 11, weight: FontWeight.w700, color: AppColors.textMuted).copyWith(letterSpacing: 1.0),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(child: Text(day.label, style: AppTypography.display(size: 20))),
                  AnimatedRotation(
                    turns: expanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: const Icon(Icons.chevron_right, color: AppColors.textMuted),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(spacing: 6, runSpacing: 6, children: day.muscleTags.map((m) => MuscleTagChip(titleCaseMuscle(m))).toList()),
              if (expanded && isFirstDay && note != null && note.trim().isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                  decoration: const BoxDecoration(
                    border: Border(left: BorderSide(color: AppColors.accentBlue, width: 3)),
                  ),
                  child: Text(note, style: AppTypography.body(size: 13, color: AppColors.textSecondary)),
                ),
              ],
              if (expanded) ...[
                const SizedBox(height: AppSpacing.md),
                ...day.exercises.map(
                  (e) => Padding(padding: const EdgeInsets.only(bottom: AppSpacing.sm), child: _ExerciseRow(exercise: e)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ExerciseRow extends StatelessWidget {
  const _ExerciseRow({required this.exercise});

  final ProgramExercise exercise;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: AppColors.surfaceHighest, borderRadius: BorderRadius.circular(6)),
          child: const Icon(Icons.fitness_center, size: 16, color: AppColors.textMuted),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(exercise.exercise.name, style: AppTypography.body(size: 13))),
        Text(_setsReps(exercise), style: AppTypography.mono(size: 12, color: AppColors.textSecondary)),
      ],
    );
  }
}

class _RestDayRow extends StatelessWidget {
  const _RestDayRow({required this.day});

  final ProgramDay day;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceBase.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Row(
        children: [
          const Icon(Icons.bedtime_outlined, size: 18, color: AppColors.textMuted),
          const SizedBox(width: AppSpacing.sm),
          Text('DAY ${day.orderIndex + 1} · ${day.label}', style: AppTypography.body(size: 13, color: AppColors.textMuted)),
        ],
      ),
    );
  }
}

class _WeeklyVolumeCard extends StatelessWidget {
  const _WeeklyVolumeCard({required this.entries, required this.maxSets});

  final List<MapEntry<String, int>> entries;
  final int maxSets;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceBase,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('WEEKLY VOLUME'),
          const SizedBox(height: AppSpacing.md),
          for (var i = 0; i < entries.length; i++)
            _VolumeBarRow(muscle: entries[i].key, sets: entries[i].value, maxSets: maxSets, color: _volumeBarColors[i % _volumeBarColors.length]),
        ],
      ),
    );
  }
}

// IWF competition-plate colors, cycled per row — matches the day-strip and
// hotspot accents used elsewhere rather than a single flat color per bar.
const _volumeBarColors = [AppColors.accentBlue, AppColors.accentGreen, AppColors.accentRed, AppColors.accentWhite];

class _VolumeBarRow extends StatelessWidget {
  const _VolumeBarRow({required this.muscle, required this.sets, required this.maxSets, required this.color});

  final String muscle;
  final int sets;
  final int maxSets;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(width: 84, child: Text(titleCaseMuscle(muscle), style: AppTypography.body(size: 12, color: AppColors.textSecondary))),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                final barW = maxSets <= 0 ? 0.0 : (sets / maxSets).clamp(0.0, 1.0) * w;
                return Stack(
                  children: [
                    Container(height: 10, decoration: BoxDecoration(color: AppColors.surfaceHighest, borderRadius: BorderRadius.circular(4))),
                    Container(width: barW, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
                  ],
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          Text('$sets sets', style: AppTypography.mono(size: 12, weight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.onRegenerate, required this.onTweakIt});

  final VoidCallback onRegenerate;
  final VoidCallback onTweakIt;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton(
            onPressed: () => context.push(AppRoutes.onboardingSavePlan),
            child: const Text('Looks good'),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(child: OutlinedButton(onPressed: onRegenerate, child: const Text('Regenerate'))),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: OutlinedButton(onPressed: onTweakIt, child: const Text('Tweak it'))),
            ],
          ),
        ],
      ),
    );
  }
}

String _headlineForGoal(String? goal) {
  switch (goal) {
    case 'build_muscle':
      return 'Built to grow';
    case 'get_stronger':
      return 'Built for strength';
    case 'lose_fat':
      return 'Built to cut';
    case 'general_health':
      return 'Built to last';
    case 'athletic_performance':
      return 'Built to perform';
    case 'move_better':
      return 'Built to move';
    default:
      return 'Built for you';
  }
}

String _eyebrowFor(Program program) {
  final split = program.splitType.split('_').where((s) => s.isNotEmpty).map((s) => s.toUpperCase()).join(' / ');
  return '$split · ${program.daysPerWeek} DAYS · ${program.durationWeeks} WEEKS';
}

ProgramDay? _firstTrainingDay(Program program) {
  for (final day in program.days) {
    if (!day.isRest && day.exercises.isNotEmpty) return day;
  }
  return null;
}

/// A truthful one-clause characteristic, derived from real plan data — not
/// per-user copywriting. Returns null rather than guessing.
String? _derivedTrait(Program program, OnboardingAnswers answers) {
  if (answers.injuries.isNotEmpty) return 'works around what you flagged';
  final firstExercise = _firstTrainingDay(program)?.exercises.first;
  if (firstExercise != null && firstExercise.repRangeLow <= 6) return 'leads with heavy compound lifts';
  return null;
}

String _descriptionFor(Program program, OnboardingAnswers answers) {
  final sessions = '${program.daysPerWeek} session${program.daysPerWeek == 1 ? '' : 's'} a week';
  final base = 'Built around $sessions over ${program.durationWeeks} weeks';
  final trait = _derivedTrait(program, answers);
  return trait == null ? '$base.' : '$base — $trait.';
}

Map<String, int> _volumeByMuscle(Program program) {
  final map = <String, int>{};
  for (final day in program.days) {
    for (final exercise in day.exercises) {
      for (final muscle in exercise.exercise.primaryMuscles) {
        map[muscle] = (map[muscle] ?? 0) + exercise.sets;
      }
    }
  }
  return map;
}

String _setsReps(ProgramExercise e) => '${e.sets} × ${e.repRangeLow}–${e.repRangeHigh}';
