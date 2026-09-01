import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../onboarding_controller.dart';
import '../widgets/onboarding_step_scaffold.dart';

class _ExperienceOption {
  const _ExperienceOption(this.value, this.title, this.subtitle, this.dots);
  final String value;
  final String title;
  final String subtitle;
  final int dots;
}

const _levels = [
  _ExperienceOption('new', 'New to lifting', "I haven't trained with weights, or it's been years.", 1),
  _ExperienceOption('machines', 'I know the machines', "I'm comfortable on machines, less so with free weights.", 2),
  _ExperienceOption('free_weights', 'Free weights, confidently', 'I squat, bench, and deadlift with a barbell.', 3),
  _ExperienceOption('programs_own', 'I program my own training', 'I track my lifts and plan my own progression.', 4),
];

class Step2Experience extends ConsumerWidget {
  const Step2Experience({super.key, required this.onBack, required this.onContinue});

  final VoidCallback onBack;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final answers = ref.watch(onboardingControllerProvider);
    final notifier = ref.read(onboardingControllerProvider.notifier);

    final l10n = AppLocalizations.of(context)!;
    return OnboardingStepScaffold(
      stepNumber: 2,
      totalSteps: kOnboardingTotalSteps,
      title: l10n.step2Title,
      subtitle: 'Pick the one that sounds most like you.',
      onBack: onBack,
      child: Column(
        children: [
          for (final level in _levels) ...[
            _ExperienceCard(
              option: level,
              selected: answers.experienceLevel == level.value,
              onTap: () => notifier.setExperienceLevel(level.value),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ),
      footer: SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: answers.experienceLevel != null ? onContinue : null,
          child: Text(l10n.onboardingContinue),
        ),
      ),
    );
  }
}

class _ExperienceCard extends StatelessWidget {
  const _ExperienceCard({required this.option, required this.selected, required this.onTap});

  final _ExperienceOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = selected ? AppColors.accentBlue : AppColors.outlineVariant;
    final fillColor = selected ? AppColors.accentBlue.withValues(alpha: 0.12) : AppColors.surfaceBase;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: fillColor,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: borderColor, width: selected ? 1.5 : 1),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(option.title, style: AppTypography.body(size: 15, weight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(option.subtitle, style: AppTypography.body(size: 13, color: AppColors.textSecondary)),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: List.generate(4, (i) {
                        final filled = i < option.dots;
                        return Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(right: 4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: filled ? AppColors.accentBlue : AppColors.surfaceHighest,
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Icon(
                selected ? Icons.check_circle : Icons.radio_button_unchecked,
                color: selected ? AppColors.accentBlue : AppColors.outline,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
