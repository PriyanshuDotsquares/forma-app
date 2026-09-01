import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/design_system/design_system.dart';
import '../data/achievements_providers.dart';
import '../domain/achievement.dart';
import '../domain/achievement_icons.dart';
import 'widgets/achievement_badge.dart';

const _preferredCategoryOrder = ['consistency', 'strength', 'volume'];

/// Categories present in the data, in a sensible fixed order, with the
/// synthetic "secret" bucket always excluded — secret achievements only
/// reveal themselves once unlocked, so they never get their own filter.
List<String> _deriveCategories(List<UserAchievement> all) {
  final present = all.map((a) => a.achievement.category).toSet()..remove('secret');
  final ordered = [for (final c in _preferredCategoryOrder) if (present.contains(c)) c];
  final rest = present.difference(ordered.toSet()).toList()..sort();
  return [...ordered, ...rest];
}

String _categoryLabel(String category) {
  if (category.isEmpty) return category;
  return category[0].toUpperCase() + category.substring(1);
}

/// Never surfaces the real title/description for a locked secret
/// achievement — that's the entire point of `isSecret`.
String _displayTitle(UserAchievement ua) => (ua.achievement.isSecret && !ua.isUnlocked) ? '???' : ua.achievement.title;

String _fmtNum(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

int _unlockedCount(List<UserAchievement> all) => all.where((a) => a.isUnlocked).length;

class AchievementsListScreen extends ConsumerStatefulWidget {
  const AchievementsListScreen({super.key});

  @override
  ConsumerState<AchievementsListScreen> createState() => _AchievementsListScreenState();
}

class _AchievementsListScreenState extends ConsumerState<AchievementsListScreen> {
  String? _selectedCategory; // null = "All"

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(userAchievementsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Achievements'),
        actions: [
          if (async.hasValue)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.md),
              child: Center(
                child: Text(
                  '${_unlockedCount(async.value!)}/${async.value!.length}',
                  style: AppTypography.mono(size: 14, weight: FontWeight.w600, color: AppColors.textSecondary),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, st) => Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: FormaEmptyState(
              icon: Icons.error_outline,
              title: "That didn't work",
              message: 'Could not load achievements. Try again.',
              primaryLabel: 'Retry',
              onPrimary: () => ref.invalidate(userAchievementsProvider),
            ),
          ),
          data: (all) => _buildBody(context, all),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, List<UserAchievement> all) {
    if (all.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: FormaEmptyState(
          icon: Icons.emoji_events_outlined,
          title: 'No achievements yet',
          message: 'Complete workouts to start unlocking badges.',
        ),
      );
    }

    final categories = _deriveCategories(all);
    final filtered = _selectedCategory == null
        ? all
        : all.where((a) => a.achievement.category == _selectedCategory).toList();

    final unlocked = filtered.where((a) => a.isUnlocked).toList()..sort((a, b) => b.unlockedAt!.compareTo(a.unlockedAt!));
    final recent = unlocked.take(3).toList();
    final now = DateTime.now();
    final newCount = unlocked.where((a) => now.difference(a.unlockedAt!) <= const Duration(days: 7)).length;

    final inProgress = filtered.where((a) => !a.isUnlocked && a.progressValue > 0).toList()
      ..sort((a, b) => b.progressFraction.compareTo(a.progressFraction));

    final locked = filtered.where((a) => !a.isUnlocked && a.progressValue <= 0).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xxl),
      children: [
        _CategoryChips(
          categories: categories,
          selected: _selectedCategory,
          onSelected: (c) => setState(() => _selectedCategory = c),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (recent.isNotEmpty) ...[
          SectionLabel(
            'Recently unlocked',
            trailing: newCount > 0 ? BadgePill('$newCount New', color: AppColors.accentGreen) : null,
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final ua in recent) _RecentCard(ua: ua),
          const SizedBox(height: AppSpacing.md),
        ],
        if (inProgress.isNotEmpty) ...[
          const SectionLabel('In progress'),
          const SizedBox(height: AppSpacing.sm),
          for (final ua in inProgress) _InProgressRow(ua: ua),
          const SizedBox(height: AppSpacing.md),
        ],
        if (locked.isNotEmpty) ...[
          const SectionLabel('Locked'),
          const SizedBox(height: AppSpacing.sm),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: AppSpacing.sm,
            crossAxisSpacing: AppSpacing.sm,
            childAspectRatio: 1.2,
            children: [for (final ua in locked) _LockedCard(ua: ua)],
          ),
        ],
        if (recent.isEmpty && inProgress.isEmpty && locked.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: AppSpacing.xl),
            child: FormaEmptyState(
              icon: Icons.filter_alt_off_outlined,
              title: 'Nothing here',
              message: 'No achievements match this filter yet.',
            ),
          ),
      ],
    );
  }
}

