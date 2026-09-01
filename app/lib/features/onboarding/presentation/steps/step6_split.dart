import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../onboarding_controller.dart';
import '../widgets/onboarding_option_card.dart';
import '../widgets/onboarding_step_scaffold.dart';

class _SplitOption {
  const _SplitOption(this.value, this.title, this.subtitle, {this.disabledReason});
  final String value;
  final String title;
  final String subtitle;
  final String? disabledReason;
}

const _splits = [
  _SplitOption('upper_lower', 'Upper/Lower', 'Alternate upper and lower body'),
  _SplitOption('push_pull_legs', 'Push/Pull/Legs', 'Three rotating sessions', disabledReason: 'Needs 3 or 6 days'),
  _SplitOption('full_body', 'Full body', 'Train everything each session'),
  _SplitOption('body_part', 'Body part', 'One or two muscle groups per day', disabledReason: 'Needs 5+ days'),
];

bool _fitsDays(String value, int? days) {
  if (days == null) return true;
  switch (value) {
    case 'push_pull_legs':
      return days == 3 || days == 6;
    case 'body_part':
      return days >= 5;
    default:
      return true;
  }
}

/// A 7-slot Mon-Sun preview of which days a split would train, purely
/// illustrative (the real generator decides the actual schedule). Splits
/// that pair two sessions back-to-back (Upper/Lower) fill in pairs with a
/// rest day between; single-session splits (Full body) spread evenly.
List<bool>? _weekPattern(String value, int days) {
  final pattern = List.filled(7, false);
  switch (value) {
    case 'upper_lower':
      var i = 0;
      var placed = 0;
      while (placed < days && i < 7) {
        pattern[i] = true;
        placed++;
        if (placed < days && i + 1 < 7) {
          pattern[i + 1] = true;
          placed++;
        }
        i += 3;
      }
      return pattern;
    case 'full_body':
      for (var k = 0; k < days; k++) {
        final idx = ((2 * k + 1) * 7) ~/ (2 * days);
        if (idx < 7) pattern[idx] = true;
      }
      return pattern;
    default:
      return null;
  }
}

class _WeekPatternDots extends StatelessWidget {
  const _WeekPatternDots({required this.pattern});

  final List<bool> pattern;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final on in pattern)
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(left: 3),
            decoration: BoxDecoration(
              color: on ? AppColors.accentBlue : AppColors.surfaceHighest,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
      ],
    );
  }
}

class Step6Split extends ConsumerWidget {
  const Step6Split({super.key, required this.onBack, required this.onContinue});

  final VoidCallback onBack;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final answers = ref.watch(onboardingControllerProvider);
    final notifier = ref.read(onboardingControllerProvider.notifier);
    final days = answers.daysPerWeek ?? 3;

    final l10n = AppLocalizations.of(context)!;
    return OnboardingStepScaffold(
      stepNumber: 6,
      totalSteps: kOnboardingTotalSteps,
      title: l10n.step6Title,
      subtitle: 'Based on your $days-day commitment.',
      onBack: onBack,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OnboardingOptionCard(
            title: 'Let FORMA decide',
            subtitle: "We'll pick the best structure for $days days and your goal, then adjust as we learn how you train.",
            badge: 'RECOMMENDED',
            selected: answers.splitPreference == 'auto',
            onTap: () => notifier.setSplitPreference('auto'),
          ),
          const SizedBox(height: AppSpacing.lg),
          const SectionLabel('OR CHOOSE YOUR OWN'),
          const SizedBox(height: AppSpacing.sm),
          for (final split in _splits) ...[
            OnboardingOptionCard(
              title: split.title,
              subtitle: split.subtitle,
              selected: answers.splitPreference == split.value,
              enabled: _fitsDays(split.value, answers.daysPerWeek),
              disabledReason: split.disabledReason,
              trailing: answers.splitPreference == split.value
                  ? null
                  : switch (_weekPattern(split.value, days)) {
                      final pattern? => _WeekPatternDots(pattern: pattern),
                      null => null,
                    },
              onTap: () => notifier.setSplitPreference(split.value),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ),
      footer: SizedBox(
        width: double.infinity,
        child: FilledButton(onPressed: onContinue, child: Text(l10n.onboardingContinue)),
      ),
    );
  }
}
