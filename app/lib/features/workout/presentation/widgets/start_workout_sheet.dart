import 'package:flutter/material.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../programs/domain/program.dart';

/// What the user picked in [showStartWorkoutSheet].
class StartWorkoutChoice {
  const StartWorkoutChoice.day(this.day) : isFreestyle = false;
  const StartWorkoutChoice.freestyle() : day = null, isFreestyle = true;

  final ProgramDay? day;
  final bool isFreestyle;
}

/// Lets the user pick today's program day (if they have an active program
/// with trainable days) or go freestyle with no plan. Returns `null` if
/// dismissed without a choice.
Future<StartWorkoutChoice?> showStartWorkoutSheet(BuildContext context, {required Program program}) {
  final trainableDays = program.days.where((d) => !d.isRest).toList()..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));

  return showModalBottomSheet<StartWorkoutChoice>(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('START A WORKOUT', style: AppTypography.display(size: 18)),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Pick a day from ${program.name}, or train without a plan.',
                style: AppTypography.body(size: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.lg),
              ...trainableDays.map(
                (day) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: _ChoiceCard(
                    title: day.label,
                    subtitle: [
                      if (day.muscleTags.isNotEmpty) day.muscleTags.join(' · '),
                      if (day.estimatedMinutes != null) '~${day.estimatedMinutes} min',
                    ].join('  ·  '),
                    icon: Icons.calendar_today_outlined,
                    onTap: () => Navigator.of(context).pop(StartWorkoutChoice.day(day)),
                  ),
                ),
              ),
              _ChoiceCard(
                title: 'Freestyle',
                subtitle: 'No plan — add exercises as you go.',
                icon: Icons.bolt_outlined,
                onTap: () => Navigator.of(context).pop(const StartWorkoutChoice.freestyle()),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({required this.title, required this.subtitle, required this.icon, required this.onTap});

  final String title;
  final String subtitle;
  final IconData icon;
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
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppRadius.card), border: Border.all(color: AppColors.outlineVariant)),
          child: Row(
            children: [
              Icon(icon, color: AppColors.accentBlue),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTypography.body(size: 15, weight: FontWeight.w700)),
                    if (subtitle.isNotEmpty) Text(subtitle, style: AppTypography.body(size: 12, color: AppColors.textSecondary)),
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
