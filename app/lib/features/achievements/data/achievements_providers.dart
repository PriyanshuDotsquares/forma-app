import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/providers.dart';
import '../domain/achievement.dart';
import 'achievements_repository.dart';

/// Single source of truth for [AchievementsRepository] access — mirrors
/// `authRepositoryProvider` / `programsRepositoryProvider`. Other features
/// should import this rather than constructing their own repository instance.
final achievementsRepositoryProvider = Provider<AchievementsRepository>((ref) {
  return AchievementsRepository(ref.watch(apiClientProvider));
});

/// The signed-in user's full achievement list (locked + in-progress +
/// unlocked). Shared by the profile hub (badge row, "N/M" counts) and the
/// full achievements list screen so both stay in sync off one fetch.
final userAchievementsProvider = FutureProvider.autoDispose<List<UserAchievement>>((ref) {
  return ref.watch(achievementsRepositoryProvider).listAchievements();
});

/// The signed-in user's personal records — used for the PRs stat tile and
/// could back a records list in a future pass.
final personalRecordsProvider = FutureProvider.autoDispose<List<PersonalRecord>>((ref) {
  return ref.watch(achievementsRepositoryProvider).listRecords();
});
