import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/app_router.dart';
import '../../achievements/data/achievements_providers.dart';
import '../../achievements/domain/achievement.dart';
import '../../progress/data/progress_providers.dart';
import '../../progress/presentation/widgets/sparkline.dart';
import '../../workout/presentation/workout_providers.dart';
import '../domain/exercise.dart';
import 'exercise_library_controller.dart';
import 'widgets/muscle_tag_chip.dart';

class ExerciseDetailScreen extends ConsumerWidget {
  const ExerciseDetailScreen({super.key, required this.exerciseId});

  final String exerciseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(exerciseByIdProvider(exerciseId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('EXERCISE'),
        actions: [
          if (state.valueOrNull != null)
            IconButton(
              icon: const Icon(Icons.ios_share),
              onPressed: () =>
                  SharePlus.instance.share(ShareParams(text: '${state.valueOrNull!.name} — training with FORMA')),
            ),
        ],
      ),
      body: SafeArea(
        child: state.when(
          data: (exercise) => _ExerciseDetailContent(exercise: exercise),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: FormaEmptyState(
                icon: Icons.error_outline,
                title: 'Something went wrong.',
                message: error is ApiException ? error.message : 'Could not load this exercise.',
                primaryLabel: 'RETRY',
                onPrimary: () => ref.invalidate(exerciseByIdProvider(exerciseId)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ExerciseDetailContent extends ConsumerWidget {
  const _ExerciseDetailContent({required this.exercise});

  final Exercise exercise;

  Color _difficultyColor(String difficulty) {
    switch (difficulty) {
      case 'beginner':
        return AppColors.accentGreen;
      case 'advanced':
        return AppColors.accentRed;
      default:
        return AppColors.accentAmber;
    }
  }

  Future<void> _doItNow(BuildContext context, WidgetRef ref) async {
    try {
      final session = await ref.read(workoutRepositoryProvider).startSession(label: exercise.name);
      if (context.mounted) context.push(AppRoutes.workoutActive(session.id));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : 'Could not start workout. Please try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Container(
                height: 180,
                decoration: BoxDecoration(
                  color: AppColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(color: AppColors.outlineVariant),
                ),
                child: Stack(
                  children: [
                    const Center(child: Icon(Icons.fitness_center, size: 56, color: AppColors.textMuted)),
                    if (exercise.supportsCamera)
                      Positioned(
                        left: 12,
                        top: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceLowest,
                            borderRadius: BorderRadius.circular(AppRadius.chip),
                            border: Border.all(color: AppColors.outlineVariant),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.play_arrow, size: 14, color: AppColors.accentBlue),
                              Text(
                                'WATCH',
                                style: AppTypography.body(
                                  size: 11,
                                  weight: FontWeight.w700,
                                  color: AppColors.accentBlue,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (exercise.cameraView != null)
                      Positioned(right: 12, top: 12, child: BadgePill(exercise.cameraView!.toUpperCase())),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(exercise.name, style: AppTypography.display(size: 28)),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ...exercise.primaryMuscles.map((m) => MuscleTagChip(titleCaseMuscle(m))),
                  ...exercise.equipment.map((eq) => MuscleTagChip(titleCaseMuscle(eq))),
                  BadgePill(exercise.difficulty.toUpperCase(), color: _difficultyColor(exercise.difficulty)),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              if (exercise.executionSteps.isNotEmpty) ...[
                const SectionLabel('EXECUTION'),
                const SizedBox(height: AppSpacing.sm),
                ...exercise.executionSteps.asMap().entries.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(color: AppColors.surfaceHigh, shape: BoxShape.circle),
                          child: Text('${entry.key + 1}', style: AppTypography.mono(size: 11, weight: FontWeight.w700)),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(child: Text(entry.value, style: AppTypography.body(size: 14))),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
              if (exercise.proCues.isNotEmpty) ...[
                const SectionLabel('PRO CUES'),
                const SizedBox(height: AppSpacing.sm),
                ...exercise.proCues.map(
                  (cue) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.check_circle_outline, size: 18, color: AppColors.accentBlue),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(child: Text(cue, style: AppTypography.body(size: 14))),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
              if (exercise.mistakes.isNotEmpty) ...[
                const SectionLabel('MISTAKES'),
                const SizedBox(height: AppSpacing.sm),
                ...exercise.mistakes.map(
                  (mistake) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.surfaceBase,
                          border: Border.all(color: AppColors.outlineVariant),
                        ),
                        child: IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(width: 3, color: AppColors.accentRed),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.all(AppSpacing.md),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(mistake.title, style: AppTypography.body(size: 14, weight: FontWeight.w700)),
                                      const SizedBox(height: 4),
                                      Text(
                                        mistake.why,
                                        style: AppTypography.body(size: 13, color: AppColors.textSecondary),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        '→ ${mistake.fix}',
                                        style: AppTypography.body(
                                          size: 13,
                                          weight: FontWeight.w600,
                                          color: AppColors.accentGreen,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              const SectionLabel('YOUR HISTORY'),
              const SizedBox(height: AppSpacing.sm),
              _HistoryCard(exerciseId: exercise.id),
              const SizedBox(height: AppSpacing.lg),
              const SectionLabel('ALTERNATIVES'),
              const SizedBox(height: AppSpacing.sm),
              _AlternativesRow(exercise: exercise),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.md),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.outlineVariant)),
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('Open a day to add exercises for now.'))),
                  child: const Text('ADD TO PLAN'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: FilledButton(onPressed: () => _doItNow(context, ref), child: const Text('DO IT NOW')),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HistoryCard extends ConsumerWidget {
  const _HistoryCard({required this.exerciseId});

  final String exerciseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trend = ref.watch(strengthTrendProvider((exerciseId: exerciseId, period: 'year')));
    final records = ref.watch(personalRecordsProvider);
    final formTrend = ref.watch(formQualityTrendProvider((period: '3month', exerciseId: exerciseId)));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceBase,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: trend.when(
        data: (points) {
          final best = records.valueOrNull
              ?.where((r) => r.exerciseId == exerciseId)
              .fold<PersonalRecord?>(null, (acc, r) => acc == null || r.est1RmKg > acc.est1RmKg ? r : acc);

          if (points.isEmpty && best == null) {
            return Text(
              'No history yet for this exercise.',
              style: AppTypography.body(size: 13, color: AppColors.textMuted),
            );
          }

          final estOneRm = best?.est1RmKg ?? points.last.est1RmKg;
          final lastLogged = points.isNotEmpty ? points.last.date : null;

          Widget stat(String label, String value) => Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTypography.body(size: 12, color: AppColors.textSecondary)),
                const SizedBox(height: 2),
                Text(value, style: AppTypography.mono(size: 16, weight: FontWeight.w600)),
              ],
            ),
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  stat('BEST', best != null ? '${_trimKg(best.weightKg)} kg×${best.reps}' : '—'),
                  stat('EST. 1RM', '${estOneRm.round()} kg'),
                  formTrend.when(
                    data: (fPoints) => stat('FORM', fPoints.isEmpty ? '—' : '${fPoints.last.formScore.round()}/100'),
                    loading: () => stat('FORM', '…'),
                    error: (e, _) => e is ApiException && e.isPaymentRequired
                        ? Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('FORM', style: AppTypography.body(size: 12, color: AppColors.textSecondary)),
                                const SizedBox(height: 2),
                                const Icon(Icons.lock_outline, size: 16, color: AppColors.textMuted),
                              ],
                            ),
                          )
                        : stat('FORM', '—'),
                  ),
                ],
              ),
              if (points.length > 1) ...[
                const SizedBox(height: AppSpacing.md),
                Sparkline(values: points.map((p) => p.est1RmKg).toList(), width: double.infinity, height: 40),
              ] else if (lastLogged != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Last logged ${DateFormat('MMM d').format(lastLogged)}',
                  style: AppTypography.body(size: 12, color: AppColors.textMuted),
                ),
              ],
            ],
          );
        },
        loading: () => const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)),
        error: (_, _) =>
            Text('No history yet for this exercise.', style: AppTypography.body(size: 13, color: AppColors.textMuted)),
      ),
    );
  }
}

