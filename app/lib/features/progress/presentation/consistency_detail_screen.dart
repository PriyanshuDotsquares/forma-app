import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/design_system/design_system.dart';
import '../../workout/domain/workout_session.dart';
import '../../workout/presentation/workout_providers.dart';
import '../data/progress_providers.dart';
import '../domain/progress_models.dart';
import 'widgets/progress_card.dart';
import 'widgets/progress_format.dart';

const _weekdayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

/// Sessions for a given month, filtered client-side from `listSessions` —
/// used to enrich the day list below the calendar with real labels/set
/// counts/duration rather than the generic "N session(s)" fallback.
final _monthSessionsProvider = FutureProvider.autoDispose.family<List<WorkoutSession>, ({int year, int month})>((
  ref,
  params,
) async {
  final sessions = await ref.watch(workoutRepositoryProvider).listSessions(limit: 200);
  return sessions.where((s) => s.startedAt.year == params.year && s.startedAt.month == params.month).toList();
});

/// The design's header chrome mislabels this screen "COMPONENT LIBRARY" —
/// that's clearly a copy/paste mismatch in the source Figma frames, so this
/// uses "CONSISTENCY" instead.
class ConsistencyDetailScreen extends ConsumerStatefulWidget {
  const ConsistencyDetailScreen({super.key});

  @override
  ConsumerState<ConsistencyDetailScreen> createState() => _ConsistencyDetailScreenState();
}

