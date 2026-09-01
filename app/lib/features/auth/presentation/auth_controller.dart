import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/providers.dart';
import '../data/auth_repository.dart';
import '../domain/user.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(apiClientProvider));
});

/// Holds the current user (null = signed out). Starts by checking whether a
/// token is already stored (e.g. app relaunch) and validating it against
/// the backend.
class AuthController extends AsyncNotifier<User?> {
  @override
  Future<User?> build() async {
    final repository = ref.watch(authRepositoryProvider);
    final client = ref.watch(apiClientProvider);
    client.onUnauthorized = () => state = const AsyncData(null);
    // Must run before the stored-token check below — on iOS a token can
    // survive a full app deletion via the Keychain (see the method's own
    // doc comment), so a "fresh" reinstall would otherwise auto-login with
    // a stale session instead of showing intro/sign-in.
    await client.clearStaleTokenOnFreshInstall();

    if (!await repository.hasStoredToken()) return null;
    try {
      return await repository.fetchMe();
    } catch (_) {
      await repository.logout();
      return null;
    }
  }

  Future<void> login({required String email, required String password}) async {
    final repository = ref.read(authRepositoryProvider);
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => repository.login(email: email, password: password));
  }

  Future<void> register({required String email, required String password, String? fullName}) async {
    final repository = ref.read(authRepositoryProvider);
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => repository.register(email: email, password: password, fullName: fullName),
    );
  }

  Future<void> updateProfile({
    String? fullName,
    String? avatarUrl,
    String? units,
    int? restTimerDefaultS,
    Map<String, dynamic>? voiceCoach,
    Map<String, dynamic>? notificationPrefs,
    String? locale,
  }) async {
    final repository = ref.read(authRepositoryProvider);
    final updated = await repository.updateProfile(
      fullName: fullName,
      avatarUrl: avatarUrl,
      units: units,
      restTimerDefaultS: restTimerDefaultS,
      voiceCoach: voiceCoach,
      notificationPrefs: notificationPrefs,
      locale: locale,
    );
    state = AsyncData(updated);
  }

  Future<void> changePassword({required String currentPassword, required String newPassword}) async {
    final repository = ref.read(authRepositoryProvider);
    final updated = await repository.changePassword(currentPassword: currentPassword, newPassword: newPassword);
    state = AsyncData(updated);
  }

  Future<void> changeEmail({required String newEmail, required String password}) async {
    final repository = ref.read(authRepositoryProvider);
    final updated = await repository.changeEmail(newEmail: newEmail, password: password);
    state = AsyncData(updated);
  }

  Future<void> submitOnboarding(Map<String, dynamic> payload) async {
    final repository = ref.read(authRepositoryProvider);
    final updated = await repository.submitOnboarding(payload);
    state = AsyncData(updated);
  }

  Future<void> logout() async {
    await ref.read(authRepositoryProvider).logout();
    state = const AsyncData(null);
  }
}

final authControllerProvider = AsyncNotifierProvider<AuthController, User?>(AuthController.new);
