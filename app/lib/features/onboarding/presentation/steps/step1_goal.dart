import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../onboarding_controller.dart';
import '../widgets/onboarding_option_card.dart';
import '../widgets/onboarding_step_scaffold.dart';

class _GoalOption {
  const _GoalOption(this.value, this.title, this.subtitle, this.icon);
  final String value;
  final String title;
  final String subtitle;
  final IconData icon;
}

const _goals = [
  _GoalOption('build_muscle', 'Build muscle', 'Add size with focused volume', Icons.fitness_center),
  _GoalOption('get_stronger', 'Get stronger', 'Heavier lifts on the big movements', Icons.trending_up),
  _GoalOption('lose_fat', 'Lose fat', 'Keep strength while leaning out', Icons.local_fire_department),
  _GoalOption('general_health', 'General health', 'Feel good, stay consistent', Icons.favorite),
  _GoalOption('athletic_performance', 'Athletic performance', 'Power, speed, and conditioning', Icons.speed),
  _GoalOption('move_better', 'Move better', 'Mobility and pain-free range', Icons.spa),
];

class Step1Goal extends ConsumerWidget {
  const Step1Goal({super.key, required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final answers = ref.watch(onboardingControllerProvider);
    final notifier = ref.read(onboardingControllerProvider.notifier);

    final l10n = AppLocalizations.of(context)!;
    return OnboardingStepScaffold(
      stepNumber: 1,
      totalSteps: kOnboardingTotalSteps,
      title: l10n.step1Title,
      subtitle: 'You can change this any time.',
      child: Column(
        children: [
          for (final goal in _goals) ...[
            OnboardingOptionCard(
              title: goal.title,
              subtitle: goal.subtitle,
              icon: goal.icon,
              selected: answers.goal == goal.value,
              onTap: () => notifier.setGoal(goal.value),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ),
      footer: SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: answers.goal != null ? onContinue : null,
          child: Text(l10n.onboardingContinue),
        ),
      ),
    );
  }
}
