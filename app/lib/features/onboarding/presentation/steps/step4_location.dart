import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../onboarding_controller.dart';
import '../widgets/onboarding_step_scaffold.dart';
import 'equipment_catalog.dart';

class _LocationOption {
  const _LocationOption(this.value, this.title, this.subtitle, this.icon);
  final String value;
  final String title;
  final String subtitle;
  final IconData icon;
}

const _locations = [
  _LocationOption('commercial_gym', 'Commercial gym', 'Full racks, machines, and free weights', Icons.chair_alt),
  _LocationOption('home_gym', 'Home gym', 'Your own weights and gear', Icons.home_outlined),
  _LocationOption('bodyweight', 'Bodyweight only', 'No equipment needed', Icons.accessibility_new),
  _LocationOption('mixed', 'A mix', 'Gym some days, home other days', Icons.shuffle),
];

class Step4Location extends ConsumerWidget {
  const Step4Location({super.key, required this.onBack, required this.onContinue});

  final VoidCallback onBack;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final answers = ref.watch(onboardingControllerProvider);
    final notifier = ref.read(onboardingControllerProvider.notifier);

    final l10n = AppLocalizations.of(context)!;
    return OnboardingStepScaffold(
      stepNumber: 4,
      totalSteps: kOnboardingTotalSteps,
      title: l10n.step4LocationTitle,
      subtitle: "This sets your starting equipment list — you'll fine-tune it next.",
      onBack: onBack,
      child: Column(
        children: [
          for (var i = 0; i < _locations.length; i += 2) ...[
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _LocationCard(
                      option: _locations[i],
                      itemCountLabel: _itemCountLabel(_locations[i].value),
                      selected: answers.gymLocation == _locations[i].value,
                      onTap: () => notifier.setGymLocation(_locations[i].value),
                    ),
                  ),
                  if (i + 1 < _locations.length) ...[
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _LocationCard(
                        option: _locations[i + 1],
                        itemCountLabel: _itemCountLabel(_locations[i + 1].value),
                        selected: answers.gymLocation == _locations[i + 1].value,
                        onTap: () => notifier.setGymLocation(_locations[i + 1].value),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (i + 2 < _locations.length) const SizedBox(height: AppSpacing.sm),
          ],
          const SizedBox(height: AppSpacing.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline, size: 16, color: AppColors.textMuted),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Training somewhere new later? You can change this any time in Settings.',
                  style: AppTypography.body(size: 13, color: AppColors.textMuted),
                ),
              ),
            ],
          ),
        ],
      ),
      footer: SizedBox(
        width: double.infinity,
        child: FilledButton(onPressed: onContinue, child: Text(l10n.onboardingContinue)),
      ),
    );
  }

  String _itemCountLabel(String location) {
    if (location == 'mixed') return "You'll pick";
    final count = EquipmentCatalog.presetFor(location).length;
    return '$count item${count == 1 ? '' : 's'}';
  }
}

class _LocationCard extends StatelessWidget {
  const _LocationCard({required this.option, required this.itemCountLabel, required this.selected, required this.onTap});

  final _LocationOption option;
  final String itemCountLabel;
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
        child: Stack(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: fillColor,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: borderColor, width: selected ? 1.5 : 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(option.icon, size: 24, color: selected ? AppColors.accentBlue : AppColors.textSecondary),
                  const SizedBox(height: AppSpacing.sm),
                  Text(option.title, style: AppTypography.body(size: 15, weight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    option.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.body(size: 12, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadius.chip),
                      border: Border.all(color: AppColors.outlineVariant),
                    ),
                    child: Text(itemCountLabel, style: AppTypography.mono(size: 11, weight: FontWeight.w600, color: AppColors.textSecondary)),
                  ),
                ],
              ),
            ),
            if (selected)
              Positioned(
                top: AppSpacing.sm,
                right: AppSpacing.sm,
                child: Container(
                  width: 20,
                  height: 20,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(color: AppColors.accentBlue, shape: BoxShape.circle),
                  child: const Icon(Icons.check, size: 13, color: AppColors.accentBlueDark),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