String _trimKg(double v) => v == v.truncateToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

/// Weighted overlap of primary/secondary muscles + equipment against the
/// exercise being viewed — an honest stand-in for the design's "% MATCH":
/// there's no curated similarity data, but this is genuinely derived from
/// the same `Exercise` fields the rest of the screen reads.
int _matchPercent(Exercise current, Exercise other) {
  double overlap(List<String> from, List<String> to) {
    if (from.isEmpty) return 0;
    return from.toSet().intersection(to.toSet()).length / from.length;
  }

  final score =
      overlap(current.primaryMuscles, other.primaryMuscles) * 0.6 +
      overlap(current.secondaryMuscles, other.secondaryMuscles) * 0.25 +
      overlap(current.equipment, other.equipment) * 0.15;
  return (score * 100).round();
}

class _AlternativesRow extends ConsumerWidget {
  const _AlternativesRow({required this.exercise});

  final Exercise exercise;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(exerciseLibraryControllerProvider);

    return library.when(
      data: (all) {
        final matches =
            all
                .where((e) => e.id != exercise.id)
                .map((e) => (exercise: e, percent: _matchPercent(exercise, e)))
                .where((m) => m.percent > 0)
                .toList()
              ..sort((a, b) => b.percent.compareTo(a.percent));

        if (matches.isEmpty) {
          return Text('No close alternatives yet.', style: AppTypography.body(size: 13, color: AppColors.textMuted));
        }

        return SizedBox(
          height: 140,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: matches.length > 5 ? 5 : matches.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
            itemBuilder: (context, i) {
              final match = matches[i];
              return _AlternativeCard(exercise: match.exercise, matchPercent: match.percent);
            },
          ),
        );
      },
      loading: () => const SizedBox(height: 140, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
      error: (_, _) =>
          Text('Could not load alternatives.', style: AppTypography.body(size: 13, color: AppColors.textMuted)),
    );
  }
}

class _AlternativeCard extends StatelessWidget {
  const _AlternativeCard({required this.exercise, required this.matchPercent});

  final Exercise exercise;
  final int matchPercent;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.card),
      onTap: () => context.push(AppRoutes.planExerciseDetail(exercise.id)),
      child: Container(
        width: 140,
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 80,
              width: double.infinity,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: AppColors.surfaceHighest,
                borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
              ),
              child: const Icon(Icons.fitness_center, size: 28, color: AppColors.textMuted),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    exercise.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.body(size: 13),
                  ),
                  const SizedBox(height: 4),
                  Text('$matchPercent% MATCH', style: AppTypography.mono(size: 11, color: AppColors.accentGreen)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
