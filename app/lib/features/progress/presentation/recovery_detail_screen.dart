import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/design_system.dart';
import '../../programs/domain/program.dart';
import '../../programs/presentation/active_program_controller.dart';
import '../data/progress_providers.dart';
import '../domain/progress_models.dart';
import 'widgets/progress_card.dart';
import 'widgets/progress_format.dart';
import 'widgets/recovery_silhouette.dart';

class RecoveryDetailScreen extends ConsumerStatefulWidget {
  const RecoveryDetailScreen({super.key});

  @override
  ConsumerState<RecoveryDetailScreen> createState() => _RecoveryDetailScreenState();
}

class _RecoveryDetailScreenState extends ConsumerState<RecoveryDetailScreen> {
  bool _isFront = true;

  @override
  Widget build(BuildContext context) {
    final recoveryAsync = ref.watch(recoveryProvider);
    // Best-effort, same spirit as TodayController's recovery fetch — the
    // program is only used to sharpen the suggestion text, so a slow/failed
    // fetch should never block the rest of this screen from rendering.
    final todayDay = _todayProgramDay(ref.watch(activeProgramControllerProvider).valueOrNull);

    return Scaffold(
      appBar: AppBar(
        title: const Text('RECOVERY'),
        actions: [
          IconButton(
            tooltip: 'How this is estimated',
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showExplainer(context),
          ),
        ],
      ),
      body: SafeArea(
        child: recoveryAsync.when(
          data: (items) =>
              _Content(items: items, isFront: _isFront, todayDay: todayDay, onToggle: (v) => setState(() => _isFront = v)),
          loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          error: (e, st) => Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: FormaEmptyState(icon: Icons.error_outline, title: "Couldn't load recovery", message: friendlyErrorMessage(e)),
          ),
        ),
      ),
    );
  }

  void _showExplainer(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('HOW RECOVERY IS ESTIMATED'),
        content: Text(
          "This isn't a physiological measurement. It's an estimate of the time since you last trained each muscle "
          'group, relative to a typical recovery window for that group. Treat it as a rough guide for balancing your '
          "training, not a medical read on how your muscles actually feel.",
          style: AppTypography.body(size: 13, color: AppColors.textSecondary),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('GOT IT'))],
      ),
    );
  }
}

/// Today's scheduled program day, if any — mirrors the weekday conversion
/// `today_screen.dart`'s `_Content._dayForWeekday` uses (Dart: 1=Mon..7=Sun
/// -> API: 0=Mon..6=Sun), kept local here since it's a three-line lookup,
/// not shared plumbing.
ProgramDay? _todayProgramDay(Program? program) {
  if (program == null) return null;
  final apiWeekday = DateTime.now().weekday - 1;
  for (final day in program.days) {
    if (day.weekday == apiWeekday) return day;
  }
  return null;
}

class _Content extends StatelessWidget {
  const _Content({required this.items, required this.isFront, required this.todayDay, required this.onToggle});

