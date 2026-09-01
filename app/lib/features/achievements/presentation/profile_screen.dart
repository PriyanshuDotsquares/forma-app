import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/network/providers.dart';
import '../../../core/router/app_router.dart';
import '../../auth/domain/user.dart';
import '../../auth/presentation/auth_controller.dart';
// Read-only import of the workout feature's existing repository/domain
// types — see `_workoutStatsProvider` below for why this doesn't add a
// shared `workoutRepositoryProvider` inside that (actively in-progress)
// feature folder.
import '../../challenges/data/challenges_providers.dart';
import '../../progress/data/progress_providers.dart';
import '../../workout/data/workout_repository.dart';
import '../data/achievements_providers.dart';
import '../domain/achievement_icons.dart';
import '../domain/leveling.dart';
import 'widgets/achievement_badge.dart';
import 'widgets/profile_nav_row.dart';

/// Lightweight aggregate for the profile header's WORKOUTS/VOLUME/TIME
/// stat tiles.
class _WorkoutStats {
  const _WorkoutStats({required this.workouts, required this.volumeKg, required this.totalSeconds});
  final int workouts;
  final double volumeKg;
  final int totalSeconds;
}

/// There's no `/workouts/summary` aggregate endpoint, so this pulls a
/// bounded page of recent sessions (the API caps `limit` at 100 server
/// side) and sums client-side. Deliberately constructs `WorkoutRepository`
/// directly rather than adding a shared `workoutRepositoryProvider` inside
/// `lib/features/workout/` — that folder belongs to the workout/camera
/// agent building in parallel, so this stays self-contained instead of
/// risking a naming collision or editing files outside this feature's scope.
final _workoutStatsProvider = FutureProvider.autoDispose<_WorkoutStats>((ref) async {
  final repo = WorkoutRepository(ref.watch(apiClientProvider));
  final sessions = await repo.listSessions(limit: 100);
  final finished = sessions.where((s) => s.isFinished).toList();
  final totalSeconds = finished.fold<int>(0, (sum, s) => sum + (s.durationS ?? 0));
  final totalVolumeKg = finished.fold<double>(0, (sum, s) {
    return sum + s.sets.fold<double>(0, (setSum, set) => setSum + (set.actualWeightKg ?? 0) * (set.actualReps ?? 0));
  });
  return _WorkoutStats(workouts: finished.length, volumeKg: totalVolumeKg, totalSeconds: totalSeconds);
});

