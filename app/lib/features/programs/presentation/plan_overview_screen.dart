import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/app_router.dart';
import '../../workout/domain/workout_session.dart';
import '../../workout/presentation/workout_providers.dart';
import '../domain/program.dart';
import 'active_program_controller.dart';
import 'programs_providers.dart';
import 'widgets/muscle_tag_chip.dart';
import 'widgets/no_active_program_view.dart';

class PlanOverviewScreen extends ConsumerWidget {
  const PlanOverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(activeProgramControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('YOUR PLAN'),
        actions: [
          IconButton(
            tooltip: 'Browse exercises',
            icon: const Icon(Icons.search),
            onPressed: () => context.push(AppRoutes.planExercises),
          ),
          IconButton(
            tooltip: 'Workout history',
            icon: const Icon(Icons.calendar_month_outlined),
            onPressed: () => context.push('/plan/history'),
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
            return _PlanContent(program: program);
          },
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
    );
  }
}

enum _DayStatus { rest, done, today, scheduled }

const _weekdayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

/// Small, curated abbreviations for the muscle-tag chips on each day row —
/// purely presentational (the real tag driving the chip is still whatever
/// the backend returned), matching the compact 4-letter style in the Figma
/// reference. Falls back to a mechanical truncation for anything unmapped.
const _muscleAbbreviations = <String, String>{
  'chest': 'CHST',
  'back': 'BACK',
  'shoulders': 'SHLD',
  'biceps': 'BICE',
  'triceps': 'TRIC',
  'quads': 'QUAD',
  'hamstrings': 'HAMS',
  'glutes': 'GLUT',
  'calves': 'CALV',
  'core': 'CORE',
  'abs': 'ABS',
  'forearms': 'FORE',
  'lats': 'LATS',
  'front_delts': 'DELT',
  'rear_delts': 'DELT',
  'traps': 'TRAP',
};

String _muscleAbbrev(String raw) {
  final mapped = _muscleAbbreviations[raw.toLowerCase()];
  if (mapped != null) return mapped;
  final compact = raw.replaceAll('_', '').toUpperCase();
  return compact.length <= 4 ? compact : compact.substring(0, 4);
}

DateTime _mondayOf(DateTime d) {
  final day = DateTime(d.year, d.month, d.day);
  return day.subtract(Duration(days: day.weekday - 1));
}

class _WeekProgress {
  const _WeekProgress({required this.currentWeek, required this.completedWeeks, required this.currentWeekStart});

  final int currentWeek;
  final Set<int> completedWeeks;
  final DateTime currentWeekStart;
}

/// Derives "week N of the program" from real workout history instead of
/// inventing progress data. The backend has no program start date and no
/// per-week variation — `program.days` is one repeating week structure — so
/// "week N" here means "which lap through that cycle," anchored to the
/// calendar week of the earliest finished session tied to one of this
/// program's days. With no session history yet, everything defaults to
/// week 1 rather than guessing.
_WeekProgress _computeWeekProgress(Program program, List<WorkoutSession> sessions) {
  final dayIds = program.days.map((d) => d.id).toSet();
  final matched = sessions.where((s) => s.isFinished && s.programDayId != null && dayIds.contains(s.programDayId)).toList();
  final nowMonday = _mondayOf(DateTime.now());
  final totalWeeks = program.durationWeeks < 1 ? 1 : program.durationWeeks;

  if (matched.isEmpty) {
    return _WeekProgress(currentWeek: 1, completedWeeks: const {}, currentWeekStart: nowMonday);
  }

  var earliest = matched.first.startedAt;
  for (final s in matched) {
    if (s.startedAt.isBefore(earliest)) earliest = s.startedAt;
  }
  final startMonday = _mondayOf(earliest);
  var currentWeek = (nowMonday.difference(startMonday).inDays ~/ 7) + 1;
  if (currentWeek < 1) currentWeek = 1;
  if (currentWeek > totalWeeks) currentWeek = totalWeeks;
  final currentWeekStart = startMonday.add(Duration(days: 7 * (currentWeek - 1)));

  final completed = <int>{};
  for (var week = 1; week < currentWeek; week++) {
    final weekStart = startMonday.add(Duration(days: 7 * (week - 1)));
    final weekEnd = weekStart.add(const Duration(days: 7));
    final trained = matched.any((s) => !s.startedAt.isBefore(weekStart) && s.startedAt.isBefore(weekEnd));
    if (trained) completed.add(week);
  }

  return _WeekProgress(currentWeek: currentWeek, completedWeeks: completed, currentWeekStart: currentWeekStart);
}

