import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/app_router.dart';
import '../domain/workout_session.dart';
import 'workout_providers.dart';

const _weekdayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

double _volumeKg(WorkoutSession s) => s.sets.fold(0.0, (sum, set) => sum + (set.actualWeightKg ?? 0) * (set.actualReps ?? 0));

double? _avgForm(WorkoutSession s) {
  final scored = s.sets.where((set) => set.formScore != null).toList();
  if (scored.isEmpty) return s.avgFormScore;
  return scored.map((set) => set.formScore!).reduce((a, b) => a + b) / scored.length;
}

String _fmtVolume(double kg) {
  if (kg >= 1000000) return '${(kg / 1000000).toStringAsFixed(2)}M';
  if (kg >= 1000) return '${(kg / 1000).toStringAsFixed(1)}k';
  return kg.toStringAsFixed(0);
}

String _fmtDurationHm(int? totalSeconds) {
  if (totalSeconds == null || totalSeconds <= 0) return '0m';
  final totalMinutes = totalSeconds ~/ 60;
  final h = totalMinutes ~/ 60;
  final m = totalMinutes % 60;
  if (h <= 0) return '${m}m';
  return '${h}h ${m}m';
}

Widget _formScoreBadge(WorkoutSession session) {
  if (session.sets.isEmpty) return const BadgePill('--', color: AppColors.textMuted, outlined: true);
  final avgForm = _avgForm(session);
  if (avgForm == null) return const BadgePill('--', color: AppColors.textMuted, outlined: true);
  final color = avgForm >= 80 ? AppColors.accentGreen : (avgForm >= 60 ? AppColors.accentAmber : AppColors.accentRed);
  return BadgePill('${avgForm.round()}', color: color);
}

/// Workout history — a calendar heatmap for one month at a time (paged with
/// ‹/›) plus the full session list grouped by month below it. Both are
/// derived client-side from a single `workoutHistoryProvider` fetch (the
/// most recent 200 sessions) since there's no server-side date-range filter
/// to page a calendar against. Paging the calendar earlier than what's
/// loaded just renders that month empty rather than fetching more.
class WorkoutHistoryScreen extends ConsumerStatefulWidget {
  const WorkoutHistoryScreen({super.key});

  @override
  ConsumerState<WorkoutHistoryScreen> createState() => _WorkoutHistoryScreenState();
}

class _WorkoutHistoryScreenState extends ConsumerState<WorkoutHistoryScreen> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);

  void _changeMonth(int delta) => setState(() => _month = DateTime(_month.year, _month.month + delta, 1));

  @override
  Widget build(BuildContext context) {
    final sessionsAsync = ref.watch(workoutHistoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('HISTORY')),
      body: SafeArea(
        child: sessionsAsync.when(
          data: (sessions) {
            if (sessions.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: const FormaEmptyState(
                    icon: Icons.history,
                    title: 'No workouts yet',
                    message: 'Finish a session and it will show up here.',
                  ),
                ),
              );
            }
            return _Content(sessions: sessions, month: _month, onChangeMonth: _changeMonth);
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: FormaEmptyState(
                icon: Icons.error_outline,
                title: "That didn't work.",
                message: error is ApiException ? error.message : 'Could not load your history.',
                primaryLabel: 'RETRY',
                onPrimary: () => ref.invalidate(workoutHistoryProvider),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({required this.sessions, required this.month, required this.onChangeMonth});

  final List<WorkoutSession> sessions;
  final DateTime month;
  final ValueChanged<int> onChangeMonth;

  @override
  Widget build(BuildContext context) {
    final monthSessions = sessions.where((s) => s.startedAt.year == month.year && s.startedAt.month == month.month).toList();
    final now = DateTime.now();
    final canGoForward = month.year < now.year || (month.year == now.year && month.month < now.month);

    final totalVolume = sessions.fold<double>(0, (a, s) => a + _volumeKg(s));
    final totalDurationS = sessions.fold<int>(0, (a, s) => a + (s.durationS ?? 0));

    // `sessions` arrives most-recent-first (see `WorkoutRepository.listSessions`),
    // so grouping by insertion order keeps months newest-first with no extra sort.
    final byMonth = <String, List<WorkoutSession>>{};
    final monthOrder = <String>[];
    for (final s in sessions) {
      final key = DateFormat('yyyy-MM').format(s.startedAt);
      if (!byMonth.containsKey(key)) monthOrder.add(key);
      byMonth.putIfAbsent(key, () => []).add(s);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xxl),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => onChangeMonth(-1)),
            Text(DateFormat('MMMM yyyy').format(month).toUpperCase(), style: AppTypography.display(size: 18)),
            IconButton(icon: const Icon(Icons.chevron_right), onPressed: canGoForward ? () => onChangeMonth(1) : null),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _CalendarCard(month: month, sessions: monthSessions),
        const SizedBox(height: AppSpacing.md),
        const _Legend(),
        const SizedBox(height: AppSpacing.lg),
        Text(
          '${sessions.length} session${sessions.length == 1 ? '' : 's'} · ${_fmtVolume(totalVolume)} kg · ${_fmtDurationHm(totalDurationS)}',
          style: AppTypography.mono(size: 13, weight: FontWeight.w600, color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.xl),
        for (final key in monthOrder) ...[
          SectionLabel(DateFormat('MMMM yyyy').format(byMonth[key]!.first.startedAt)),
          const SizedBox(height: AppSpacing.sm),
          ...byMonth[key]!.map((s) => Padding(padding: const EdgeInsets.only(bottom: AppSpacing.sm), child: _SessionRow(session: s))),
          const SizedBox(height: AppSpacing.md),
        ],
      ],
    );
  }
}

