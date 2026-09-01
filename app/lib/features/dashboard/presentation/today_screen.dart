import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/app_router.dart';
import '../../auth/domain/user.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../programs/domain/program.dart';
import '../../programs/presentation/widgets/muscle_tag_chip.dart';
import '../../progress/domain/progress_models.dart';
import '../../progress/presentation/widgets/progress_format.dart' hide titleCaseMuscle;
import '../../progress/presentation/widgets/recovery_silhouette.dart';
import '../../workout/domain/workout_session.dart';
import '../../workout/presentation/workout_providers.dart';
import 'today_controller.dart';

class TodayScreen extends ConsumerStatefulWidget {
  const TodayScreen({super.key});

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen> {
  bool _coachBannerDismissed = false;

  @override
  Widget build(BuildContext context) {
    final todayState = ref.watch(todayControllerProvider);
    final user = ref.watch(authControllerProvider).valueOrNull;

    return Scaffold(
      body: SafeArea(
        child: todayState.when(
          data: (data) => _Content(user: user, data: data, coachBannerDismissed: _coachBannerDismissed, onDismissCoachBanner: () => setState(() => _coachBannerDismissed = true)),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: FormaEmptyState(
                icon: Icons.error_outline,
                title: 'Something went wrong.',
                message: error is ApiException ? error.message : 'Could not load today. Please try again.',
                primaryLabel: 'RETRY',
                onPrimary: () => ref.invalidate(todayControllerProvider),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Content extends ConsumerWidget {
  const _Content({required this.user, required this.data, required this.coachBannerDismissed, required this.onDismissCoachBanner});

  final User? user;
  final TodayData data;
  final bool coachBannerDismissed;
  final VoidCallback onDismissCoachBanner;

  ProgramDay? _dayForWeekday(Program program, int apiWeekday) {
    for (final day in program.days) {
      if (day.weekday == apiWeekday) return day;
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final program = data.program;
    final todayApiWeekday = DateTime.now().weekday - 1; // Dart: 1=Mon..7=Sun -> API: 0=Mon..6=Sun
    final todayDay = program != null ? _dayForWeekday(program, todayApiWeekday) : null;
    final isWorkoutDay = todayDay != null && !todayDay.isRest;

    return RefreshIndicator(
      onRefresh: () => ref.read(todayControllerProvider.notifier).refresh(),
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          _Header(user: user),
          const SizedBox(height: AppSpacing.xl),
          if (program == null)
            _NoProgramCard(onboarded: user?.onboardingCompleted ?? false)
          else ...[
            if (isWorkoutDay)
              _WorkoutDayCard(day: todayDay, sessions: data.sessions)
            else
              _RestDayCard(program: program, recovery: data.recovery),
            // Figma shows this compact card on both the workout-day and
            // rest-day dashboard — only the rest day additionally gets its
            // own inline breakdown inside the hero card above.
            if (data.recovery.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              _RecoveryCard(recovery: data.recovery),
            ],
          ],
          const SizedBox(height: AppSpacing.xl),
          _ThisWeekSection(program: program, sessions: data.sessions),
          const SizedBox(height: AppSpacing.xl),
          if (!coachBannerDismissed) ...[
            _CoachBanner(onDismiss: onDismissCoachBanner),
            const SizedBox(height: AppSpacing.xl),
          ],
          _RecentSection(sessions: data.sessions),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.user});

  final User? user;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dateLabel = DateFormat('EEEE d MMM').format(now).toUpperCase();
    final hour = now.hour;
    final timeOfDay = hour < 12 ? 'morning' : (hour < 17 ? 'afternoon' : 'evening');
    final fullName = user?.fullName?.trim();
    final firstName = (fullName != null && fullName.isNotEmpty) ? fullName.split(' ').first : 'there';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(dateLabel, style: AppTypography.mono(size: 12, color: AppColors.textMuted).copyWith(letterSpacing: 1.2)),
              const SizedBox(height: 4),
              Text('Good $timeOfDay, $firstName', style: AppTypography.display(size: 24)),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.notifications_none),
          onPressed: () {},
        ),
        CircleAvatar(
          radius: 20,
          backgroundColor: AppColors.surfaceHigh,
          backgroundImage: (user?.avatarUrl != null && user!.avatarUrl!.isNotEmpty) ? NetworkImage(user!.avatarUrl!) : null,
          child: (user?.avatarUrl == null || user!.avatarUrl!.isEmpty)
              ? const Icon(Icons.person_outline, color: AppColors.textSecondary)
              : null,
        ),
      ],
    );
  }
}

class _NoProgramCard extends ConsumerWidget {
  const _NoProgramCard({required this.onboarded});

  final bool onboarded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!onboarded) {
      return FormaEmptyState(
        icon: Icons.fitness_center,
        eyebrow: 'NO PLAN YET',
        title: 'No plan yet.',
        message: "Answer a few questions and we'll build your first week.",
        primaryLabel: 'BUILD MY PLAN',
        onPrimary: () => context.push(AppRoutes.onboarding),
      );
    }
    return FormaEmptyState(
      icon: Icons.refresh,
      eyebrow: 'NO PLAN YET',
      title: 'No plan yet.',
      message: "Something interrupted building your plan. Let's try again.",
      primaryLabel: 'GENERATE MY PLAN',
      onPrimary: () => ref.read(todayControllerProvider.notifier).regenerateProgram(),
    );
  }
}

Future<void> _startSession(BuildContext context, WidgetRef ref, {String? programDayId, required String label}) async {
  try {
    final session = await ref.read(workoutRepositoryProvider).startSession(programDayId: programDayId, label: label);
    if (context.mounted) context.push(AppRoutes.workoutActive(session.id));
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e is ApiException ? e.message : 'Could not start workout. Please try again.')),
    );
  }
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

