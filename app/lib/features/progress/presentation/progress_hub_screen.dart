import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/router/app_router.dart';
import '../../achievements/data/achievements_providers.dart';
import '../../achievements/domain/achievement.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/progress_providers.dart';
import '../domain/progress_models.dart';
import 'widgets/hub_row_link.dart';
import 'widgets/mini_previews.dart';
import 'widgets/period_selector.dart';
import 'widgets/progress_card.dart';
import 'widgets/progress_format.dart';
import 'widgets/sparkline.dart';

class ProgressHubScreen extends ConsumerStatefulWidget {
  const ProgressHubScreen({super.key});

  @override
  ConsumerState<ProgressHubScreen> createState() => _ProgressHubScreenState();
}

class _ProgressHubScreenState extends ConsumerState<ProgressHubScreen> {
  String _period = 'month';

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).valueOrNull;
    final summaryAsync = ref.watch(progressSummaryProvider(_period));

    return Scaffold(
      appBar: AppBar(
        title: const Text('PROGRESS'),
        actions: [
          IconButton(
            tooltip: 'Consistency calendar',
            icon: const Icon(Icons.calendar_today_outlined),
            onPressed: () => context.push(AppRoutes.progressConsistency),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xxl),
          children: [
            PeriodSelector(value: _period, onChanged: (p) => setState(() => _period = p)),
            const SizedBox(height: AppSpacing.lg),
            _SummaryGrid(summaryAsync: summaryAsync),
            const SizedBox(height: AppSpacing.lg),
            const SectionLabel('BREAKDOWN'),
            const SizedBox(height: AppSpacing.sm),
            _VolumeRow(period: _period),
            const SizedBox(height: AppSpacing.sm),
            const _RecoveryRow(),
            const SizedBox(height: AppSpacing.sm),
            const _StrengthFold(),
            const SizedBox(height: AppSpacing.sm),
            _FormQualityRow(isPro: user?.isPro ?? false),
            const SizedBox(height: AppSpacing.sm),
            const _RecordsFold(),
            const SizedBox(height: AppSpacing.sm),
            const _ConsistencyRow(),
          ],
        ),
      ),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.summaryAsync});

  final AsyncValue<ProgressSummary> summaryAsync;

  @override
  Widget build(BuildContext context) {
    if (summaryAsync.hasError && !summaryAsync.isLoading) {
      return FormaEmptyState(
        icon: Icons.error_outline,
        title: "Couldn't load progress",
        message: friendlyErrorMessage(summaryAsync.error!),
      );
    }

    final s = summaryAsync.valueOrNull;
    final tiles = [
      StatTile(label: 'Workouts', value: s != null ? '${s.workouts}' : '—'),
      StatTile(label: 'Volume', value: s != null ? formatVolumeKg(s.volumeKg) : '—', unit: s != null ? 'kg' : null),
      StatTile(label: 'Time in gym', value: s != null ? formatDurationHm(s.timeS) : '—'),
      StatTile(
        label: 'Avg form',
        value: s?.avgFormScore != null ? s!.avgFormScore!.toStringAsFixed(0) : '—',
        unit: s?.avgFormScore != null ? '%' : null,
      ),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: AppSpacing.sm,
      crossAxisSpacing: AppSpacing.sm,
      childAspectRatio: 1.7,
      children: tiles,
    );
  }
}

class _VolumeRow extends ConsumerWidget {
  const _VolumeRow({required this.period});

  final String period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final volumeAsync = ref.watch(volumeByMuscleProvider(period));

    return volumeAsync.when(
      data: (muscles) {
        if (muscles.isEmpty) {
          return HubRowLink(
            title: 'Volume by muscle',
            subtitle: 'No sets logged yet',
            preview: const Icon(Icons.bar_chart, color: AppColors.textMuted, size: 20),
            onTap: () => context.push(AppRoutes.progressVolume),
          );
        }
        final sorted = [...muscles]..sort((a, b) => b.sets.compareTo(a.sets));
        final top = sorted.take(6).toList();
        final maxSets = top.first.sets.toDouble().clamp(1, double.infinity);
        return HubRowLink(
          title: 'Volume by muscle',
          subtitle: '${titleCaseMuscle(top.first.muscle)} leads this period',
          preview: MiniBarPreview(values: top.map((m) => m.sets / maxSets).toList()),
          onTap: () => context.push(AppRoutes.progressVolume),
        );
      },
      loading: () => HubRowLink(
        title: 'Volume by muscle',
        subtitle: 'Loading…',
        preview: const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        onTap: () => context.push(AppRoutes.progressVolume),
      ),
      error: (e, st) => HubRowLink(
        title: 'Volume by muscle',
        subtitle: "Couldn't load",
        preview: const Icon(Icons.error_outline, color: AppColors.textMuted, size: 18),
        onTap: () => context.push(AppRoutes.progressVolume),
      ),
    );
  }
}