/// The "PROFILE" tab: an achievements-header + navigation-hub screen (not
/// the settings form itself — that's a separate screen reached via the
/// "Settings" row below).
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).valueOrNull;

    return Scaffold(
      body: SafeArea(
        child: user == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xxl),
                children: [
                  _Header(user: user),
                  const SizedBox(height: AppSpacing.lg),
                  _ProfileCard(user: user),
                  const SizedBox(height: AppSpacing.lg),
                  const _StatsGrid(),
                  const SizedBox(height: AppSpacing.lg),
                  const _BadgesRow(),
                  const SizedBox(height: AppSpacing.lg),
                  _NavList(user: user),
                ],
              ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.user});
  final User user;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text('Achievements', style: AppTypography.display(size: 26)),
        _Avatar(user: user, size: 40),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.user, this.size = 40});
  final User user;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = user.avatarUrl;
    return ClipOval(
      child: Container(
        width: size,
        height: size,
        color: AppColors.surfaceHigh,
        alignment: Alignment.center,
        child: (url != null && url.isNotEmpty)
            ? CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                width: size,
                height: size,
                errorWidget: (context, url, error) => Icon(Icons.person, color: AppColors.textMuted, size: size * 0.55),
                placeholder: (context, url) => SizedBox(
                  width: size * 0.4,
                  height: size * 0.4,
                  child: const CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : Icon(Icons.person, color: AppColors.textMuted, size: size * 0.55),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.user});
  final User user;

  String get _displayName {
    final name = user.fullName;
    if (name != null && name.trim().isNotEmpty) return name;
    return user.email.split('@').first;
  }

  @override
  Widget build(BuildContext context) {
    final level = LevelProgress.fromXp(user.xp);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceBase,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        children: [
          _Avatar(user: user, size: 72),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  _displayName,
                  style: AppTypography.display(size: 20),
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
              if (user.isPro) ...[const SizedBox(width: AppSpacing.sm), const BadgePill('PRO')],
            ],
          ),
          // The design shows a "Member since {month year}" line here, but
          // `User` has no `createdAt` — `/users/me` doesn't expose an
          // account-creation timestamp on the client model. Rather than
          // fabricate a date, that line is omitted until the backend adds
          // one (would need `created_at` on `UserRead`).
          const SizedBox(height: AppSpacing.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'LEVEL ${level.level}',
                style: AppTypography.body(
                  size: 12,
                  weight: FontWeight.w700,
                  color: AppColors.textMuted,
                ).copyWith(letterSpacing: 1.0),
              ),
              Text(
                '${level.xpIntoLevel} / ${level.xpForNextLevel} XP',
                style: AppTypography.mono(size: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: level.fraction,
              minHeight: 8,
              backgroundColor: AppColors.surfaceHighest,
              color: AppColors.accentBlue,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsGrid extends ConsumerWidget {
  const _StatsGrid();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(_workoutStatsProvider).valueOrNull;
    final prCount = ref.watch(personalRecordsProvider).valueOrNull?.length;

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: AppSpacing.sm,
      crossAxisSpacing: AppSpacing.sm,
      childAspectRatio: 1.8,
      children: [
        StatTile(label: 'Workouts', value: stats?.workouts.toString() ?? '—'),
        StatTile(
          label: 'Volume',
          value: stats != null ? _formatVolume(stats.volumeKg) : '—',
          unit: stats != null ? 'kg' : null,
        ),
        StatTile(label: 'Time', value: stats != null ? _formatDuration(stats.totalSeconds) : '—'),
        StatTile(label: 'PRs', value: prCount?.toString() ?? '—'),
      ],
    );
  }
}

String _formatVolume(double kg) {
  if (kg >= 1000000) return '${(kg / 1000000).toStringAsFixed(2)}M';
  if (kg >= 1000) return '${(kg / 1000).toStringAsFixed(1)}k';
  return kg.toStringAsFixed(0);
}

String _formatDuration(int seconds) {
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  if (hours > 0) return '${hours}h ${minutes}m';
  return '${minutes}m';
}

class _BadgesRow extends ConsumerWidget {
  const _BadgesRow();

  static const _maxShown = 5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(userAchievementsProvider).valueOrNull;
    final unlocked = (list ?? const []).where((a) => a.isUnlocked).toList()
      ..sort((a, b) => b.unlockedAt!.compareTo(a.unlockedAt!));
    final shown = unlocked.take(_maxShown).toList();
    final overflow = unlocked.length - shown.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(
          'Badges',
          trailing: GestureDetector(
            onTap: () => context.push(AppRoutes.achievements),
            child: Text(
              'See all',
              style: AppTypography.body(size: 13, weight: FontWeight.w600, color: AppColors.accentBlue),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (list == null)
          const SizedBox(height: 44)
        else if (shown.isEmpty)
          Text(
            'No badges unlocked yet — get training.',
            style: AppTypography.body(size: 13, color: AppColors.textMuted),
          )
        else
          Row(
            children: [
              for (final ua in shown) ...[
                AchievementBadge(icon: achievementIcon(ua.achievement.icon)),
                const SizedBox(width: AppSpacing.sm),
              ],
              if (overflow > 0)
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.surfaceHigh,
                    border: Border.all(color: AppColors.outlineVariant),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '+$overflow',
                    style: AppTypography.mono(size: 12, weight: FontWeight.w600, color: AppColors.textSecondary),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _NavList extends ConsumerWidget {
  const _NavList({required this.user});
  final User user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(userAchievementsProvider).valueOrNull;
    final unlockedCount = list?.where((a) => a.isUnlocked).length;
    final totalCount = list?.length;
    final level = LevelProgress.fromXp(user.xp);
    // `streak_days` is computed once on the backend (`compute_streak_days`)
    // and shared by the progress summary — reuse it rather than duplicating
    // `today_screen.dart`'s client-side streak calculation. Not period-
    // filtered server-side, so any period value returns the same streak.
    final streak = ref.watch(progressSummaryProvider('month')).valueOrNull?.streakDays;
    final activeChallenges = ref.watch(challengesProvider).valueOrNull?.where((c) => c.joined).length;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceBase,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Column(
        children: [
          ProfileNavRow(
            icon: Icons.emoji_events_outlined,
            label: 'Achievements',
            trailingText: (unlockedCount != null && totalCount != null) ? '$unlockedCount/$totalCount' : '—',
            onTap: () => context.push(AppRoutes.achievements),
          ),
          const Divider(height: 1),
          ProfileNavRow(
            icon: Icons.bolt_outlined,
            label: 'Level & XP',
            trailingText: 'Level ${level.level}',
            onTap: () => _showLevelSheet(context, level, user.xp),
          ),
          const Divider(height: 1),
          ProfileNavRow(
            icon: Icons.local_fire_department_outlined,
            label: 'Streak',
            trailingText: streak != null ? '$streak ${streak == 1 ? 'day' : 'days'}' : '—',
            onTap: () => _showInfoDialog(
              context,
              title: 'Streak',
              message: streak == null
                  ? 'Could not load your streak right now.'
                  : streak > 0
                  ? "You've trained $streak day${streak == 1 ? '' : 's'} in a row. Keep it going."
                  : 'No active streak yet — log a workout today to start one.',
            ),
          ),
          const Divider(height: 1),
          ProfileNavRow(
            icon: Icons.flag_outlined,
            label: 'Challenges',
            trailing: BadgePill('${activeChallenges ?? 0} ACTIVE', color: AppColors.textMuted, outlined: true),
            onTap: () => context.push(AppRoutes.challenges),
          ),
          const Divider(height: 1),
          ProfileNavRow(
            icon: Icons.forum_outlined,
            label: 'Ask the Coach',
            trailing: const BadgePill('AI'),
            onTap: () => context.go(AppRoutes.coach),
          ),
          const Divider(height: 1),
          ProfileNavRow(
            icon: Icons.settings_outlined,
            label: 'Settings',
            onTap: () => context.push(AppRoutes.settings),
          ),
        ],
      ),
    );
  }
}

void _showLevelSheet(BuildContext context, LevelProgress level, int xp) {
  showModalBottomSheet(
    context: context,
    builder: (context) => Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('Level & XP'),
          const SizedBox(height: AppSpacing.md),
          Text('Level ${level.level}', style: AppTypography.display(size: 30)),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${level.xpIntoLevel} / ${level.xpForNextLevel} XP to next level',
            style: AppTypography.body(size: 14, color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: level.fraction, minHeight: 8, backgroundColor: AppColors.surfaceHighest),
          ),
          const SizedBox(height: AppSpacing.md),
          Text('Total XP earned: $xp', style: AppTypography.mono(size: 13, color: AppColors.textMuted)),
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    ),
  );
}

void _showInfoDialog(BuildContext context, {required String title, required String message}) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))],
    ),
  );
}
