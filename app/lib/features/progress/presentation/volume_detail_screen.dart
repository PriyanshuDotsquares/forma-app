import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/design_system.dart';
import '../data/progress_providers.dart';
import '../domain/progress_models.dart';
import 'widgets/period_selector.dart';
import 'widgets/progress_card.dart';
import 'widgets/progress_format.dart';

class VolumeDetailScreen extends ConsumerStatefulWidget {
  const VolumeDetailScreen({super.key});

  @override
  ConsumerState<VolumeDetailScreen> createState() => _VolumeDetailScreenState();
}

class _VolumeDetailScreenState extends ConsumerState<VolumeDetailScreen> {
  String _period = 'month';

  @override
  Widget build(BuildContext context) {
    final trendAsync = ref.watch(volumeTrendProvider(_period));
    final muscleAsync = ref.watch(volumeByMuscleProvider(_period));
    final trend12wAsync = ref.watch(volumeTrendProvider('3month'));

    return Scaffold(
      appBar: AppBar(title: const Text('VOLUME')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xxl),
          children: [
            PeriodSelector(value: _period, onChanged: (p) => setState(() => _period = p)),
            const SizedBox(height: AppSpacing.lg),
            SectionLabel(kPeriodDistributionLabels[_period] ?? 'DISTRIBUTION'),
            const SizedBox(height: AppSpacing.sm),
            _DistributionChart(trendAsync: trendAsync),
            const SizedBox(height: AppSpacing.xl),
            SectionLabel('SETS PER MUSCLE (${kPeriodNounLabels[_period] ?? _period.toUpperCase()})'),
            const SizedBox(height: AppSpacing.sm),
            _MuscleBreakdown(muscleAsync: muscleAsync, showBand: _period == 'week'),
            const SizedBox(height: AppSpacing.sm),
            const InfoBanner(
              title: 'Where most people grow',
              body: 'The shaded band is 10–20 hard sets per muscle per week.',
              icon: Icons.info_outline,
            ),
            const SizedBox(height: AppSpacing.xl),
            const SectionLabel('BALANCE RATIOS'),
            const SizedBox(height: AppSpacing.sm),
            _BalanceRatios(muscleAsync: muscleAsync),
            const SizedBox(height: AppSpacing.xl),
            const SectionLabel('12-WEEK TREND'),
            const SizedBox(height: AppSpacing.sm),
            _TrendLine(trendAsync: trend12wAsync),
          ],
        ),
      ),
    );
  }
}

class _DistributionChart extends StatelessWidget {
  const _DistributionChart({required this.trendAsync});

  final AsyncValue<List<VolumeTrendPoint>> trendAsync;

  @override
  Widget build(BuildContext context) {
    return trendAsync.when(
      data: (points) {
        if (points.isEmpty) {
          return const FormaEmptyState(
            icon: Icons.bar_chart,
            title: 'No volume yet',
            message: 'Log a few workouts to see your distribution here.',
          );
        }
        final maxVal = points.map((p) => p.volumeKg).reduce((a, b) => a > b ? a : b);
        final maxY = maxVal <= 0 ? 10.0 : maxVal * 1.2;
        final deloadLabels = points.where((p) => p.isDeload).map((p) => p.periodLabel).toList();

        return ProgressCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 200,
                child: BarChart(
                  BarChartData(
                    maxY: maxY,
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      horizontalInterval: maxY / 4,
                      getDrawingHorizontalLine: (_) => const FlLine(color: AppColors.outlineVariant, strokeWidth: 1),
                    ),
                    borderData: FlBorderData(show: false),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 40,
                          getTitlesWidget: (value, meta) =>
                              Text(formatVolumeKg(value), style: AppTypography.mono(size: 9, color: AppColors.textMuted)),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 26,
                          interval: 1,
                          getTitlesWidget: (value, meta) {
                            final i = value.toInt();
                            if (i < 0 || i >= points.length) return const SizedBox.shrink();
                            if (points.length > 8 && i.isOdd) return const SizedBox.shrink();
                            return Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(points[i].periodLabel, style: AppTypography.mono(size: 9, color: AppColors.textMuted)),
                            );
                          },
                        ),
                      ),
                    ),
                    barGroups: [
                      for (var i = 0; i < points.length; i++)
                        BarChartGroupData(
                          x: i,
                          barRods: [
                            BarChartRodData(
                              toY: points[i].volumeKg,
                              color: points[i].isDeload ? AppColors.textMuted : AppColors.accentBlue,
                              width: 14,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              if (deloadLabels.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Deload: ${deloadLabels.join(', ')}',
                  style: AppTypography.body(size: 11, color: AppColors.textMuted),
                ),
              ],
            ],
          ),
        );
      },
      loading: () => const ProgressCard(
        child: SizedBox(height: 200, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
      ),
      error: (e, st) => FormaEmptyState(icon: Icons.error_outline, title: "Couldn't load", message: friendlyErrorMessage(e)),
    );
  }
}