class _RecoveryRow extends ConsumerWidget {
  const _RecoveryRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recoveryAsync = ref.watch(recoveryProvider);

    return recoveryAsync.when(
      data: (items) {
        if (items.isEmpty) {
          return HubRowLink(
            title: 'Recovery',
            subtitle: 'No training data yet',
            preview: const MiniRecoveryFigures(avgPct: 100),
            onTap: () => context.push(AppRoutes.progressRecovery),
          );
        }
        final avg = items.map((i) => i.recoveredPct).reduce((a, b) => a + b) / items.length;
        final least = [...items]..sort((a, b) => a.recoveredPct.compareTo(b.recoveredPct));
        // Every muscle group defaults to 100% recovered until it's actually
        // been trained — naming one as "needs the most time" when they're
        // all fully fresh (nothing trained yet) reads backwards.
        final subtitle = least.first.recoveredPct >= 100
            ? 'Fully recovered'
            : '${titleCaseMuscle(least.first.muscleGroup)} needs the most time';
        return HubRowLink(
          title: 'Recovery',
          subtitle: subtitle,
          preview: MiniRecoveryFigures(avgPct: avg),
          onTap: () => context.push(AppRoutes.progressRecovery),
        );
      },
      loading: () => HubRowLink(
        title: 'Recovery',
        subtitle: 'Loading…',
        preview: const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        onTap: () => context.push(AppRoutes.progressRecovery),
      ),
      error: (e, st) => HubRowLink(
        title: 'Recovery',
        subtitle: "Couldn't load",
        preview: const Icon(Icons.error_outline, color: AppColors.textMuted, size: 18),
        onTap: () => context.push(AppRoutes.progressRecovery),
      ),
    );
  }
}

/// Folded directly onto the hub since there's no dedicated top-level
/// strength route — a small real trend chart of whichever exercise most
/// recently set a PR, backed by [personalRecordsProvider] (achievements
/// feature) + `strengthTrendProvider`.
class _StrengthFold extends ConsumerWidget {
  const _StrengthFold();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordsAsync = ref.watch(personalRecordsProvider);

    return recordsAsync.when(
      data: (records) {
        if (records.isEmpty) {
          return const ProgressCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionLabel('STRENGTH'),
                SizedBox(height: 6),
                Text('No PRs yet — log a set to start tracking strength.'),
              ],
            ),
          );
        }
        final sorted = [...records]..sort((a, b) => b.achievedAt.compareTo(a.achievedAt));
        final recent = sorted.first;
        return _StrengthCard(exerciseId: recent.exerciseId, latestEst1RmKg: recent.est1RmKg);
      },
      loading: () => const ProgressCard(
        child: SizedBox(height: 48, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
      ),
      // Achievements isn't this feature's dependency to fail loudly for —
      // hide the fold rather than surfacing another feature's error here.
      error: (e, st) => const SizedBox.shrink(),
    );
  }
}

class _StrengthCard extends ConsumerWidget {
  const _StrengthCard({required this.exerciseId, required this.latestEst1RmKg});

  final String exerciseId;
  final double latestEst1RmKg;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exerciseAsync = ref.watch(exerciseByIdProvider(exerciseId));
    final trendAsync = ref.watch(strengthTrendProvider((exerciseId: exerciseId, period: 'year')));
    final name = exerciseAsync.valueOrNull?.name ?? 'Recent PR';

