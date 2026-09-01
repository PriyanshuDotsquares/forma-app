import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/network/api_exception.dart';
import '../data/progress_providers.dart';
import '../domain/progress_models.dart';
import 'widgets/progress_card.dart';
import 'widgets/progress_format.dart';
import 'widgets/pro_teaser.dart';

/// Pro-gated: `ProgressRepository.formQualityTrend` throws a 402
/// [ApiException] for non-Pro users. That's caught here and swapped for the
/// paywall teaser rather than a generic error state.
class FormQualityDetailScreen extends ConsumerStatefulWidget {
  const FormQualityDetailScreen({super.key});

  @override
  ConsumerState<FormQualityDetailScreen> createState() => _FormQualityDetailScreenState();
}

class _FormQualityDetailScreenState extends ConsumerState<FormQualityDetailScreen> {
  String? _exerciseId;

  @override
  Widget build(BuildContext context) {
    final params = (period: '3month', exerciseId: _exerciseId);
    final trendAsync = ref.watch(formQualityTrendProvider(params));

    return Scaffold(
      appBar: AppBar(title: const Text('FORM QUALITY')),
      body: SafeArea(
        child: trendAsync.when(
          data: (points) => _RealContent(
            points: points,
            selectedExerciseId: _exerciseId,
            onExerciseChanged: (id) => setState(() => _exerciseId = id),
          ),
          loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          error: (e, st) {
            if (e is ApiException && e.isPaymentRequired) {
              return const Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: ProLockedTeaser(
                  title: 'See how your form is trending',
                  message: 'Coach a few sets and unlock advanced form analytics with Pro.',
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: FormaEmptyState(
                icon: Icons.error_outline,
                title: "Couldn't load form quality",
                message: friendlyErrorMessage(e),
                primaryLabel: 'RETRY',
                onPrimary: () => ref.invalidate(formQualityTrendProvider(params)),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _RealContent extends ConsumerWidget {
  const _RealContent({required this.points, required this.selectedExerciseId, required this.onExerciseChanged});

  final List<FormQualityPoint> points;
  final String? selectedExerciseId;
  final ValueChanged<String?> onExerciseChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xxl),
      children: [
        _ExercisePicker(selectedId: selectedExerciseId, onChanged: onExerciseChanged),
        const SizedBox(height: AppSpacing.lg),
        const SectionLabel('FORM SCORE TREND'),
        const SizedBox(height: AppSpacing.sm),
        _TrendCard(points: points),
      ],
    );
  }
}

class _ExercisePicker extends ConsumerWidget {
  const _ExercisePicker({required this.selectedId, required this.onChanged});

  final String? selectedId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exercisesAsync = ref.watch(exerciseListProvider);

    return exercisesAsync.when(
      data: (exercises) {
        final options = exercises.take(8).toList();
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _ExerciseChip(label: 'All Exercises', selected: selectedId == null, onTap: () => onChanged(null)),
              for (final ex in options) ...[
                const SizedBox(width: 8),
                _ExerciseChip(label: ex.name, selected: selectedId == ex.id, onTap: () => onChanged(ex.id)),
              ],
            ],
          ),
        );
      },
      loading: () => const SizedBox(height: 32),
      error: (e, st) => const SizedBox.shrink(),
    );
  }
}

class _ExerciseChip extends StatelessWidget {
  const _ExerciseChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentBlue : AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(AppRadius.chip),
          border: Border.all(color: selected ? AppColors.accentBlue : AppColors.outlineVariant),
        ),
        child: Text(
          label,
          style: AppTypography.body(
            size: 12,
            weight: FontWeight.w600,
            color: selected ? AppColors.accentBlueDark : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.points});

  final List<FormQualityPoint> points;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const FormaEmptyState(
        icon: Icons.show_chart,
        title: 'No form-scored sets yet',
        message: 'Coach a set with the camera on and your form score trend will show up here.',
      );
    }

    final delta = points.length >= 2 ? points.last.formScore - points.first.formScore : 0.0;
    final positive = delta > 0;
    final negative = delta < 0;
    final deltaColor = positive ? AppColors.accentGreen : (negative ? AppColors.accentRed : AppColors.textMuted);

    return ProgressCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (points.length >= 2)
            Row(
              children: [
                Icon(
                  positive ? Icons.trending_up : (negative ? Icons.trending_down : Icons.trending_flat),
                  size: 16,
                  color: deltaColor,
                ),
                const SizedBox(width: 4),
                Text(
                  '${positive ? '+' : ''}${delta.toStringAsFixed(0)} (12 wk)',
                  style: AppTypography.mono(size: 14, weight: FontWeight.w700, color: deltaColor),
                ),
              ],
            ),
          if (points.length >= 2) const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 180,
            child: points.length < 2
                ? Center(
                    child: Text(
                      '${points.first.formScore.toStringAsFixed(0)}% — need another week of data for a trend',
                      textAlign: TextAlign.center,
                      style: AppTypography.body(size: 13, color: AppColors.textSecondary),
                    ),
                  )
                : LineChart(
                    LineChartData(
                      minY: 0,
                      maxY: 100,
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: 25,
                        getDrawingHorizontalLine: (_) => const FlLine(color: AppColors.outlineVariant, strokeWidth: 1),
                      ),
                      borderData: FlBorderData(show: false),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 32,
                            interval: 25,
                            getTitlesWidget: (value, meta) =>
                                Text('${value.toInt()}', style: AppTypography.mono(size: 9, color: AppColors.textMuted)),
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 22,
                            interval: 1,
                            getTitlesWidget: (value, meta) {
                              final i = value.toInt();
                              if (i < 0 || i >= points.length) return const SizedBox.shrink();
                              final skipStep = (points.length / 5).ceil().clamp(1, points.length);
                              if (i % skipStep != 0) return const SizedBox.shrink();
                              return Text(points[i].weekLabel, style: AppTypography.mono(size: 9, color: AppColors.textMuted));
                            },
                          ),
                        ),
                      ),
                      lineBarsData: [
                        LineChartBarData(
                          spots: [for (var i = 0; i < points.length; i++) FlSpot(i.toDouble(), points[i].formScore)],
                          isCurved: true,
                          color: AppColors.accentBlue,
                          barWidth: 2,
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(show: true, color: AppColors.accentBlue.withValues(alpha: 0.08)),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
