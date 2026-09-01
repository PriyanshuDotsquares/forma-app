import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../onboarding_controller.dart';
import '../widgets/onboarding_step_scaffold.dart';

const _dayOptions = [2, 3, 4, 5, 6, 7];
const _sessionOptions = [30, 45, 60, 75, 90];

class Step5Frequency extends ConsumerWidget {
  const Step5Frequency({super.key, required this.onBack, required this.onContinue});

  final VoidCallback onBack;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final answers = ref.watch(onboardingControllerProvider);
    final notifier = ref.read(onboardingControllerProvider.notifier);
    final days = answers.daysPerWeek;
    final minutes = answers.sessionMinutes;
    final valid = days != null && minutes != null;

    final l10n = AppLocalizations.of(context)!;
    return OnboardingStepScaffold(
      stepNumber: 5,
      totalSteps: kOnboardingTotalSteps,
      title: l10n.step5Title,
      subtitle: 'Be realistic — a consistent 3 beats an ambitious 6.',
      onBack: onBack,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('DAYS PER WEEK'),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final d in _dayOptions)
                _Chip(label: '$d', selected: days == d, onTap: () => notifier.setDaysPerWeek(d)),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          const SectionLabel('SESSION LENGTH'),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final m in _sessionOptions)
                _Chip(label: '$m min', selected: minutes == m, onTap: () => notifier.setSessionMinutes(m)),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          if (valid) _WeeklyLoadCard(days: days, minutes: minutes),
        ],
      ),
      footer: SizedBox(
        width: double.infinity,
        child: FilledButton(onPressed: valid ? onContinue : null, child: Text(l10n.onboardingContinue)),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentBlue : AppColors.surfaceBase,
          borderRadius: BorderRadius.circular(AppRadius.chip),
          border: Border.all(color: selected ? AppColors.accentBlue : AppColors.outlineVariant),
        ),
        child: Text(
          label.toUpperCase(),
          style: AppTypography.body(
            size: 13,
            weight: FontWeight.w700,
            color: selected ? AppColors.accentBlueDark : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _WeeklyLoadCard extends StatelessWidget {
  const _WeeklyLoadCard({required this.days, required this.minutes});

  final int days;
  final int minutes;

  @override
  Widget build(BuildContext context) {
    final total = days * minutes;
    final hours = total ~/ 60;
    final mins = total % 60;
    final episodes = (total / 45).round().clamp(1, 99);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg, horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceBase,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('${hours}h', style: AppTypography.display(size: 40)),
              const SizedBox(width: AppSpacing.sm),
              Text('${mins.toString().padLeft(2, '0')}m', style: AppTypography.display(size: 40)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'PER WEEK',
            style: AppTypography.body(size: 11, weight: FontWeight.w700, color: AppColors.textMuted).copyWith(letterSpacing: 1.2),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'About the same as $episodes episode${episodes == 1 ? '' : 's'} of a show.',
            textAlign: TextAlign.center,
            style: AppTypography.body(size: 13, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
