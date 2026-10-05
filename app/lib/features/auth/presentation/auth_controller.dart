import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
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
  /// Shortest time the splash stays up on launch (and on a retry from the
  /// "couldn't connect" screen). The session check is usually well under a
  /// second, which flashed the wordmark too briefly to register; this holds it
  /// on screen for a fixed minimum. It never shortens a slow check — the splash
  /// stays until the check finishes, however long that takes.
  static const Duration minSplashDuration = Duration(milliseconds: 2500);

  @override
  Future<User?> build() async {
    final minimumShown = Future<void>.delayed(minSplashDuration);
    try {
      return await _resolveSession();
    } finally {
      // Also on failure, so the retry screen doesn't flash up early either.
      await minimumShown;
    }
  }

  Future<User?> _resolveSession() async {
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
    } catch (e) {
      // Only a genuine 401 means the token itself is invalid/expired —
      // that's a real "you need to sign in again". Anything else (a
      // timeout, no connection, the backend being unreachable — this app's
      // API is hosted on Render, whose free tier can take well over this
      // client's timeout to wake from sleep) is a transient failure to
      // *verify* the session, not proof the session is bad. Wiping the
      // token here would force a fresh login every time the app happens to
      // reopen during a network hiccup; keeping it means the next launch
      // (or a retry) can silently succeed once connectivity/the backend
      // recovers.
      if (e is ApiException && e.isUnauthorized) {
        await repository.logout();
        return null;
      }
      rethrow;
    }
  }

  Future<void> login({required String email, required String password}) {
    final repository = ref.read(authRepositoryProvider);
    return _authenticate(() => repository.login(email: email, password: password));
  }

  Future<void> register({required String email, required String password, String? fullName}) {
    final repository = ref.read(authRepositoryProvider);
    return _authenticate(() => repository.register(email: email, password: password, fullName: fullName));
  }

  /// A rejected sign-in/sign-up (wrong password, email already registered,
  /// no connection) is a failed *attempt*, not a failed session check, so it
  /// must not be stored as `AsyncError` — the router reads that as "couldn't
  /// verify your session" and bounces to the splash retry screen, hiding the
  /// real reason. Reset to signed-out and rethrow so `AuthScreen` shows the
  /// error inline.
  Future<void> _authenticate(Future<User> Function() attempt) async {
    state = const AsyncLoading();
    try {
      state = AsyncData(await attempt());
    } catch (_) {
      state = const AsyncData(null);
      rethrow;
    }
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
