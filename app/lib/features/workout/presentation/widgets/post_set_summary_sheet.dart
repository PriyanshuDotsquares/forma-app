import 'package:flutter/material.dart';

import '../../../../core/design_system/design_system.dart';
import '../../domain/workout_session.dart';

/// Shows the post-set summary sheet: reps/depth/form for the set just
/// logged, an optional "ONE THING TO FIX" coaching card, an optional
/// "VS LAST TIME" comparison against the same set index from the most
/// recent other finished session with the same workout label, and a
/// primary button that simply pops the sheet — the caller (already holding
/// the logged set) decides whether to proceed to the rest timer or finish
/// the workout.
Future<void> showPostSetSummarySheet(
  BuildContext context, {
  required int setIndex,
  required String exerciseName,
  required WorkoutSet loggedSet,
  String? coachingNote,
  WorkoutSet? baselineSet,
  required bool isLastSetOfWorkout,
  int? goodReps,
  int? badReps,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    builder: (context) => PostSetSummarySheet(
      setIndex: setIndex,
      exerciseName: exerciseName,
      loggedSet: loggedSet,
      coachingNote: coachingNote,
      baselineSet: baselineSet,
      isLastSetOfWorkout: isLastSetOfWorkout,
      goodReps: goodReps,
      badReps: badReps,
    ),
  );
}

Color _qualityColor(int score) {
  if (score >= 80) return AppColors.accentGreen;
  if (score >= 60) return AppColors.accentAmber;
  return AppColors.accentRed;
}

String _qualityCaption(int score) {
  if (score >= 80) return 'Solid';
  if (score >= 60) return 'Good';
  return 'Needs work';
}

String _qualityHeadline(int? formScore) {
  if (formScore == null) return 'Set logged.';
  if (formScore >= 80) return 'Solid set.';
  if (formScore >= 60) return 'Good set.';
  return 'Needs work.';
}

class PostSetSummarySheet extends StatelessWidget {
  const PostSetSummarySheet({
    super.key,
    required this.setIndex,
    required this.exerciseName,
    required this.loggedSet,
    this.coachingNote,
    this.baselineSet,
    required this.isLastSetOfWorkout,
    this.goodReps,
    this.badReps,
  });

  final int setIndex;
  final String exerciseName;
  final WorkoutSet loggedSet;
  final String? coachingNote;
  final WorkoutSet? baselineSet;
  final bool isLastSetOfWorkout;

  /// Per-rep good/bad breakdown from live camera coaching (null when the
  /// set wasn't camera-tracked, e.g. logged manually).
  final int? goodReps;
  final int? badReps;

  List<_ComparisonRow> _comparisonRows() {
    final baseline = baselineSet;
    if (baseline == null) return const [];

    _ComparisonRow? row(String label, num? oldValue, num? newValue, String Function(num) fmt) {
      if (oldValue == null || newValue == null) return null;
      return _ComparisonRow(
        label: label,
        oldText: fmt(oldValue),
        newText: fmt(newValue),
        improved: newValue > oldValue,
        worsened: newValue < oldValue,
      );
    }

    return [
      row('Reps', baseline.actualReps, loggedSet.actualReps, (v) => v.toStringAsFixed(0)),
      row('Depth', baseline.depthPct, loggedSet.depthPct, (v) => '${v.round()}%'),
      row('Form', baseline.formScore, loggedSet.formScore, (v) => v.toStringAsFixed(0)),
    ].whereType<_ComparisonRow>().toList();
  }

  @override
  Widget build(BuildContext context) {
    final formScore = loggedSet.formScore;
    final depthPct = loggedSet.depthPct;
    final comparisonRows = _comparisonRows();

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionLabel('Set ${setIndex + 1} · $exerciseName'),
            const SizedBox(height: AppSpacing.xs),
            Text(_qualityHeadline(formScore), style: AppTypography.display(size: 26)),
            const SizedBox(height: AppSpacing.lg),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _MetricCard(
                      label: 'Reps',
                      value: loggedSet.actualReps?.toString() ?? '—',
                      footer: GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Text('Edit', style: AppTypography.body(size: 12, weight: FontWeight.w600, color: AppColors.accentBlue)),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _MetricCard(
                      label: 'Avg Depth',
                      value: depthPct == null ? '—' : '${depthPct.round()}%',
                      valueColor: depthPct == null ? null : _qualityColor(depthPct.round()),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _MetricCard(
                      label: 'Form',
                      value: formScore?.toString() ?? '—',
                      valueColor: formScore == null ? null : _qualityColor(formScore),
                      footer: formScore == null
                          ? null
                          : Text(
                              _qualityCaption(formScore),
                              style: AppTypography.body(size: 12, weight: FontWeight.w600, color: _qualityColor(formScore)),
                            ),
                    ),
                  ),
                ],
              ),
            ),
            if (goodReps != null && badReps != null && (goodReps! + badReps!) > 0) ...[
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  const Icon(Icons.check_circle, size: 14, color: AppColors.accentGreen),
                  const SizedBox(width: 4),
                  Text(
                    '$goodReps good',
                    style: AppTypography.body(size: 12, weight: FontWeight.w600, color: AppColors.textSecondary),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  const Icon(Icons.error, size: 14, color: AppColors.accentRed),
                  const SizedBox(width: 4),
                  Text(
                    '$badReps needs work',
                    style: AppTypography.body(size: 12, weight: FontWeight.w600, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ],
            if (coachingNote != null) ...[
              const SizedBox(height: AppSpacing.md),
              InfoBanner(
                title: 'ONE THING TO FIX',
                body: coachingNote,
                icon: Icons.warning_amber_rounded,
                accent: AppColors.accentAmber,
              ),
            ],
            if (comparisonRows.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.surfaceBase,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(color: AppColors.outlineVariant),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionLabel('VS LAST TIME'),
                    const SizedBox(height: AppSpacing.sm),
                    ...comparisonRows,
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(isLastSetOfWorkout ? 'Save set · finish workout' : 'Save set · start rest'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value, this.valueColor, this.footer});

  final String label;
  final String value;
  final Color? valueColor;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceBase,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: AppTypography.body(size: 11, weight: FontWeight.w700, color: AppColors.textMuted).copyWith(letterSpacing: 1.0),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(value, style: AppTypography.mono(size: 24, weight: FontWeight.w700, color: valueColor)),
            ],
          ),
          if (footer != null) ...[const SizedBox(height: AppSpacing.xs), footer!],
        ],
      ),
    );
  }
}

class _ComparisonRow extends StatelessWidget {
  const _ComparisonRow({required this.label, required this.oldText, required this.newText, required this.improved, required this.worsened});

  final String label;
  final String oldText;
  final String newText;
  final bool improved;
  final bool worsened;

  @override
  Widget build(BuildContext context) {
    final color = improved ? AppColors.accentGreen : (worsened ? AppColors.accentRed : AppColors.textSecondary);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTypography.body(size: 13, color: AppColors.textSecondary)),
          Text('$oldText → $newText', style: AppTypography.mono(size: 13, weight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}
