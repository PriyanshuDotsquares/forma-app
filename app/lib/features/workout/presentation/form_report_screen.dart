import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/network/api_exception.dart';
import '../domain/workout_session.dart';
import 'workout_providers.dart';

String _qualityLabel(double score) {
  if (score >= 80) return 'SOLID';
  if (score >= 60) return 'GOOD';
  return 'NEEDS WORK';
}

Color _qualityColor(double score) {
  if (score >= 80) return AppColors.accentGreen;
  if (score >= 60) return AppColors.accentAmber;
  return AppColors.accentRed;
}

Color _depthColor(double pct) {
  if (pct >= 90) return AppColors.accentGreen;
  if (pct >= 70) return AppColors.accentAmber;
  return AppColors.accentRed;
}

/// Per-exercise form breakdown for one finished session. Every number here
/// comes straight from `WorkoutSet.formScore` / `.depthPct` — there is no
/// per-rep tempo or joint-angle data captured anywhere in this app, so
/// sections that would need it (a tempo curve, named form-fault clips) are
/// left out entirely rather than invented.
class FormReportScreen extends ConsumerStatefulWidget {
  const FormReportScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<FormReportScreen> createState() => _FormReportScreenState();
}

class _FormReportScreenState extends ConsumerState<FormReportScreen> {
  String? _exerciseId;

  @override
  Widget build(BuildContext context) {
    final sessionAsync = ref.watch(sessionProvider(widget.sessionId));
    final recentAsync = ref.watch(sessionListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('FORM REPORT')),
      body: SafeArea(
        child: sessionAsync.when(
          loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          error: (error, stack) => Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: FormaEmptyState(
              icon: Icons.error_outline,
              title: "Couldn't load this report.",
              message: error is ApiException ? error.message : 'Something went wrong.',
              primaryLabel: 'RETRY',
              onPrimary: () => ref.invalidate(sessionProvider(widget.sessionId)),
            ),
          ),
          data: (session) => _Body(
            session: session,
            recentSessions: recentAsync.valueOrNull ?? const [],
            selectedExerciseId: _exerciseId,
            onExerciseChanged: (id) => setState(() => _exerciseId = id),
          ),
        ),
      ),
    );
  }
}

class _ScoredExercise {
  const _ScoredExercise(this.exerciseId, this.name, this.sets);
  final String exerciseId;
  final String name;
  final List<WorkoutSet> sets;
}

List<_ScoredExercise> _scoredExercises(WorkoutSession session) {
  final byId = <String, _ScoredExercise>{};
  final order = <String>[];
  for (final set in session.sets) {
    if (set.formScore == null && set.depthPct == null) continue;
    if (!byId.containsKey(set.exerciseId)) {
      order.add(set.exerciseId);
      byId[set.exerciseId] = _ScoredExercise(set.exerciseId, set.exercise.name, []);
    }
    byId[set.exerciseId]!.sets.add(set);
  }
  return [for (final id in order) byId[id]!];
}

class _Body extends StatelessWidget {
  const _Body({
    required this.session,
    required this.recentSessions,
    required this.selectedExerciseId,
    required this.onExerciseChanged,
  });

  final WorkoutSession session;
  final List<WorkoutSession> recentSessions;
  final String? selectedExerciseId;
  final ValueChanged<String?> onExerciseChanged;

  @override
  Widget build(BuildContext context) {
    final scored = _scoredExercises(session);
    if (scored.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: Center(
          child: FormaEmptyState(
            icon: Icons.show_chart,
            title: 'No form data for this session',
            message: 'Coach a set with the camera on and its form report will show up here.',
          ),
        ),
      );
    }

    final selected = scored.firstWhere(
      (e) => e.exerciseId == selectedExerciseId,
      orElse: () => scored.first,
    );
    final sets = [...selected.sets]..sort((a, b) => a.setIndex.compareTo(b.setIndex));

    final scores = [for (final s in sets) if (s.formScore != null) s.formScore!.toDouble()];
    final avgForm = scores.isEmpty ? null : scores.reduce((a, b) => a + b) / scores.length;
    final formDelta = avgForm == null ? null : _formDeltaVsLastTime(selected.exerciseId, avgForm, recentSessions, session.id);

    final depths = [for (final s in sets) if (s.depthPct != null) s.depthPct!];
    final avgDepth = depths.isEmpty ? null : depths.reduce((a, b) => a + b) / depths.length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xxl),
      children: [
        if (scored.length > 1) ...[
          _ExercisePicker(exercises: scored, selectedId: selected.exerciseId, onChanged: onExerciseChanged),
          const SizedBox(height: AppSpacing.lg),
        ],
        if (avgForm != null) _FormScoreCard(avgForm: avgForm, delta: formDelta, sets: sets),
        if (avgForm != null) const SizedBox(height: AppSpacing.lg),
        if (depths.isNotEmpty) _DepthByRepCard(sets: sets, avgDepth: avgDepth!),
        if (depths.isNotEmpty) const SizedBox(height: AppSpacing.lg),
        const SectionLabel('WHAT CAME UP'),
        const SizedBox(height: AppSpacing.sm),
        ..._whatCameUp(sets, scores, depths),
      ],
    );
  }
}

double? _formDeltaVsLastTime(String exerciseId, double avgForm, List<WorkoutSession> recent, String currentSessionId) {
  for (final other in recent) {
    if (other.id == currentSessionId || !other.isFinished) continue;
    final otherScores = [
      for (final s in other.sets)
        if (s.exerciseId == exerciseId && s.formScore != null) s.formScore!.toDouble(),
    ];
    if (otherScores.isEmpty) continue;
    final otherAvg = otherScores.reduce((a, b) => a + b) / otherScores.length;
    return avgForm - otherAvg;
  }
  return null;
}