    return ProgressCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const SectionLabel('STRENGTH'),
                const SizedBox(height: 4),
                Text(name, style: AppTypography.body(size: 13, weight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  '${latestEst1RmKg.toStringAsFixed(1)} kg est. 1RM',
                  style: AppTypography.mono(size: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          trendAsync.when(
            data: (points) {
              if (points.length < 2) return const SizedBox.shrink();
              final values = points.map((p) => p.est1RmKg).toList();
              final delta = values.last - values.first;
              final positive = delta >= 0;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Sparkline(values: values, color: positive ? AppColors.accentGreen : AppColors.accentRed),
                  const SizedBox(height: 2),
                  Text(
                    '${positive ? '+' : ''}${delta.toStringAsFixed(1)} kg',
                    style: AppTypography.mono(size: 11, weight: FontWeight.w600, color: positive ? AppColors.accentGreen : AppColors.accentRed),
                  ),
                ],
              );
            },
            loading: () => const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            error: (e, st) => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _FormQualityRow extends ConsumerWidget {
  const _FormQualityRow({required this.isPro});

  final bool isPro;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!isPro) {
      return HubRowLink(
        title: 'Form quality',
        subtitle: 'Unlock with FORMA Pro',
        trailingBadge: const BadgePill('PRO'),
        preview: const Icon(Icons.lock_outline, color: AppColors.textMuted, size: 18),
        onTap: () => context.push(AppRoutes.progressFormQuality),
      );
    }

    final trendAsync = ref.watch(formQualityTrendProvider((period: '3month', exerciseId: null)));

    return trendAsync.when(
      data: (points) {
        if (points.isEmpty) {
          return HubRowLink(
            title: 'Form quality',
            subtitle: 'No form-scored sets yet',
            preview: const Icon(Icons.show_chart, color: AppColors.textMuted, size: 18),
            onTap: () => context.push(AppRoutes.progressFormQuality),
          );
        }
        final values = points.map((p) => p.formScore).toList();
        return HubRowLink(
          title: 'Form quality',
          subtitle: 'Latest: ${values.last.toStringAsFixed(0)}%',
          preview: Sparkline(values: values, color: AppColors.accentBlue),
          onTap: () => context.push(AppRoutes.progressFormQuality),
        );
      },
      loading: () => HubRowLink(
        title: 'Form quality',
        subtitle: 'Loading…',
        preview: const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        onTap: () => context.push(AppRoutes.progressFormQuality),
      ),
      error: (e, st) => HubRowLink(
        title: 'Form quality',
        subtitle: "Couldn't load",
        preview: const Icon(Icons.error_outline, color: AppColors.textMuted, size: 18),
        onTap: () => context.push(AppRoutes.progressFormQuality),
      ),
    );
  }
}

/// Folded onto the hub since there's no dedicated records route — reuses
/// the same [personalRecordsProvider] fetch as [_StrengthFold] (Riverpod
/// dedupes the watch, so this doesn't cost a second request).
class _RecordsFold extends ConsumerWidget {
  const _RecordsFold();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordsAsync = ref.watch(personalRecordsProvider);

    return recordsAsync.when(
      data: (records) {
        if (records.isEmpty) return const SizedBox.shrink();
        final sorted = [...records]..sort((a, b) => b.achievedAt.compareTo(a.achievedAt));
        final recent = sorted.take(3).toList();
        return ProgressCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionLabel(
                'RECORDS',
                trailing: Text(
                  '${records.length} PR${records.length == 1 ? '' : 's'}',
                  style: AppTypography.mono(size: 12, weight: FontWeight.w700, color: AppColors.accentAmber),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final r in recent) ...[_RecordRow(record: r), if (r != recent.last) const SizedBox(height: 8)],
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (e, st) => const SizedBox.shrink(),
    );
  }
}

class _RecordRow extends ConsumerWidget {
  const _RecordRow({required this.record});

  final PersonalRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exerciseAsync = ref.watch(exerciseByIdProvider(record.exerciseId));
    final name = exerciseAsync.valueOrNull?.name ?? 'Exercise';

    return Row(
      children: [
        const Icon(Icons.emoji_events_outlined, size: 16, color: AppColors.accentAmber),
        const SizedBox(width: 8),
        Expanded(child: Text(name, style: AppTypography.body(size: 13))),
        Text(
          '${record.weightKg.toStringAsFixed(1)}kg × ${record.reps}',
          style: AppTypography.mono(size: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(width: 8),
        Text(formatRelativeDate(record.achievedAt), style: AppTypography.body(size: 11, color: AppColors.textMuted)),
      ],
    );
  }
}

class _ConsistencyRow extends ConsumerWidget {
  const _ConsistencyRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final calendarAsync = ref.watch(consistencyCalendarProvider((year: now.year, month: now.month)));

    return calendarAsync.when(
      data: (days) {
        final byDay = {for (final d in days) d.date.day: d.sessions > 0};
        final flags = [for (var day = 1; day <= now.day; day++) byDay[day] ?? false];
        final padded = flags.length >= 28 ? flags.sublist(flags.length - 28) : [...List.filled(28 - flags.length, false), ...flags];
        final sessionCount = days.fold<int>(0, (a, b) => a + b.sessions);
        return HubRowLink(
          title: 'Consistency',
          subtitle: '$sessionCount session${sessionCount == 1 ? '' : 's'} this month',
          preview: MiniDotGrid(filled: padded),
          onTap: () => context.push(AppRoutes.progressConsistency),
        );
      },
      loading: () => HubRowLink(
        title: 'Consistency',
        subtitle: 'Loading…',
        preview: const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        onTap: () => context.push(AppRoutes.progressConsistency),
      ),
      error: (e, st) => HubRowLink(
        title: 'Consistency',
        subtitle: "Couldn't load",
        preview: const Icon(Icons.error_outline, color: AppColors.textMuted, size: 18),
        onTap: () => context.push(AppRoutes.progressConsistency),
      ),
    );
  }
}