String? _lowestVolumeMuscle(Map<String, int> volumeByMuscle, {int threshold = 8}) {
  String? worst;
  var worstSets = threshold;
  for (final entry in volumeByMuscle.entries) {
    if (entry.value < threshold && (worst == null || entry.value < worstSets)) {
      worst = entry.key;
      worstSets = entry.value;
    }
  }
  return worst;
}

class _PlanContent extends ConsumerStatefulWidget {
  const _PlanContent({required this.program});

  final Program program;

  @override
  ConsumerState<_PlanContent> createState() => _PlanContentState();
}

class _PlanContentState extends ConsumerState<_PlanContent> {
  late List<ProgramDay> _days;
  bool _addingDay = false;

  @override
  void initState() {
    super.initState();
    _syncDays();
  }

  @override
  void didUpdateWidget(covariant _PlanContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    final incoming = widget.program.days.map((d) => d.id).toSet();
    final local = _days.map((d) => d.id).toSet();
    if (incoming.length != local.length || !incoming.containsAll(local)) {
      _syncDays();
    }
  }

  void _syncDays() {
    _days = List.of(widget.program.days)..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
  }

  String _eyebrow(int weekIndex) {
    final split = widget.program.splitType.split('_').where((s) => s.isNotEmpty).map((s) => s.toUpperCase()).join(' / ');
    return '$split · WEEK $weekIndex OF ${widget.program.durationWeeks}';
  }

  String _description() {
    final split = widget.program.splitType.replaceAll('_', ' ');
    return 'A $split split across ${widget.program.daysPerWeek} sessions a week, built to progress over ${widget.program.durationWeeks} weeks.';
  }

  Map<String, int> _volumeByMuscle() {
    final map = <String, int>{};
    for (final day in widget.program.days) {
      for (final exercise in day.exercises) {
        for (final muscle in exercise.exercise.primaryMuscles) {
          map[muscle] = (map[muscle] ?? 0) + exercise.sets;
        }
      }
    }
    return map;
  }