class _ConsistencyDetailScreenState extends ConsumerState<ConsistencyDetailScreen> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);

  void _changeMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta, 1));
  }

  @override
  Widget build(BuildContext context) {
    final params = (year: _month.year, month: _month.month);
    final calendarAsync = ref.watch(consistencyCalendarProvider(params));
    final sessionsAsync = ref.watch(_monthSessionsProvider(params));
    final now = DateTime.now();
    final canGoForward = _month.year < now.year || (_month.year == now.year && _month.month < now.month);

    return Scaffold(
      appBar: AppBar(title: const Text('CONSISTENCY')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xxl),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => _changeMonth(-1)),
                Text(DateFormat('MMMM yyyy').format(_month).toUpperCase(), style: AppTypography.display(size: 18)),
                IconButton(icon: const Icon(Icons.chevron_right), onPressed: canGoForward ? () => _changeMonth(1) : null),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            calendarAsync.when(
              data: (days) => _CalendarSection(month: _month, days: days),
              loading: () => const SizedBox(height: 260, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
              error: (e, st) => FormaEmptyState(icon: Icons.error_outline, title: "Couldn't load", message: friendlyErrorMessage(e)),
            ),
            const SizedBox(height: AppSpacing.md),
            const _Legend(),
            const SizedBox(height: AppSpacing.lg),
            calendarAsync.maybeWhen(
              data: (days) => _SummaryLine(days: days, sessionsAsync: sessionsAsync),
              orElse: () => const SizedBox.shrink(),
            ),
            const SizedBox(height: AppSpacing.xl),
            const SectionLabel('TRAINING DAYS'),
            const SizedBox(height: AppSpacing.sm),
            calendarAsync.when(
              data: (days) => _DayListSection(days: days, sessionsAsync: sessionsAsync),
              loading: () => const SizedBox(height: 80, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
              error: (e, st) => const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

class _CalendarSection extends StatelessWidget {
  const _CalendarSection({required this.month, required this.days});

  final DateTime month;
  final List<ConsistencyDay> days;

  @override
  Widget build(BuildContext context) {
    final byDay = {for (final d in days) d.date.day: d};
    final maxVol = days.isEmpty ? 0.0 : days.map((d) => d.volumeKg).reduce((a, b) => a > b ? a : b);

    final firstWeekday = DateTime(month.year, month.month, 1).weekday; // 1=Mon..7=Sun
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final cells = <int?>[...List<int?>.filled(firstWeekday - 1, null), for (var d = 1; d <= daysInMonth; d++) d];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }

    double stepFor(ConsistencyDay? day) {
      if (day == null || day.sessions == 0 || maxVol <= 0) return 0;
      final t = (day.volumeKg / maxVol).clamp(0.0, 1.0);
      return (t * 4).ceil().clamp(1, 4) / 4;
    }

    return ProgressCard(
      child: Column(
        children: [
          Row(children: [for (final l in _weekdayLabels) Expanded(child: Center(child: Text(l, style: AppTypography.body(size: 11, weight: FontWeight.w700, color: AppColors.textMuted))))]),
          const SizedBox(height: 6),
          for (var w = 0; w < cells.length; w += 7)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  for (final c in cells.sublist(w, w + 7))
                    Expanded(
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: c == null ? const SizedBox.shrink() : _DayCell(dayNum: c, day: byDay[c], step: stepFor(byDay[c])),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.dayNum, required this.day, required this.step});

  final int dayNum;
  final ConsistencyDay? day;
  final double step;

  @override
  Widget build(BuildContext context) {
    final color = Color.lerp(AppColors.surfaceHighest, AppColors.accentBlue, step)!;
    final isPr = day?.hasPr ?? false;
    final textColor = step >= 0.5 ? AppColors.accentBlueDark : AppColors.textSecondary;

    return Container(
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: isPr ? AppColors.accentAmber : AppColors.outlineVariant, width: isPr ? 2 : 1),
      ),
      alignment: Alignment.center,
      child: Text('$dayNum', style: AppTypography.mono(size: 11, weight: FontWeight.w600, color: textColor)),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text('less', style: AppTypography.body(size: 11, color: AppColors.textMuted)),
        const SizedBox(width: 6),
        for (var i = 0; i <= 4; i++)
          Container(
            width: 12,
            height: 12,
            margin: const EdgeInsets.only(right: 3),
            decoration: BoxDecoration(
              color: Color.lerp(AppColors.surfaceHighest, AppColors.accentBlue, i / 4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        const SizedBox(width: 4),
        Text('more', style: AppTypography.body(size: 11, color: AppColors.textMuted)),
        const Spacer(),
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(border: Border.all(color: AppColors.accentAmber, width: 2), borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 4),
        Text('PR', style: AppTypography.body(size: 11, color: AppColors.textMuted)),
      ],
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.days, required this.sessionsAsync});

  final List<ConsistencyDay> days;
  final AsyncValue<List<WorkoutSession>> sessionsAsync;

  @override
  Widget build(BuildContext context) {
    final sessionCount = days.fold<int>(0, (a, b) => a + b.sessions);
    final totalVolume = days.fold<double>(0, (a, b) => a + b.volumeKg);
    final sessions = sessionsAsync.valueOrNull;
    final totalDurationS = sessions?.fold<int>(0, (a, s) => a + (s.durationS ?? 0));

    final parts = [
      '$sessionCount session${sessionCount == 1 ? '' : 's'}',
      '${formatVolumeKg(totalVolume)} kg',
      if (totalDurationS != null) formatDurationHm(totalDurationS),
    ];

    return Text(parts.join(' · '), style: AppTypography.mono(size: 13, weight: FontWeight.w600, color: AppColors.textSecondary));
  }
}

class _DayListSection extends StatelessWidget {
  const _DayListSection({required this.days, required this.sessionsAsync});

  final List<ConsistencyDay> days;
  final AsyncValue<List<WorkoutSession>> sessionsAsync;

  @override
  Widget build(BuildContext context) {
    final trainingDays = days.where((d) => d.sessions > 0).toList()..sort((a, b) => b.date.compareTo(a.date));

    if (trainingDays.isEmpty) {
      return const FormaEmptyState(
        icon: Icons.event_busy,
        title: 'No sessions this month',
        message: 'Training days will show up here once you log a workout.',
      );
    }

    final sessionsByDay = <int, List<WorkoutSession>>{};
    for (final s in sessionsAsync.valueOrNull ?? const <WorkoutSession>[]) {
      sessionsByDay.putIfAbsent(s.startedAt.day, () => []).add(s);
    }

    return ProgressCard(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Column(
        children: [
          for (final day in trainingDays) ...[
            _DayRow(day: day, sessions: sessionsByDay[day.date.day] ?? const []),
            if (day != trainingDays.last) const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({required this.day, required this.sessions});

  final ConsistencyDay day;
  final List<WorkoutSession> sessions;

  @override
  Widget build(BuildContext context) {
    final hasSessions = sessions.isNotEmpty;
    final label = !hasSessions
        ? '${day.sessions} session${day.sessions == 1 ? '' : 's'}'
        : (sessions.length == 1 ? sessions.first.label : '${sessions.length} sessions');
    final totalSets = sessions.fold<int>(0, (a, s) => a + s.sets.length);
    final totalDurationS = sessions.fold<int>(0, (a, s) => a + (s.durationS ?? 0));
    final subtitle = hasSessions
        ? '${totalSets > 0 ? '$totalSets sets · ' : ''}${formatDurationHm(totalDurationS)}'
        : '${formatVolumeKg(day.volumeKg)} kg';

    final formScores = sessions.map((s) => s.avgFormScore).whereType<double>().toList();
    final avgForm = formScores.isEmpty ? null : formScores.reduce((a, b) => a + b) / formScores.length;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          SizedBox(width: 28, child: Text('${day.date.day}', style: AppTypography.mono(size: 15, weight: FontWeight.w700))),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTypography.body(size: 13, weight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(subtitle, style: AppTypography.mono(size: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
          if (day.hasPr) ...[const BadgePill('PR', color: AppColors.accentAmber), const SizedBox(width: 6)],
          if (avgForm != null)
            BadgePill(
              '${avgForm.toStringAsFixed(0)}%',
              color: avgForm >= 85 ? AppColors.accentGreen : (avgForm >= 70 ? AppColors.accentAmber : AppColors.accentRed),
            ),
        ],
      ),
    );
  }
}
