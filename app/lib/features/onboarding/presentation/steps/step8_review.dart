import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../onboarding_controller.dart';
import '../widgets/onboarding_step_scaffold.dart';

class Step8Review extends ConsumerWidget {
  const Step8Review({super.key, required this.onBack, required this.onEditStep, required this.onBuildPlan});

  final VoidCallback onBack;
  final ValueChanged<int> onEditStep;
  final VoidCallback onBuildPlan;

  String _youLine(OnboardingAnswers answers) {
    final parts = <String>[];
    final age = answers.ageYears;
    if (age != null) parts.add('$age yrs');
    if (answers.heightCm != null) {
      parts.add(
        answers.units == 'imperial' ? '${(answers.heightCm! / 2.54).round()} in' : '${answers.heightCm!.round()} cm',
      );
    }
    if (answers.weightKg != null) {
      parts.add(
        answers.units == 'imperial' ? '${(answers.weightKg! * 2.20462).round()} lb' : '${answers.weightKg!.round()} kg',
      );
    }
    return parts.isEmpty ? 'Not set' : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final answers = ref.watch(onboardingControllerProvider);

    final rows = <_ReviewRow>[
      _ReviewRow('GOAL', goalLabel(answers.goal), 0),
      _ReviewRow('EXPERIENCE', experienceLevelLabel(answers.experienceLevel), 1),
      _ReviewRow('YOU', _youLine(answers), 2),
      _ReviewRow(
        'FREQUENCY',
        answers.daysPerWeek != null && answers.sessionMinutes != null
            ? '${answers.daysPerWeek}x / week · ${answers.sessionMinutes} min'
            : 'Not set',
        5,
      ),
      _ReviewRow('SPLIT', splitPreferenceLabel(answers.splitPreference, daysPerWeek: answers.daysPerWeek), 6),
      _ReviewRow('WHERE', gymLocationLabel(answers.gymLocation), 3),
      _ReviewRow(
        'EQUIPMENT',
        answers.equipmentItems.isEmpty ? 'None selected' : '${answers.equipmentItems.length} item${answers.equipmentItems.length == 1 ? '' : 's'}',
        4,
      ),
      _ReviewRow(
        'LIMITATIONS',
        answers.injuries.isEmpty ? 'None' : '${answers.injuries.length} flagged',
        7,
      ),
    ];

    final l10n = AppLocalizations.of(context)!;
    return OnboardingStepScaffold(
      stepNumber: 8,
      totalSteps: kOnboardingTotalSteps,
      title: l10n.step8Title,
      subtitle: 'Review your training parameters before we calculate your optimal load path.',
      onBack: onBack,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.surfaceBase,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.outlineVariant),
        ),
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              _ReviewRowTile(row: rows[i], onEdit: () => onEditStep(rows[i].targetPage)),
              if (i != rows.length - 1) const Divider(height: 1),
            ],
          ],
        ),
      ),
      footer: SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: onBuildPlan,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.auto_awesome, size: 16),
              const SizedBox(width: AppSpacing.xs),
              Text(l10n.onboardingBuildMyPlan),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewRow {
  const _ReviewRow(this.label, this.value, this.targetPage);
  final String label;
  final String value;
  final int targetPage;
}

class _ReviewRowTile extends StatelessWidget {
  const _ReviewRowTile({required this.row, required this.onEdit});

  final _ReviewRow row;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onEdit,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
        child: Row(
          children: [
            SizedBox(
              width: 96,
              child: Text(
                row.label,
                style: AppTypography.body(size: 11, weight: FontWeight.w700, color: AppColors.textMuted).copyWith(letterSpacing: 1.0),
              ),
            ),
            Expanded(
              child: Text(
                row.value,
                textAlign: TextAlign.right,
                style: AppTypography.body(size: 14, weight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            const Icon(Icons.edit_outlined, size: 16, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}
