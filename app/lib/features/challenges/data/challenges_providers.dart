import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/providers.dart';
import '../domain/challenge.dart';
import 'challenges_repository.dart';

final challengesRepositoryProvider = Provider<ChallengesRepository>((ref) {
  return ChallengesRepository(ref.watch(apiClientProvider));
});

/// Every active challenge plus this user's join-status/progress on each —
/// shared by the challenges list and the Profile tab's "N ACTIVE" badge.
final challengesProvider = FutureProvider.autoDispose<List<UserChallenge>>((ref) {
  return ref.watch(challengesRepositoryProvider).listChallenges();
});