class _ExercisePicker extends StatelessWidget {
  const _ExercisePicker({required this.exercises, required this.selectedId, required this.onChanged});

  final List<_ScoredExercise> exercises;
  final String selectedId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < exercises.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            _Chip(
              label: exercises[i].name,
              selected: exercises[i].exerciseId == selectedId,
              onTap: () => onChanged(exercises[i].exerciseId),
            ),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});
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
          style: AppTypography.body(size: 12, weight: FontWeight.w600, color: selected ? AppColors.accentBlueDark : AppColors.textSecondary),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: child,
    );
  }
}

class _FormScoreCard extends StatelessWidget {
  const _FormScoreCard({required this.avgForm, required this.delta, required this.sets});

  final double avgForm;
  final double? delta;
  final List<WorkoutSet> sets;

  @override
  Widget build(BuildContext context) {
    final color = _qualityColor(avgForm);
    return _Card(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(avgForm.round().toString(), style: AppTypography.mono(size: 64, weight: FontWeight.w600).copyWith(letterSpacing: -2)),
              const SizedBox(width: AppSpacing.sm),
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('FORM SCORE', style: AppTypography.body(size: 13, color: AppColors.textSecondary)),
                    const SizedBox(height: 4),
                    BadgePill(_qualityLabel(avgForm), color: color, outlined: true),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 40,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < sets.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  _ScoreBar(score: sets[i].formScore),
                ],
                if (delta != null) ...[
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '${delta! >= 0 ? '+' : ''}${delta!.round()}',
                      style: AppTypography.mono(size: 12, weight: FontWeight.w600, color: delta! >= 0 ? AppColors.accentGreen : AppColors.accentRed),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoreBar extends StatelessWidget {
  const _ScoreBar({required this.score});
  final int? score;

  @override
  Widget build(BuildContext context) {
    final s = score;
    final value = (s ?? 0).clamp(0, 100) / 100;
    return Container(
      width: 6,
      height: (value * 40).clamp(6, 40).toDouble(),
      decoration: BoxDecoration(
        color: s == null ? AppColors.surfaceHighest : _qualityColor(s.toDouble()),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

class _DepthByRepCard extends StatelessWidget {
  const _DepthByRepCard({required this.sets, required this.avgDepth});

  final List<WorkoutSet> sets;
  final double avgDepth;

  @override
  Widget build(BuildContext context) {
    final totalReps = sets.fold<int>(0, (sum, s) => sum + (s.actualReps ?? 0));
    WorkoutSet? worst;
    for (final s in sets) {
      if (s.depthPct == null) continue;
      if (worst == null || s.depthPct! < worst.depthPct!) worst = s;
    }
    String caption;
    if (worst != null && sets.length > 1 && worst.depthPct! < avgDepth - 3) {
      caption = 'Average ${avgDepth.round()}% · dropped to ${worst.depthPct!.round()}% on set ${worst.setIndex + 1}';
    } else {
      caption = 'Average ${avgDepth.round()}% depth across ${sets.length} set${sets.length == 1 ? '' : 's'}';
    }

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('DEPTH BY REP', style: AppTypography.body(size: 14, color: AppColors.textSecondary)),
              Text('$totalReps REPS', style: AppTypography.mono(size: 14, weight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 110,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final set in sets)
                  if (set.depthPct != null)
                    for (var rep = 0; rep < (set.actualReps ?? 0); rep++) ...[
                      Expanded(
                        child: Container(
                          height: (set.depthPct!.clamp(0, 100) / 100 * 100).clamp(6, 100).toDouble(),
                          margin: const EdgeInsets.symmetric(horizontal: 1),
                          decoration: BoxDecoration(color: _depthColor(set.depthPct!), borderRadius: BorderRadius.circular(2)),
                        ),
                      ),
                    ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(caption, style: AppTypography.mono(size: 12, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

List<Widget> _whatCameUp(List<WorkoutSet> sets, List<double> scores, List<double> depths) {
  final cards = <Widget>[];

  if (scores.length >= 2) {
    final drop = scores.first - scores.last;
    if (drop >= 5) {
      cards.add(_CueCard(
        title: 'Fatigue effect',
        body: 'Your form dropped ${drop.round()} points by your last set. Consider stopping a rep earlier next time.',
        color: AppColors.accentAmber,
      ));
    }
  }

  if (depths.length >= 2) {
    final range = depths.reduce((a, b) => a > b ? a : b) - depths.reduce((a, b) => a < b ? a : b);
    if (range >= 10) {
      cards.add(_CueCard(
        title: 'Depth got less consistent',
        body: 'Your depth ranged by ${range.round()} points across sets — aim to keep it steady set to set.',
        color: AppColors.accentAmber,
      ));
    }
  }

  if (cards.isEmpty) {
    cards.add(const _CueCard(
      title: 'Consistent form',
      body: 'Your form and depth held steady across every set. Nothing to fix here.',
      color: AppColors.accentGreen,
    ));
  }

  return [for (final c in cards) Padding(padding: const EdgeInsets.only(bottom: AppSpacing.sm), child: c)];
}

class _CueCard extends StatelessWidget {
  const _CueCard({required this.title, required this.body, required this.color});

  final String title;
  final String body;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTypography.display(size: 18)),
          const SizedBox(height: 4),
          Text(body, style: AppTypography.body(size: 14, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}