  final List<RecoveryItem> items;
  final bool isFront;
  final ProgramDay? todayDay;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: FormaEmptyState(
          icon: Icons.self_improvement,
          title: 'No training data yet',
          message: 'Log a workout and your per-muscle recovery will show up here.',
        ),
      );
    }

    final pctByMuscle = {for (final i in items) i.muscleGroup.toLowerCase(): i.recoveredPct};
    final sorted = [...items]..sort((a, b) => a.recoveredPct.compareTo(b.recoveredPct));

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xxl),
      children: [
        _ViewToggle(isFront: isFront, onChanged: onToggle),
        const SizedBox(height: AppSpacing.lg),
        Center(child: RecoverySilhouette(pctByMuscle: pctByMuscle, isFront: isFront)),
        const SizedBox(height: AppSpacing.lg),
        _Legend(),
        const SizedBox(height: AppSpacing.lg),
        InfoBanner(title: 'SUGGESTION', body: _suggestion(sorted), icon: Icons.lightbulb_outline),
        const SizedBox(height: AppSpacing.xl),
        const SectionLabel('ALL MUSCLE GROUPS'),
        const SizedBox(height: AppSpacing.sm),
        ProgressCard(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Column(
            children: [
              for (final item in sorted) ...[
                _RecoveryItemRow(item: item),
                if (item != sorted.last) const Divider(height: 1),
              ],
            ],
          ),
        ),
      ],
    );
  }

  String _suggestion(List<RecoveryItem> sorted) {
    final day = todayDay;
    if (day == null || day.isRest || day.muscleTags.isEmpty) return _generalSuggestion(sorted);

    final byMuscle = {for (final i in sorted) i.muscleGroup.toLowerCase(): i};
    final targeted = [for (final tag in day.muscleTags) if (byMuscle[tag.toLowerCase()] != null) byMuscle[tag.toLowerCase()]!];
    if (targeted.isEmpty) return _generalSuggestion(sorted);

    targeted.sort((a, b) => a.recoveredPct.compareTo(b.recoveredPct));
    final worstPct = targeted.first.recoveredPct;
    final verdict = worstPct >= 80
        ? 'fits well'
        : worstPct >= 50
            ? 'is workable'
            : 'might be a stretch — consider easing off intensity';

    String qualifierFor(double pct) => pct >= 80 ? 'fully recovered' : pct >= 50 ? 'workable' : 'needs another day';
    final clauses = [
      for (final item in targeted.take(2))
        '${titleCaseMuscle(item.muscleGroup)} at ${item.recoveredPct.toStringAsFixed(0)}% (${qualifierFor(item.recoveredPct)})',
    ];
    final detail = clauses.length == 2 ? '${clauses[0]} and ${clauses[1]}' : clauses.first;
    final closing = worstPct >= 50 ? 'Stick to the plan.' : 'Consider an easier session today.';

    return "Today's ${day.label} session $verdict — $detail. $closing";
  }

  String _generalSuggestion(List<RecoveryItem> sorted) {
    final least = sorted.first;
    if (least.recoveredPct >= 85) {
      return "You're fresh across the board — a good day to push intensity wherever you like.";
    }
    return '${titleCaseMuscle(least.muscleGroup)} is your least-recovered group at '
        '${least.recoveredPct.toStringAsFixed(0)}% — consider training something else today.';
  }
}

class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.isFront, required this.onChanged});

  final bool isFront;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: AppColors.surfaceHigh, borderRadius: BorderRadius.circular(AppRadius.button)),
      child: Row(
        children: [
          Expanded(child: _ToggleTab(label: 'FRONT', selected: isFront, onTap: () => onChanged(true))),
          Expanded(child: _ToggleTab(label: 'BACK', selected: !isFront, onTap: () => onChanged(false))),
        ],
      ),
    );
  }
}

class _ToggleTab extends StatelessWidget {
  const _ToggleTab({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.button - 4),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: AppTypography.body(
            size: 13,
            weight: FontWeight.w700,
            color: selected ? AppColors.accentBlueDark : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Text('0%', style: AppTypography.mono(size: 11, color: AppColors.textMuted)),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                height: 8,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  gradient: const LinearGradient(
                    colors: [AppColors.accentRed, AppColors.accentAmber, AppColors.accentGreen],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text('100%', style: AppTypography.mono(size: 11, color: AppColors.textMuted)),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'RECOVERED',
          style: AppTypography.body(size: 11, weight: FontWeight.w700, color: AppColors.textMuted).copyWith(letterSpacing: 1.2),
        ),
      ],
    );
  }
}

class _RecoveryItemRow extends StatelessWidget {
  const _RecoveryItemRow({required this.item});

  final RecoveryItem item;

  @override
  Widget build(BuildContext context) {
    final color = recoveryColor(item.recoveredPct);
    final ready = item.recoveredPct >= 100 || item.freshInHours == null || item.freshInHours! <= 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titleCaseMuscle(item.muscleGroup), style: AppTypography.body(size: 14, weight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  'Last trained ${formatRelativeDate(item.lastTrained)} · ${item.setsLastSession} sets',
                  style: AppTypography.body(size: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${item.recoveredPct.toStringAsFixed(0)}%',
                style: AppTypography.mono(size: 15, weight: FontWeight.w700, color: color),
              ),
              const SizedBox(height: 2),
              Text(
                ready ? 'Ready' : 'fresh in ~${item.freshInHours!.toStringAsFixed(0)}h',
                style: AppTypography.body(size: 11, color: AppColors.textMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