  Future<void> _persistDayReorder(List<ProgramDay> reordered) async {
    final repository = ref.read(programsRepositoryProvider);
    try {
      for (var i = 0; i < reordered.length; i++) {
        if (reordered[i].orderIndex != i) {
          await repository.updateDay(reordered[i].id, {'order_index': i});
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e is ApiException ? e.message : 'Could not reorder days.')),
        );
      }
    } finally {
      await ref.read(activeProgramControllerProvider.notifier).refresh();
    }
  }

  Future<void> _addDay() async {
    setState(() => _addingDay = true);
    try {
      final day = await ref.read(programsRepositoryProvider).addDay(
        widget.program.id,
        orderIndex: widget.program.days.length,
        label: 'New Day',
      );
      await ref.read(activeProgramControllerProvider.notifier).refresh();
      if (mounted) context.push(AppRoutes.planDay(day.id));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e is ApiException ? e.message : 'Could not add a day.')),
        );
      }
    } finally {
      if (mounted) setState(() => _addingDay = false);
    }
  }

  void _onTapWeek(int week, int currentWeek) {
    if (week == currentWeek) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Only your current week is tracked here — the plan repeats this structure each week.')),
    );
  }

  void _fixLowVolume(String muscle) {
    ProgramDay? target;
    for (final day in widget.program.days) {
      if (day.isRest) continue;
      final inTags = day.muscleTags.any((t) => t.toLowerCase() == muscle);
      final inExercises = day.exercises.any((e) => e.exercise.primaryMuscles.any((m) => m.toLowerCase() == muscle));
      if (inTags || inExercises) {
        target = day;
        break;
      }
    }
    if (target != null) {
      context.push(AppRoutes.planDay(target.id));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Add more ${titleCaseMuscle(muscle)} work to a day to fix this.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final program = widget.program;
    final sessions = ref.watch(workoutHistoryProvider).valueOrNull ?? const <WorkoutSession>[];
    final weekProgress = _computeWeekProgress(program, sessions);
    final volumeByMuscle = _volumeByMuscle();
    final volumeEntries = volumeByMuscle.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final topMuscles = volumeEntries.take(3).toList();
    final maxSets = topMuscles.isEmpty ? 1 : topMuscles.first.value;
    final lowMuscle = _lowestVolumeMuscle(volumeByMuscle);
    final todayApiWeekday = DateTime.now().weekday - 1; // Dart: 1=Mon..7=Sun -> API: 0=Mon..6=Sun
    final weekEnd = weekProgress.currentWeekStart.add(const Duration(days: 7));

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        // Summary card.
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: AppColors.surfaceBase,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _eyebrow(weekProgress.currentWeek),
                          style: AppTypography.body(size: 11, weight: FontWeight.w700, color: AppColors.textMuted).copyWith(letterSpacing: 1.0),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(program.name, style: AppTypography.display(size: 26)),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_horiz, color: AppColors.textMuted),
                    onSelected: (value) {
                      if (value == 'regenerate') {
                        ref.read(activeProgramControllerProvider.notifier).regenerate();
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'regenerate', child: Text('Regenerate plan')),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(_description(), style: AppTypography.body(size: 14, color: AppColors.textSecondary)),
              const SizedBox(height: AppSpacing.lg),
              _WeekTabsRow(
                durationWeeks: program.durationWeeks,
                currentWeek: weekProgress.currentWeek,
                completedWeeks: weekProgress.completedWeeks,
                onTapWeek: (week) => _onTapWeek(week, weekProgress.currentWeek),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        if (lowMuscle != null) ...[
          InfoBanner(
            title:
                '${titleCaseMuscle(lowMuscle)} gets ${volumeByMuscle[lowMuscle]} ${volumeByMuscle[lowMuscle] == 1 ? 'set' : 'sets'} this week — a bit low.',
            icon: Icons.warning_amber_rounded,
            accent: AppColors.accentRed,
            trailing: TextButton(onPressed: () => _fixLowVolume(lowMuscle), child: const Text('FIX')),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _days.length,
          onReorder: (oldIndex, newIndex) {
            setState(() {
              if (oldIndex < newIndex) newIndex -= 1;
              final moved = _days.removeAt(oldIndex);
              _days.insert(newIndex, moved);
            });
            _persistDayReorder(_days);
          },
          itemBuilder: (context, index) {
            final day = _days[index];
            final letter = day.weekday != null ? _weekdayLetters[day.weekday!] : (day.label.isNotEmpty ? day.label[0].toUpperCase() : '?');

            Widget child;
            if (day.isRest) {
              child = _RestDayRow(day: day, letter: letter);
            } else {
              final isToday = day.weekday == todayApiWeekday;
              final isDone = sessions.any(
                (s) =>
                    s.programDayId == day.id &&
                    s.isFinished &&
                    !s.startedAt.isBefore(weekProgress.currentWeekStart) &&
                    s.startedAt.isBefore(weekEnd),
              );
              final status = isDone ? _DayStatus.done : (isToday ? _DayStatus.today : _DayStatus.scheduled);
              child = _DayCard(day: day, status: status, letter: letter);
            }

            return Padding(key: ValueKey(day.id), padding: const EdgeInsets.only(bottom: AppSpacing.sm), child: child);
          },
        ),
        const SizedBox(height: AppSpacing.md),
        if (topMuscles.isNotEmpty) ...[
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
                const SectionLabel('WEEKLY VOLUME'),
                const SizedBox(height: AppSpacing.md),
                ...topMuscles.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Row(
                      children: [
                        SizedBox(width: 72, child: Text(titleCaseMuscle(entry.key), style: AppTypography.body(size: 12, color: AppColors.textSecondary))),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              value: entry.value / maxSets,
                              minHeight: 6,
                              backgroundColor: AppColors.surfaceHighest,
                              color: AppColors.accentBlue,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text('${entry.value} sets', style: AppTypography.mono(size: 12)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _addingDay ? null : _addDay,
            icon: const Icon(Icons.add, size: 18),
            label: Text(_addingDay ? 'ADDING…' : 'ADD DAY'),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => context.go(AppRoutes.coach),
            icon: const Icon(Icons.auto_awesome, size: 18),
            label: const Text('ASK AI TO ADJUST'),
          ),
        ),
      ],
    );
  }
}

class _WeekTabsRow extends StatelessWidget {
  const _WeekTabsRow({required this.durationWeeks, required this.currentWeek, required this.completedWeeks, required this.onTapWeek});

  final int durationWeeks;
  final int currentWeek;
  final Set<int> completedWeeks;
  final ValueChanged<int> onTapWeek;

  @override
  Widget build(BuildContext context) {
    final weeks = durationWeeks < 1 ? 1 : durationWeeks;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(weeks, (i) {
          final week = i + 1;
          final isCurrent = week == currentWeek;
          final isCompleted = completedWeeks.contains(week);

          return Padding(
            padding: EdgeInsets.only(right: i == weeks - 1 ? 0 : AppSpacing.sm),
            child: GestureDetector(
              onTap: () => onTapWeek(week),
              child: Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isCurrent ? AppColors.accentBlue : AppColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: isCurrent ? AppColors.accentBlue : AppColors.outlineVariant),
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    Text(
                      'W$week',
                      style: AppTypography.mono(size: 16, weight: FontWeight.w600, color: isCurrent ? AppColors.accentBlueDark : AppColors.textSecondary),
                    ),
                    if (isCompleted)
                      const Positioned(top: 2, right: 2, child: Icon(Icons.check_circle, size: 12, color: AppColors.accentGreen)),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _DayAvatar extends StatelessWidget {
  const _DayAvatar({required this.letter, required this.status});

  final String letter;
  final _DayStatus status;

  @override
  Widget build(BuildContext context) {
    var bg = AppColors.surfaceHigh;
    Color? border;
    var fg = AppColors.textSecondary;

    if (status == _DayStatus.rest) {
      bg = AppColors.surfaceLowest;
      fg = AppColors.textMuted;
    } else if (status == _DayStatus.done) {
      bg = AppColors.accentGreen.withValues(alpha: 0.18);
      border = AppColors.accentGreen.withValues(alpha: 0.4);
      fg = AppColors.accentGreen;
    } else if (status == _DayStatus.today) {
      bg = AppColors.accentBlue.withValues(alpha: 0.1);
      border = AppColors.accentBlue.withValues(alpha: 0.4);
      fg = AppColors.accentBlue;
    }

    return Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4), border: border != null ? Border.all(color: border) : null),
      child: status == _DayStatus.done
          ? Icon(Icons.check, size: 20, color: fg)
          : Text(letter, style: AppTypography.mono(size: 16, weight: FontWeight.w600, color: fg)),
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({required this.day, required this.status, required this.letter});

  final ProgramDay day;
  final _DayStatus status;
  final String letter;

  @override
  Widget build(BuildContext context) {
    final highlight = status == _DayStatus.today;

    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.card),
      onTap: () => context.push(AppRoutes.planDay(day.id)),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surfaceBase,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: highlight ? AppColors.accentBlue : AppColors.outlineVariant),
          boxShadow: highlight ? [BoxShadow(color: AppColors.accentBlue.withValues(alpha: 0.15), blurRadius: 16)] : null,
        ),
        child: Row(
          children: [
            if (highlight)
              Container(
                width: 3,
                height: 48,
                margin: const EdgeInsets.only(right: AppSpacing.sm),
                decoration: BoxDecoration(color: AppColors.accentBlue, borderRadius: BorderRadius.circular(2)),
              ),
            _DayAvatar(letter: letter, status: status),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(day.label.toUpperCase(), style: AppTypography.display(size: 18), overflow: TextOverflow.ellipsis, maxLines: 1),
                  if (day.muscleTags.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: day.muscleTags.take(2).map((m) => MuscleTagChip(_muscleAbbrev(m))).toList(),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text('${day.exercises.length} exercises · ${day.estimatedMinutes ?? 45} min', style: AppTypography.mono(size: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            if (status == _DayStatus.done) const BadgePill('DONE', color: AppColors.accentGreen),
            if (status == _DayStatus.today) const BadgePill('TODAY', color: AppColors.accentBlue, outlined: true),
            if (status != _DayStatus.scheduled) const SizedBox(width: 8),
            const Icon(Icons.drag_handle, color: AppColors.textMuted, size: 18),
          ],
        ),
      ),
    );
  }
}

class _RestDayRow extends StatelessWidget {
  const _RestDayRow({required this.day, required this.letter});

  final ProgramDay day;
  final String letter;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.5,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surfaceBase,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.outlineVariant),
        ),
        child: Row(
          children: [
            _DayAvatar(letter: letter, status: _DayStatus.rest),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text('REST', style: AppTypography.display(size: 18, color: AppColors.textMuted))),
            Text('Rest', style: AppTypography.mono(size: 12, color: AppColors.textMuted)),
            const SizedBox(width: 8),
            const Icon(Icons.drag_handle, color: AppColors.textMuted, size: 18),
          ],
        ),
      ),
    );
  }
}
