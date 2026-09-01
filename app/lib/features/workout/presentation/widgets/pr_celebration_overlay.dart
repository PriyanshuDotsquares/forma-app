import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/design_system/design_system.dart';

/// Shows the full-bleed PR celebration after a set comes back with
/// `WorkoutSet.isPr == true`. [previousWeightKg]/[previousReps] (when known)
/// are the prior best for this exercise — omitted gracefully together when
/// there's nothing to compare against, never shown partially.
Future<void> showPrCelebration(
  BuildContext context, {
  required String exerciseName,
  required double weightKg,
  required int reps,
  double? previousWeightKg,
  int? previousReps,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: AppColors.surfaceLowest,
    useSafeArea: false,
    builder: (context) => _PrCelebrationScreen(
      exerciseName: exerciseName,
      weightKg: weightKg,
      reps: reps,
      previousWeightKg: previousWeightKg,
      previousReps: previousReps,
    ),
  );
}

class _PrCelebrationScreen extends StatelessWidget {
  const _PrCelebrationScreen({
    required this.exerciseName,
    required this.weightKg,
    required this.reps,
    this.previousWeightKg,
    this.previousReps,
  });

  final String exerciseName;
  final double weightKg;
  final int reps;
  final double? previousWeightKg;
  final int? previousReps;

  static String _trim(double v) => v == v.truncateToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  double? get _deltaKg => previousWeightKg == null ? null : weightKg - previousWeightKg!;

  String get _shareText {
    final delta = _deltaKg != null && _deltaKg! > 0 ? ' (+${_trim(_deltaKg!)}kg)' : '';
    return 'New PR: $exerciseName ${_trim(weightKg)}kg × $reps$delta via FORMA';
  }

  @override
  Widget build(BuildContext context) {
    final hasComparison = previousWeightKg != null && previousReps != null;

    return Dialog(
      insetPadding: EdgeInsets.zero,
      backgroundColor: AppColors.surfaceLowest,
      shape: const RoundedRectangleBorder(),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topCenter,
            radius: 1.1,
            colors: [AppColors.accentRed.withValues(alpha: 0.10), AppColors.surfaceLowest],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          exerciseName.toUpperCase(),
                          textAlign: TextAlign.center,
                          style: AppTypography.display(size: 34).copyWith(letterSpacing: -1),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              _trim(weightKg),
                              style: AppTypography.mono(size: 72, weight: FontWeight.w600, color: AppColors.accentRed).copyWith(letterSpacing: -2),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Text('kg × $reps', style: AppTypography.mono(size: 24, color: AppColors.textSecondary)),
                          ],
                        ),
                        if (hasComparison) ...[
                          const SizedBox(height: AppSpacing.sm),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${_trim(previousWeightKg!)} kg × $previousReps',
                                style: AppTypography.mono(size: 14, color: AppColors.textMuted).copyWith(decoration: TextDecoration.lineThrough),
                              ),
                              if (_deltaKg != null && _deltaKg! > 0) ...[
                                const SizedBox(width: AppSpacing.sm),
                                Icon(Icons.arrow_upward, size: 12, color: AppColors.accentRed),
                                Text('+${_trim(_deltaKg!)} kg', style: AppTypography.mono(size: 14, weight: FontWeight.w600, color: AppColors.accentRed)),
                              ],
                            ],
                          ),
                        ],
                        const SizedBox(height: AppSpacing.xl),
                        Text(
                          'New personal record.',
                          textAlign: TextAlign.center,
                          style: AppTypography.body(size: 16, color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        const _BarbellGraphic(),
                      ],
                    ),
                  ),
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.lg),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [AppColors.surfaceBase, AppColors.surfaceBase.withValues(alpha: 0)],
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          SharePlus.instance.share(ShareParams(text: _shareText));
                        },
                        icon: const Icon(Icons.ios_share, size: 16),
                        label: const Text('SHARE'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('NICE'))),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Purely decorative bar+plates graphic — a schematic reading (flat, no
/// gradients on the plates themselves) consistent with this design system's
/// "no drop shadows / no glassmorphism" rule; only the new-PR plates get the
/// red accent glow.
class _BarbellGraphic extends StatelessWidget {
  const _BarbellGraphic();

  @override
  Widget build(BuildContext context) {
    Widget plate({required double height, required double width, Color? color, bool glow = false}) {
      return Container(
        width: width,
        height: height,
        margin: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(
          color: color ?? AppColors.surfaceHighest,
          borderRadius: BorderRadius.circular(2),
          boxShadow: glow ? [BoxShadow(color: AppColors.accentRed.withValues(alpha: 0.4), blurRadius: 8)] : null,
        ),
      );
    }

    final sidePlates = [
      plate(height: 48, width: 12),
      plate(height: 48, width: 12),
      plate(height: 36, width: 8),
      plate(height: 40, width: 10, color: AppColors.accentRed, glow: true),
    ];

    return SizedBox(
      width: 260,
      height: 60,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(width: double.infinity, height: 8, decoration: BoxDecoration(color: AppColors.surfaceHigh, borderRadius: BorderRadius.circular(2))),
          Container(width: 12, height: 16, decoration: BoxDecoration(color: AppColors.outline, borderRadius: BorderRadius.circular(1))),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(children: sidePlates),
              Row(children: sidePlates.reversed.toList()),
            ],
          ),
        ],
      ),
    );
  }
}
