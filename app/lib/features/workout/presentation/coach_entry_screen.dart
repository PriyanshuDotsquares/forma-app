import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/app_router.dart';
import '../../programs/domain/program.dart';
import '../../programs/presentation/programs_providers.dart';
import '../domain/workout_session.dart';
import 'widgets/start_workout_sheet.dart';
import 'workout_providers.dart';

final _activeProgramForCoachProvider = FutureProvider.autoDispose<Program?>(
  (ref) => ref.watch(programsRepositoryProvider).getActiveProgram(),
);

/// The COACH tab's landing screen: start a new workout (optionally against
/// today's program day), or resume one already in progress.
class CoachEntryScreen extends ConsumerWidget {
  const CoachEntryScreen({super.key});

  Future<void> _startWorkout(BuildContext context, WidgetRef ref) async {
    Program? program;
    try {
      program = await ref.read(_activeProgramForCoachProvider.future);
    } catch (_) {
      program = null;
    }
    if (!context.mounted) return;

    String? programDayId;
    var label = 'Freestyle';
    if (program != null && program.days.any((d) => !d.isRest)) {
      final choice = await showStartWorkoutSheet(context, program: program);
      if (choice == null) return; // sheet dismissed without a choice
      if (!choice.isFreestyle && choice.day != null) {
        programDayId = choice.day!.id;
        label = choice.day!.label;
      }
    }
    if (!context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final session = await ref.read(workoutRepositoryProvider).startSession(programDayId: programDayId, label: label);
      ref.invalidate(sessionListProvider);
      if (!context.mounted) return;
      context.push(AppRoutes.workoutActive(session.id));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(sessionListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('COACH')),
      body: SafeArea(
        child: sessionsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: FormaEmptyState(
                icon: Icons.wifi_off,
                title: "That didn't work.",
                message: error is ApiException ? error.message : 'Could not load your sessions.',
                primaryLabel: 'RETRY',
                onPrimary: () => ref.invalidate(sessionListProvider),
              ),
            ),
          ),
          data: (sessions) {
            if (sessions.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: FormaEmptyState(
                    icon: Icons.fitness_center,
                    eyebrow: 'NO HISTORY',
                    title: 'Nothing logged yet.',
                    message: 'Your first session will show up here.',
                    primaryLabel: 'START A WORKOUT',
                    onPrimary: () => _startWorkout(context, ref),
                  ),
                ),
              );
            }

            WorkoutSession? activeSession;
            for (final session in sessions) {
              if (!session.isFinished) {
                activeSession = session;
                break;
              }
            }

            return ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                Text('Coach a set.', style: AppTypography.display(size: 30)),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Point the camera and FORMA counts your reps, tracks range of motion, and calls out fixes as you lift.',
                  style: AppTypography.body(size: 14, color: AppColors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.xl),
                if (activeSession != null)
                  _ResumeCard(session: activeSession, onTap: () => context.push(AppRoutes.workoutActive(activeSession!.id)))
                else
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(onPressed: () => _startWorkout(context, ref), child: const Text('START A WORKOUT')),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ResumeCard extends StatelessWidget {
  const _ResumeCard({required this.session, required this.onTap});

  final WorkoutSession session;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceBase,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppRadius.card), border: Border.all(color: AppColors.accentBlue)),
          child: Row(
            children: [
              const Icon(Icons.play_circle_outline, color: AppColors.accentBlue, size: 32),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionLabel('RESUME WORKOUT'),
                    const SizedBox(height: 2),
                    Text(session.label, style: AppTypography.body(size: 16, weight: FontWeight.w700)),
                    Text('${session.sets.length} sets logged so far', style: AppTypography.body(size: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