class _MuscleBreakdown extends StatelessWidget {
  const _MuscleBreakdown({required this.muscleAsync, required this.showBand});

  final AsyncValue<List<VolumeByMuscle>> muscleAsync;
  final bool showBand;

  @override
  Widget build(BuildContext context) {
    return muscleAsync.when(
      data: (muscles) {
        if (muscles.isEmpty) {
          return const FormaEmptyState(
            icon: Icons.fitness_center,
            title: 'No sets yet',
            message: 'Your per-muscle breakdown will show up here once you log some sets.',
          );
        }
        final sorted = [...muscles]..sort((a, b) => b.sets.compareTo(a.sets));
        final axisMax = [20, ...sorted.map((m) => m.sets)].reduce((a, b) => a > b ? a : b).toDouble() * 1.1;

        return ProgressCard(
          child: Column(
            children: [
              for (final m in sorted)
                _MuscleBarRow(muscle: m.muscle, sets: m.sets, axisMax: axisMax, showBand: showBand),
            ],
          ),
        );
      },
      loading: () => const ProgressCard(
        child: SizedBox(height: 80, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
      ),
      error: (e, st) => FormaEmptyState(icon: Icons.error_outline, title: "Couldn't load", message: friendlyErrorMessage(e)),
    );
  }
}

class _MuscleBarRow extends StatelessWidget {
  const _MuscleBarRow({required this.muscle, required this.sets, required this.axisMax, required this.showBand});