class _CalendarCard extends StatelessWidget {
  const _CalendarCard({required this.month, required this.sessions});

  final DateTime month;
  final List<WorkoutSession> sessions;

  @override
  Widget build(BuildContext context) {
    final volumeByDay = <int, double>{};
    final prByDay = <int, bool>{};
    for (final s in sessions) {
      final day = s.startedAt.day;
      volumeByDay[day] = (volumeByDay[day] ?? 0) + _volumeKg(s);
      if (s.sets.any((set) => set.isPr)) prByDay[day] = true;
    }
    final maxVol = volumeByDay.values.isEmpty ? 0.0 : volumeByDay.values.reduce((a, b) => a > b ? a : b);

    final firstWeekday = DateTime(month.year, month.month, 1).weekday; // 1=Mon..7=Sun
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final cells = <int?>[...List<int?>.filled(firstWeekday - 1, null), for (var d = 1; d <= daysInMonth; d++) d];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }

    // Any session that day gets at least the lightest fill (min bucket 1),
    // even at zero volume (a logged-but-empty rest/mobility day) — that's
    // what visually distinguishes "trained" from "no session" cells.
    double stepFor(int? day) {
      if (day == null || !volumeByDay.containsKey(day)) return 0;
      if (maxVol <= 0) return 0.25;
      final t = (volumeByDay[day]! / maxVol).clamp(0.0, 1.0);
      return (t * 4).ceil().clamp(1, 4) / 4;
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceBase,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        children: [
          Row(
            children: [
              for (final l in _weekdayLabels)
                Expanded(
                  child: Center(child: Text(l, style: AppTypography.body(size: 11, weight: FontWeight.w700, color: AppColors.textMuted))),
                ),
            ],
          ),
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
                        child: c == null ? const SizedBox.shrink() : _DayCell(dayNum: c, step: stepFor(c), isPr: prByDay[c] ?? false),
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
  const _DayCell({required this.dayNum, required this.step, required this.isPr});

  final int dayNum;
  final double step;
  final bool isPr;

  @override
  Widget build(BuildContext context) {
    final color = step <= 0 ? Colors.transparent : Color.lerp(AppColors.surfaceHighest, AppColors.accentBlue, step)!;
    final textColor = step >= 0.75 ? AppColors.accentBlueDark : AppColors.textSecondary;

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
              color: i == 0 ? Colors.transparent : Color.lerp(AppColors.surfaceHighest, AppColors.accentBlue, i / 4),
              borderRadius: BorderRadius.circular(2),
              border: i == 0 ? Border.all(color: AppColors.outlineVariant) : null,
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

class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.session});

  final WorkoutSession session;

  @override
  Widget build(BuildContext context) {
    final volume = _volumeKg(session);
    final prCount = session.sets.where((s) => s.isPr).length;
    final subtitle =
        '${_fmtDurationHm(session.durationS)} · ${session.sets.length} set${session.sets.length == 1 ? '' : 's'} · ${_fmtVolume(volume)} kg';

    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.card),
      onTap: () => context.push(AppRoutes.workoutSummary(session.id)),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surfaceBase,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.outlineVariant),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.surfaceHighest, borderRadius: BorderRadius.circular(8)),
              child: Text('${session.startedAt.day}', style: AppTypography.mono(size: 13, weight: FontWeight.w700)),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(session.label, style: AppTypography.body(size: 14, weight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: AppTypography.mono(size: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
            if (prCount > 0) ...[
              BadgePill('$prCount PR', color: AppColors.accentAmber),
              const SizedBox(width: 8),
            ],
            _formScoreBadge(session),
          ],
        ),
      ),
    );
  }
}