class _WorkoutDayCard extends ConsumerWidget {
  const _WorkoutDayCard({required this.day, required this.sessions});

  final ProgramDay day;
  final List<WorkoutSession> sessions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totalSets = day.exercises.fold<int>(0, (sum, e) => sum + e.sets);
    final duration = day.estimatedMinutes ?? 45;

    // There's no session "in progress" status — a session the user started
    // today for this day and hasn't finished is the closest signal that
    // some sets are already logged, so the load strip isn't stuck at zero
    // if they backed out mid-workout and came back.
    final today = _dateOnly(DateTime.now());
    WorkoutSession? startedToday;
    for (final s in sessions) {
      if (!s.isFinished && s.programDayId == day.id && _dateOnly(s.startedAt) == today) {
        startedToday = s;
        break;
      }
    }
    final completed = (startedToday?.sets.length ?? 0).clamp(0, totalSets);

    return Container(
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
            children: [
              const BadgePill('TODAY', outlined: true),
              const Spacer(),
              Text('$duration MIN', style: AppTypography.mono(size: 13, color: AppColors.textSecondary)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(day.label.toUpperCase(), style: AppTypography.display(size: 30)),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: day.muscleTags.map((m) => MuscleTagChip(titleCaseMuscle(m))).toList(),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${day.exercises.length} exercises · $totalSets sets',
            style: AppTypography.body(size: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          LoadStrip(total: totalSets, completed: completed),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => _startSession(context, ref, programDayId: day.id, label: day.label),
              child: const Text('START WORKOUT'),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: () => context.push(AppRoutes.planSessionPreview(day.id)),
                child: const Text('Preview'),
              ),
              Text('·', style: AppTypography.body(color: AppColors.textMuted)),
              TextButton(
                onPressed: () => context.push(AppRoutes.planDay(day.id)),
                child: const Text("Swap today's session"),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

const _legsMuscles = ['quads', 'hamstrings', 'glutes', 'calves'];

/// The dashboard's recovery cards show a simplified chest/back/legs
/// breakdown, but the recovery API tracks 10 finer muscle groups — there's
/// no single "legs" entry. Synthesize one from the worst-recovered leg
/// muscle, since that's the one that actually gates training legs again.
RecoveryItem? _legsRecoveryItem(List<RecoveryItem> recovery) {
  final legs = _legsMuscles
      .map((m) {
        for (final r in recovery) {
          if (r.muscleGroup.toLowerCase() == m) return r;
        }
        return null;
      })
      .whereType<RecoveryItem>()
      .toList();
  if (legs.isEmpty) return null;
  legs.sort((a, b) => a.recoveredPct.compareTo(b.recoveredPct));
  return RecoveryItem(muscleGroup: 'legs', recoveredPct: legs.first.recoveredPct, setsLastSession: legs.first.setsLastSession);
}

List<RecoveryItem> _coarseRecoveryBars(List<RecoveryItem> recovery, List<String> order) {
  final legs = _legsRecoveryItem(recovery);
  final bars = <RecoveryItem>[];
  for (final m in order) {
    if (m == 'legs') {
      if (legs != null) bars.add(legs);
      continue;
    }
    for (final r in recovery) {
      if (r.muscleGroup.toLowerCase() == m) {
        bars.add(r);
        break;
      }
    }
  }
  return bars;
}

class _RecoveryCard extends StatelessWidget {
  const _RecoveryCard({required this.recovery});

  final List<RecoveryItem> recovery;

  @override
  Widget build(BuildContext context) {
    final bars = _coarseRecoveryBars(recovery, const ['chest', 'legs', 'back']);
    if (bars.isEmpty) return const SizedBox.shrink();
    final pctByMuscle = {for (final r in recovery) r.muscleGroup.toLowerCase(): r.recoveredPct};

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceBase,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(
            'RECOVERY',
            trailing: Tooltip(
              message: 'Estimated from time since you last trained each muscle group.',
              child: Icon(Icons.info_outline, size: 14, color: AppColors.textMuted),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final r in bars)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              margin: const EdgeInsets.only(right: AppSpacing.sm),
                              decoration: BoxDecoration(shape: BoxShape.circle, color: recoveryColor(r.recoveredPct)),
                            ),
                            SizedBox(
                              width: 64,
                              child: Text(titleCaseMuscle(r.muscleGroup), style: AppTypography.body(size: 13, color: AppColors.textSecondary)),
                            ),
                            Text(
                              '${r.recoveredPct.round()}%',
                              style: AppTypography.mono(size: 13, weight: FontWeight.w600, color: recoveryColor(r.recoveredPct)),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              Opacity(
                opacity: 0.8,
                child: RecoverySilhouette(pctByMuscle: pctByMuscle, isFront: true, width: 88, height: 118),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RestDayCard extends ConsumerWidget {
  const _RestDayCard({required this.program, required this.recovery});

  final Program program;
  final List<RecoveryItem> recovery;

  String _recoveryHeadline() {
    final recovering = recovery.where((r) => r.recoveredPct < 100).toList()
      ..sort((a, b) => a.recoveredPct.compareTo(b.recoveredPct));
    if (recovering.isEmpty) {
      return 'Everything is fresh — a good day to rest before your next session.';
    }
    final names = recovering.take(2).map((r) => titleCaseMuscle(r.muscleGroup)).toList();
    final joined = names.length == 1 ? names.first : '${names[0]} and ${names[1]}';
    final verb = names.length == 1 ? 'is' : 'are';
    return '$joined $verb still rebuilding.';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bars = _coarseRecoveryBars(recovery, const ['chest', 'back', 'legs']);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceBase,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BadgePill('REST DAY', color: AppColors.accentGreen, outlined: true),
          const SizedBox(height: AppSpacing.sm),
          Text('Let it rebuild.', style: AppTypography.display(size: 28)),
          const SizedBox(height: AppSpacing.xs),
          Text(_recoveryHeadline(), style: AppTypography.body(size: 14, color: AppColors.textSecondary)),
          if (bars.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            ...bars.map(
              (r) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  children: [
                    SizedBox(
                      width: 56,
                      child: Text(
                        titleCaseMuscle(r.muscleGroup).toUpperCase(),
                        style: AppTypography.body(size: 12, color: AppColors.textSecondary),
                      ),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: (r.recoveredPct / 100).clamp(0, 1),
                          minHeight: 6,
                          backgroundColor: AppColors.surfaceHighest,
                          color: recoveryColor(r.recoveredPct),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      '${r.recoveredPct.round()}%',
                      style: AppTypography.mono(size: 12, color: recoveryColor(r.recoveredPct)),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Coming soon.'))),
                  child: const Text('10-MIN MOBILITY'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _startSession(context, ref, label: 'Freestyle workout'),
                  child: const Text('TRAIN ANYWAY'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ThisWeekSection extends StatelessWidget {
  const _ThisWeekSection({required this.program, required this.sessions});

  final Program? program;
  final List<WorkoutSession> sessions;

  static const _labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = _dateOnly(now);
    final monday = today.subtract(Duration(days: now.weekday - 1));
    final trainedDates = sessions.map((s) => _dateOnly(s.startedAt)).toSet();

    final streak = _computeStreak(trainedDates, today);
    final volume = _volumeSince(sessions, monday);
    final form = _avgFormSince(sessions, monday);

    var scheduledCount = 0;
    var doneCount = 0;
    for (final day in program?.days ?? const []) {
      if (day.isRest || day.weekday == null) continue;
      scheduledCount++;
      if (trainedDates.contains(monday.add(Duration(days: day.weekday!)))) doneCount++;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(
          'THIS WEEK',
          trailing: scheduledCount == 0
              ? null
              : Text('$doneCount of $scheduledCount done', style: AppTypography.mono(size: 14, color: AppColors.textSecondary)),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: List.generate(7, (i) {
            final date = monday.add(Duration(days: i));
            final trained = trainedDates.contains(date);
            final isToday = date == today;
            return Expanded(
              child: Column(
                children: [
                  Text(_labels[i], style: AppTypography.body(size: 12, color: AppColors.textMuted)),
                  const SizedBox(height: 6),
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: trained ? AppColors.accentGreen : Colors.transparent,
                      border: Border.all(color: trained ? AppColors.accentGreen : (isToday ? AppColors.accentBlue : AppColors.outlineVariant)),
                    ),
                    child: trained
                        ? const Icon(Icons.check, size: 16, color: AppColors.accentBlueDark)
                        : (isToday ? const Icon(Icons.circle, size: 6, color: AppColors.accentBlue) : null),
                  ),
                ],
              ),
            );
          }),
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Expanded(child: StatTile(label: 'STREAK', value: '$streak', unit: streak == 1 ? 'day' : 'days')),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: StatTile(label: 'VOLUME', value: formatVolumeKg(volume), unit: 'kg this wk')),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: StatTile(label: 'FORM', value: form == null ? '—' : form.round().toString(), unit: form == null ? null : '%')),
          ],
        ),
      ],
    );
  }

  int _computeStreak(Set<DateTime> trainedDates, DateTime today) {
    var cursor = today;
    if (!trainedDates.contains(cursor)) {
      cursor = cursor.subtract(const Duration(days: 1));
    }
    var streak = 0;
    while (trainedDates.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  double _volumeSince(List<WorkoutSession> sessions, DateTime monday) {
    double total = 0;
    for (final s in sessions) {
      if (!s.startedAt.isBefore(monday)) {
        for (final set in s.sets) {
          if (set.actualWeightKg != null && set.actualReps != null) {
            total += set.actualWeightKg! * set.actualReps!;
          }
        }
      }
    }
    return total;
  }

  double? _avgFormSince(List<WorkoutSession> sessions, DateTime monday) {
    final scores = <double>[];
    for (final s in sessions) {
      if (!s.startedAt.isBefore(monday) && s.avgFormScore != null) {
        scores.add(s.avgFormScore!);
      }
    }
    if (scores.isEmpty) return null;
    return scores.reduce((a, b) => a + b) / scores.length;
  }
}

class _CoachBanner extends StatelessWidget {
  const _CoachBanner({required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push(AppRoutes.coach),
      child: InfoBanner(
        title: 'Meet your AI coach',
        body: 'Thirty seconds, no weights needed.',
        icon: Icons.smart_toy_outlined,
        trailing: IconButton(
          icon: const Icon(Icons.close, size: 18, color: AppColors.textMuted),
          onPressed: onDismiss,
        ),
      ),
    );
  }
}

class _RecentSection extends StatelessWidget {
  const _RecentSection({required this.sessions});

  final List<WorkoutSession> sessions;

  @override
  Widget build(BuildContext context) {
    final finished = sessions.where((s) => s.isFinished).take(3).toList();
    if (finished.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('RECENT'),
        const SizedBox(height: AppSpacing.md),
        ...finished.map((s) => Padding(padding: const EdgeInsets.only(bottom: AppSpacing.sm), child: _RecentRow(session: s))),
      ],
    );
  }
}

class _RecentRow extends StatelessWidget {
  const _RecentRow({required this.session});

  final WorkoutSession session;

  @override
  Widget build(BuildContext context) {
    final minutes = session.durationS != null ? (session.durationS! / 60).round() : null;
    double volume = 0;
    for (final set in session.sets) {
      if (set.actualWeightKg != null && set.actualReps != null) volume += set.actualWeightKg! * set.actualReps!;
    }
    final hasPr = session.sets.any((set) => set.isPr);
    final parts = <String>[
      if (minutes != null) '$minutes min',
      '${session.sets.length} sets',
      if (volume > 0) '${formatVolumeKg(volume)} kg',
    ];

    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.card),
      onTap: () => context.push(AppRoutes.workoutSummary(session.id)),
      child: Container(
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
                  Row(
                    children: [
                      Text(session.label, style: AppTypography.body(size: 15, weight: FontWeight.w600)),
                      if (hasPr) ...[const SizedBox(width: 6), const BadgePill('PR', color: AppColors.accentRed, outlined: true)],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(parts.join(' · '), style: AppTypography.mono(size: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}