  final String muscle;
  final int sets;
  final double axisMax;
  final bool showBand;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 84,
            child: Text(titleCaseMuscle(muscle), style: AppTypography.body(size: 12, color: AppColors.textSecondary)),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                final barW = axisMax <= 0 ? 0.0 : (sets / axisMax).clamp(0.0, 1.0) * w;
                return Stack(
                  children: [
                    Container(
                      height: 10,
                      decoration: BoxDecoration(color: AppColors.surfaceHighest, borderRadius: BorderRadius.circular(4)),
                    ),
                    if (showBand && axisMax > 0)
                      Positioned(
                        left: (10 / axisMax).clamp(0.0, 1.0) * w,
                        width: (10 / axisMax).clamp(0.0, 1.0) * w,
                        child: Container(
                          height: 10,
                          decoration: BoxDecoration(
                            color: AppColors.accentGreen.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    Container(
                      width: barW,
                      height: 10,
                      decoration: BoxDecoration(color: AppColors.accentBlue, borderRadius: BorderRadius.circular(4)),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 26,
            child: Text('$sets', textAlign: TextAlign.right, style: AppTypography.mono(size: 12, weight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _BalanceRatios extends StatelessWidget {
  const _BalanceRatios({required this.muscleAsync});

  final AsyncValue<List<VolumeByMuscle>> muscleAsync;

  @override
  Widget build(BuildContext context) {
    return muscleAsync.when(
      data: (muscles) {
        if (muscles.isEmpty) {
          return ProgressCard(
            child: Text('Not enough data yet.', style: AppTypography.body(size: 13, color: AppColors.textSecondary)),
          );
        }
        double setsFor(Set<String> group) =>
            muscles.where((m) => group.contains(m.muscle.toLowerCase())).fold(0.0, (a, b) => a + b.sets);

        final push = setsFor(kPushMuscles);
        final pull = setsFor(kPullMuscles);
        final upper = setsFor(kUpperMuscles);
        final lower = setsFor(kLowerMuscles);

        return ProgressCard(
          child: Column(
            children: [
              _RatioRow(leftLabel: 'PUSH', rightLabel: 'PULL', leftValue: push, rightValue: pull),
              const SizedBox(height: AppSpacing.md),
              _RatioRow(leftLabel: 'UPPER', rightLabel: 'LOWER', leftValue: upper, rightValue: lower),
              const SizedBox(height: AppSpacing.sm),
              Text(
                _pushPullReasoning(push, pull),
                style: AppTypography.body(size: 13, color: AppColors.textSecondary),
              ),
            ],
          ),
        );
      },
      loading: () => const ProgressCard(
        child: SizedBox(height: 64, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
      ),
      error: (e, st) => ProgressCard(
        child: Text(friendlyErrorMessage(e), style: AppTypography.body(size: 12, color: AppColors.textMuted)),
      ),
    );
  }
}

/// Plain-language read on the push/pull split below the ratio bars — the
/// direction and how far off balance it is come from the same set counts
/// as [_RatioRow] above, never a hardcoded number.
String _pushPullReasoning(double push, double pull) {
  final total = push + pull;
  if (total <= 0) return 'Log a few push and pull sets to see how they compare.';
  final imbalance = (push - pull) / total; // positive: push ahead, negative: pull ahead
  if (imbalance.abs() < 0.08) {
    return 'Your push and pull volume are evenly matched — a solid balance for shoulder health.';
  }
  final wellAhead = imbalance.abs() >= 0.25;
  if (imbalance < 0) {
    return wellAhead
        ? "Your pull volume is well ahead of push — great for joint health, just don't let pushing drop off completely."
        : "Your pull volume is slightly ahead — that's a good place to be for joint health.";
  }
  return wellAhead
      ? 'Your push volume is well ahead of pull — add more rows or pulldowns to keep your shoulders balanced.'
      : 'Your push volume is slightly ahead of pull — a few extra rows or pulldowns would help keep things balanced.';
}

class _RatioRow extends StatelessWidget {
  const _RatioRow({required this.leftLabel, required this.rightLabel, required this.leftValue, required this.rightValue});

  final String leftLabel;
  final String rightLabel;
  final double leftValue;
  final double rightValue;

  @override
  Widget build(BuildContext context) {
    final total = leftValue + rightValue;
    final leftFraction = total <= 0 ? 0.5 : leftValue / total;
    final ratio = rightValue <= 0 ? null : leftValue / rightValue;
    final ratioLabel = ratio == null ? '—' : ratio.toStringAsFixed(1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$leftLabel $ratioLabel — 1.0 $rightLabel',
          style: AppTypography.mono(size: 13, weight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 8,
            child: Row(
              children: [
                Expanded(flex: (leftFraction * 1000).round().clamp(1, 999), child: Container(color: AppColors.accentBlue)),
                Expanded(
                  flex: ((1 - leftFraction) * 1000).round().clamp(1, 999),
                  child: Container(color: AppColors.accentGreen),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Shaded bands over contiguous deload weeks in the trend line, mirroring
/// the grayed-out bars + "Deload: ..." label the bar-chart version above
/// already uses for the same [VolumeTrendPoint.isDeload] flag.
List<VerticalRangeAnnotation> _deloadBands(List<VolumeTrendPoint> points) {
  final bands = <VerticalRangeAnnotation>[];
  int? start;
  for (var i = 0; i < points.length; i++) {
    if (points[i].isDeload) {
      start ??= i;
    } else if (start != null) {
      bands.add(VerticalRangeAnnotation(x1: start - 0.5, x2: i - 0.5, color: AppColors.accentRed.withValues(alpha: 0.1)));
      start = null;
    }
  }
  if (start != null) {
    bands.add(VerticalRangeAnnotation(x1: start - 0.5, x2: points.length - 0.5, color: AppColors.accentRed.withValues(alpha: 0.1)));
  }
  return bands;
}

class _TrendLine extends StatelessWidget {
  const _TrendLine({required this.trendAsync});

  final AsyncValue<List<VolumeTrendPoint>> trendAsync;

  @override
  Widget build(BuildContext context) {
    return trendAsync.when(
      data: (points) {
        if (points.length < 2) {
          return const FormaEmptyState(
            icon: Icons.show_chart,
            title: 'Not enough data',
            message: 'Keep logging workouts to see a trend line here.',
          );
        }
        final spots = [for (var i = 0; i < points.length; i++) FlSpot(i.toDouble(), points[i].volumeKg)];
        final maxVal = points.map((p) => p.volumeKg).reduce((a, b) => a > b ? a : b);
        final maxY = maxVal <= 0 ? 10.0 : maxVal * 1.2;
        final labelInterval = (points.length / 5).ceil().clamp(1, points.length);
        final deloadBands = _deloadBands(points);
        final deloadLabels = points.where((p) => p.isDeload).map((p) => p.periodLabel).toList();

        return ProgressCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 180,
                child: LineChart(
                  LineChartData(
                    minY: 0,
                    maxY: maxY,
                    rangeAnnotations: RangeAnnotations(verticalRangeAnnotations: deloadBands),
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      horizontalInterval: maxY / 4,
                      getDrawingHorizontalLine: (_) => const FlLine(color: AppColors.outlineVariant, strokeWidth: 1),
                    ),
                    borderData: FlBorderData(show: false),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 40,
                          getTitlesWidget: (value, meta) =>
                              Text(formatVolumeKg(value), style: AppTypography.mono(size: 9, color: AppColors.textMuted)),
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
                            if (i % labelInterval != 0) return const SizedBox.shrink();
                            return Text(points[i].periodLabel, style: AppTypography.mono(size: 9, color: AppColors.textMuted));
                          },
                        ),
                      ),
                    ),
                    lineBarsData: [
                      LineChartBarData(
                        spots: spots,
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
              if (deloadLabels.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Deload: ${deloadLabels.join(', ')}',
                  style: AppTypography.body(size: 11, color: AppColors.textMuted),
                ),
              ],
            ],
          ),
        );
      },
      loading: () => const ProgressCard(
        child: SizedBox(height: 180, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
      ),
      error: (e, st) => FormaEmptyState(icon: Icons.error_outline, title: "Couldn't load", message: friendlyErrorMessage(e)),
    );
  }
}
