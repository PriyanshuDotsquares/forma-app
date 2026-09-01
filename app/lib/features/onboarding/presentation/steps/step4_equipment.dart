import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../onboarding_controller.dart';
import '../widgets/onboarding_step_scaffold.dart';
import 'equipment_catalog.dart';

class Step4Equipment extends ConsumerWidget {
  const Step4Equipment({super.key, required this.onBack, required this.onContinue});

  final VoidCallback onBack;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final answers = ref.watch(onboardingControllerProvider);
    final notifier = ref.read(onboardingControllerProvider.notifier);
    final selected = answers.equipmentItems;

    final l10n = AppLocalizations.of(context)!;
    return OnboardingStepScaffold(
      stepNumber: 4,
      totalSteps: kOnboardingTotalSteps,
      title: l10n.step4EquipmentTitle,
      subtitle: "We've pre-selected a typical ${_locationNoun(answers.gymLocation)}. Uncheck anything you don't have.",
      onBack: onBack,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.surfaceBase,
              borderRadius: BorderRadius.circular(AppRadius.chip),
              border: Border.all(color: AppColors.outlineVariant),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.info_outline, size: 16, color: AppColors.accentBlue),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      '${selected.length} selected',
                      style: AppTypography.body(size: 13, weight: FontWeight.w700, color: AppColors.textSecondary),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: selected.isEmpty ? null : notifier.deselectAllEquipment,
                  child: const Text('DESELECT ALL'),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          for (final section in EquipmentCatalog.sections) ...[
            _SectionBlock(section: section, selected: selected, notifier: notifier),
            const SizedBox(height: AppSpacing.lg),
          ],
        ],
      ),
      footer: SizedBox(
        width: double.infinity,
        child: FilledButton(onPressed: onContinue, child: Text(l10n.onboardingContinue)),
      ),
    );
  }

  String _locationNoun(String gymLocation) {
    switch (gymLocation) {
      case 'home_gym':
        return 'home gym';
      case 'bodyweight':
        return 'bodyweight setup';
      case 'mixed':
        return 'mixed setup';
      case 'commercial_gym':
      default:
        return 'commercial gym';
    }
  }
}

class _SectionBlock extends StatelessWidget {
  const _SectionBlock({required this.section, required this.selected, required this.notifier});

  final EquipmentSection section;
  final Set<String> selected;
  final OnboardingController notifier;

  @override
  Widget build(BuildContext context) {
    final allSelected = section.items.every((item) => selected.contains(item.id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(
          section.title,
          trailing: TextButton(
            onPressed: () => notifier.setSectionSelected(section, !allSelected),
            child: Text(allSelected ? 'NONE' : 'ALL'),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        LayoutBuilder(
          builder: (context, constraints) {
            const columns = 3;
            const gap = AppSpacing.sm;
            final cardWidth = (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final item in section.items)
                  SizedBox(
                    width: cardWidth,
                    child: _EquipmentCard(
                      item: item,
                      selected: selected.contains(item.id),
                      onTap: () => notifier.toggleEquipmentItem(item.id),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _EquipmentCard extends StatelessWidget {
  const _EquipmentCard({required this.item, required this.selected, required this.onTap});

  final EquipmentItem item;
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
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md, horizontal: AppSpacing.xs),
              decoration: BoxDecoration(
                color: fillColor,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: borderColor, width: selected ? 1.5 : 1),
              ),
              child: Column(
                children: [
                  Icon(item.icon, size: 26, color: selected ? AppColors.accentBlue : AppColors.textSecondary),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    item.label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.body(size: 13, weight: FontWeight.w600),
                  ),
                  if (item.subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.subtitle!,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.body(size: 10, color: AppColors.textMuted),
                    ),
                  ],
                ],
              ),
            ),
            Positioned(
              top: 6,
              right: 6,
              child: Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                size: 16,
                color: selected ? AppColors.accentBlue : AppColors.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