class _CategoryChips extends StatelessWidget {
  const _CategoryChips({required this.categories, required this.selected, required this.onSelected});

  final List<String> categories;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          ChoiceChip(
            label: const Text('All'),
            selected: selected == null,
            showCheckmark: false,
            onSelected: (_) => onSelected(null),
          ),
          for (final c in categories) ...[
            const SizedBox(width: AppSpacing.sm),
            ChoiceChip(
              label: Text(_categoryLabel(c)),
              selected: selected == c,
              showCheckmark: false,
              onSelected: (_) => onSelected(c),
            ),
          ],
        ],
      ),
    );
  }
}

class _RecentCard extends StatelessWidget {
  const _RecentCard({required this.ua});
  final UserAchievement ua;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceBase,
        borderRadius: BorderRadius.circular(AppRadius.card),
        // Gold border distinguishes a recently-unlocked card from the
        // neutral-bordered in-progress/locked ones below — same amber tint
        // `AchievementBadge` already uses for its unlocked ring.
        border: Border.all(color: AppColors.accentAmber.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          AchievementBadge(icon: achievementIcon(ua.achievement.icon)),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_displayTitle(ua), style: AppTypography.body(size: 15, weight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  ua.unlockedAt != null ? DateFormat.yMMMd().format(ua.unlockedAt!) : '',
                  style: AppTypography.body(size: 12, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InProgressRow extends StatelessWidget {
  const _InProgressRow({required this.ua});
  final UserAchievement ua;

  @override
  Widget build(BuildContext context) {
    final pct = (ua.progressFraction * 100).round();
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceBase,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AchievementBadge(icon: achievementIcon(ua.achievement.icon), unlocked: false, size: 40),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(_displayTitle(ua), style: AppTypography.body(size: 14, weight: FontWeight.w600))),
                    Text(
                      '$pct%',
                      style: AppTypography.mono(size: 13, weight: FontWeight.w600, color: AppColors.accentBlue),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${_fmtNum(ua.progressValue)} / ${_fmtNum(ua.targetValue)}',
                  style: AppTypography.body(size: 12, color: AppColors.textMuted),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: ua.progressFraction,
                    minHeight: 6,
                    backgroundColor: AppColors.surfaceHighest,
                    color: AppColors.accentBlue,
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

class _LockedCard extends StatelessWidget {
  const _LockedCard({required this.ua});
  final UserAchievement ua;

  @override
  Widget build(BuildContext context) {
    final secret = ua.achievement.isSecret;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceBase.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              AchievementBadge(
                icon: secret ? Icons.help_outline : achievementIcon(ua.achievement.icon),
                unlocked: false,
                size: 36,
              ),
              const Icon(Icons.lock_outline, size: 16, color: AppColors.textMuted),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            _displayTitle(ua),
            style: AppTypography.body(size: 13, weight: FontWeight.w600, color: AppColors.textSecondary),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (secret) ...[
            const SizedBox(height: 4),
            const BadgePill('SECRET', color: AppColors.textMuted, outlined: true),
          ],
        ],
      ),
    );
  }
}
