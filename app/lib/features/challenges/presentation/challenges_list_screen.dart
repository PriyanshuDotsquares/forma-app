import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/network/api_exception.dart';
import '../../achievements/domain/achievement_icons.dart';
import '../data/challenges_providers.dart';
import '../domain/challenge.dart';

String _periodLabel(String period) {
  switch (period) {
    case 'weekly':
      return 'THIS WEEK';
    case 'monthly':
      return 'THIS MONTH';
    default:
      return 'ONGOING';
  }
}

String _metricUnit(String metric) {
  switch (metric) {
    case 'volume_kg':
      return 'kg';
    case 'streak_days':
      return 'days';
    default:
      return 'sessions';
  }
}

String _fmtNum(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

class ChallengesListScreen extends ConsumerWidget {
  const ChallengesListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(challengesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Challenges')),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, st) => Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: FormaEmptyState(
              icon: Icons.error_outline,
              title: "That didn't work",
              message: err is ApiException ? err.message : 'Could not load challenges.',
              primaryLabel: 'Retry',
              onPrimary: () => ref.invalidate(challengesProvider),
            ),
          ),
          data: (all) => _buildBody(context, ref, all),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, WidgetRef ref, List<UserChallenge> all) {
    if (all.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: FormaEmptyState(
          icon: Icons.flag_outlined,
          title: 'No challenges yet',
          message: 'Check back soon.',
        ),
      );
    }

    final joined = all.where((c) => c.joined).toList();
    final available = all.where((c) => !c.joined).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xxl),
      children: [
        if (joined.isNotEmpty) ...[
          const SectionLabel('Your challenges'),
          const SizedBox(height: AppSpacing.sm),
          for (final uc in joined) _ChallengeCard(uc: uc),
          const SizedBox(height: AppSpacing.md),
        ],
        if (available.isNotEmpty) ...[
          const SectionLabel('Available'),
          const SizedBox(height: AppSpacing.sm),
          for (final uc in available) _ChallengeCard(uc: uc),
        ],
      ],
    );
  }
}

class _ChallengeCard extends ConsumerStatefulWidget {
  const _ChallengeCard({required this.uc});
  final UserChallenge uc;

  @override
  ConsumerState<_ChallengeCard> createState() => _ChallengeCardState();
}

class _ChallengeCardState extends ConsumerState<_ChallengeCard> {
  bool _busy = false;

  Future<void> _toggleJoin() async {
    setState(() => _busy = true);
    final repository = ref.read(challengesRepositoryProvider);
    try {
      if (widget.uc.joined) {
        await repository.leave(widget.uc.challenge.id);
      } else {
        await repository.join(widget.uc.challenge.id);
      }
      ref.invalidate(challengesProvider);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : 'Could not update this challenge.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showLeaderboard() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _LeaderboardSheet(challenge: widget.uc.challenge),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uc = widget.uc;
    final challenge = uc.challenge;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceBase,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: uc.isCompleted ? AppColors.accentGreen.withValues(alpha: 0.5) : AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: uc.isCompleted ? AppColors.accentGreen.withValues(alpha: 0.15) : AppColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.outlineVariant),
                ),
                child: Icon(achievementIcon(challenge.icon), size: 20, color: uc.isCompleted ? AppColors.accentGreen : AppColors.textSecondary),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(challenge.title, style: AppTypography.body(size: 15, weight: FontWeight.w600))),
                        BadgePill(_periodLabel(challenge.period), color: AppColors.textMuted, outlined: true),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(challenge.description, style: AppTypography.body(size: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          if (uc.joined) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: uc.progressFraction,
                      minHeight: 6,
                      backgroundColor: AppColors.surfaceHighest,
                      color: uc.isCompleted ? AppColors.accentGreen : AppColors.accentBlue,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  '${_fmtNum(uc.progressValue)}/${_fmtNum(challenge.targetValue)} ${_metricUnit(challenge.metric)}',
                  style: AppTypography.mono(size: 11, color: AppColors.textSecondary),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              if (challenge.isGroup) ...[
                TextButton(onPressed: _showLeaderboard, child: const Text('LEADERBOARD')),
                const Spacer(),
              ] else
                const Spacer(),
              SizedBox(
                height: 32,
                child: uc.joined
                    ? OutlinedButton(
                        onPressed: _busy ? null : _toggleJoin,
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md)),
                        child: Text(_busy ? '…' : 'LEAVE'),
                      )
                    : FilledButton(
                        onPressed: _busy ? null : _toggleJoin,
                        style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md)),
                        child: Text(_busy ? '…' : 'JOIN'),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LeaderboardSheet extends ConsumerWidget {
  const _LeaderboardSheet({required this.challenge});
  final Challenge challenge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.watch(challengesRepositoryProvider);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: FutureBuilder<List<LeaderboardEntry>>(
        future: repository.leaderboard(challenge.id),
        builder: (context, snapshot) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(challenge.title, style: AppTypography.display(size: 20)),
              const SizedBox(height: AppSpacing.xs),
              Text('LEADERBOARD', style: AppTypography.body(size: 11, weight: FontWeight.w700, color: AppColors.textMuted).copyWith(letterSpacing: 1.0)),
              const SizedBox(height: AppSpacing.md),
              if (snapshot.connectionState != ConnectionState.done)
                const Padding(padding: EdgeInsets.all(AppSpacing.lg), child: Center(child: CircularProgressIndicator()))
              else if (snapshot.hasError)
                Text('Could not load the leaderboard.', style: AppTypography.body(color: AppColors.textMuted))
              else if ((snapshot.data ?? const []).isEmpty)
                Text('Nobody has joined yet — be the first.', style: AppTypography.body(color: AppColors.textMuted))
              else
                for (final entry in snapshot.data!)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 28,
                          child: Text('#${entry.rank}', style: AppTypography.mono(size: 13, color: AppColors.textMuted)),
                        ),
                        Expanded(
                          child: Text(
                            entry.isMe ? '${entry.displayName} (you)' : entry.displayName,
                            style: AppTypography.body(size: 14, weight: entry.isMe ? FontWeight.w700 : FontWeight.w500),
                          ),
                        ),
                        Text(
                          '${_fmtNum(entry.progressValue)} ${_metricUnit(challenge.metric)}',
                          style: AppTypography.mono(size: 13, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
              const SizedBox(height: AppSpacing.sm),
            ],
          );
        },
      ),
    );
  }
}
