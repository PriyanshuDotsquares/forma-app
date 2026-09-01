import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/achievements/presentation/achievements_list_screen.dart';
import '../../features/achievements/presentation/profile_screen.dart';
import '../../features/auth/presentation/auth_controller.dart';
import '../../features/auth/presentation/auth_screen.dart';
import '../../features/auth/presentation/forgot_password_screen.dart';
import '../../features/auth/presentation/reset_password_screen.dart';
import '../../features/challenges/presentation/challenges_list_screen.dart';
import '../../features/dashboard/presentation/today_screen.dart';
import '../../features/onboarding/presentation/intro_screen.dart';
import '../../features/onboarding/presentation/onboarding_flow_screen.dart';
import '../../features/onboarding/presentation/plan_preview_screen.dart';
import '../../features/onboarding/presentation/save_your_plan_screen.dart';
import '../../features/onboarding/presentation/splash_screen.dart';
import '../../features/programs/presentation/day_editor_screen.dart';
import '../../features/programs/presentation/exercise_detail_screen.dart';
import '../../features/programs/presentation/exercise_library_screen.dart';
import '../../features/programs/presentation/plan_overview_screen.dart';
import '../../features/programs/presentation/session_preview_screen.dart';
import '../../features/progress/presentation/consistency_detail_screen.dart';
import '../../features/progress/presentation/form_quality_detail_screen.dart';
import '../../features/progress/presentation/progress_hub_screen.dart';
import '../../features/progress/presentation/recovery_detail_screen.dart';
import '../../features/progress/presentation/volume_detail_screen.dart';
import '../../features/settings/presentation/language_screen.dart';
import '../../features/settings/presentation/premium_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/settings/presentation/voice_coach_settings_screen.dart';
import '../../features/workout/presentation/active_workout_screen.dart';
import '../../features/workout/presentation/camera_precheck_screen.dart';
import '../../features/workout/presentation/coach_entry_screen.dart';
import '../../features/workout/presentation/form_report_screen.dart';
import '../../features/workout/presentation/workout_history_screen.dart';
import '../../features/workout/presentation/workout_summary_screen.dart';
import 'app_shell.dart';

/// Route paths as plain constants so screens can navigate without
/// hand-typing strings — import this class rather than literal paths.
class AppRoutes {
  AppRoutes._();

  static const splash = '/splash';
  static const intro = '/intro';
  static const auth = '/auth';
  static const forgotPassword = '/auth/forgot-password';
  static const resetPassword = '/auth/reset-password';
  static const onboarding = '/onboarding';
  static const onboardingPlanPreview = '/onboarding/plan-preview';
  static const onboardingSavePlan = '/onboarding/save-plan';

  static const today = '/today';

  static const plan = '/plan';
  static String planDay(String dayId) => '/plan/day/$dayId';
  static const planExercises = '/plan/exercises';
  static String planExerciseDetail(String exerciseId) => '/plan/exercises/$exerciseId';
  static String planSessionPreview(String dayId) => '/plan/session/$dayId';
  static const planHistory = '/plan/history';

  static const coach = '/coach';
  static String workoutCameraPrecheck(String sessionId, {String? programExerciseId}) =>
      '/workout/camera-precheck/$sessionId${programExerciseId != null ? '?exerciseId=$programExerciseId' : ''}';
  static String workoutActive(String sessionId) => '/workout/active/$sessionId';
  static String workoutSummary(String sessionId) => '/workout/summary/$sessionId';
  static String workoutFormReport(String sessionId) => '/workout/form-report/$sessionId';

  static const progress = '/progress';
  static const progressVolume = '/progress/volume';
  static const progressRecovery = '/progress/recovery';
  static const progressFormQuality = '/progress/form-quality';
  static const progressConsistency = '/progress/consistency';

  static const profile = '/profile';
  static const achievements = '/profile/achievements';
  static const challenges = '/profile/challenges';
  static const settings = '/profile/settings';
  static const voiceCoachSettings = '/profile/settings/voice-coach';
  static const languageSettings = '/profile/settings/language';
  static const premium = '/profile/premium';
}

/// Bridges `authControllerProvider` into a `Listenable` for `refreshListenable`
/// below. `routerProvider` must build its `GoRouter` exactly once — if it
/// `ref.watch`ed auth state directly, every auth change would hand
/// `MaterialApp.router` a brand-new `GoRouter` instance, which resets
/// navigation back to `initialLocation` and clobbers whatever route the app
/// was actually on (this is how a plan-generation success used to bounce
/// straight to /today instead of showing the plan-preview/save-plan screens
/// pushed a moment earlier).
class _AuthRefreshNotifier extends ChangeNotifier {
  _AuthRefreshNotifier(Ref ref) {
    ref.listen(authControllerProvider, (_, _) => notifyListeners());
  }
}

/// True from the moment `Step9Building` submits the quiz until
/// `SaveYourPlanScreen` hands off to /today. `submitOnboarding` flips
/// `onboarding_completed` to true *while the app is still sitting on
/// `/onboarding`* (the plan-preview push happens a moment later, once the
/// checklist animation and network calls both finish) — without this flag,
/// the redirect below sees "onboarded + on /onboarding" the instant that
/// happens and bounces straight to /today, skipping plan-preview and
/// save-plan entirely before they ever get a chance to show.
final onboardingPostFlowActiveProvider = StateProvider<bool>((ref) => false);

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: _AuthRefreshNotifier(ref),
    redirect: (context, state) {
      final authState = ref.read(authControllerProvider);
      final loc = state.matchedLocation;
      final loggedIn = authState.valueOrNull != null;
      final onboarded = authState.valueOrNull?.onboardingCompleted ?? false;
      final postFlowActive = ref.read(onboardingPostFlowActiveProvider);

      final isSplash = loc == AppRoutes.splash;
      final isIntro = loc == AppRoutes.intro;
      final isAuth = loc == AppRoutes.auth;
      final isAuthAdjacent = loc == AppRoutes.forgotPassword || loc == AppRoutes.resetPassword;
      final isOnboarding = loc == AppRoutes.onboarding;

      // `AuthController.login()`/`register()` set `AsyncLoading()` the
      // instant a submit starts, before the network call even resolves —
      // without the auth-screen exception here, that transient loading
      // state would bounce the user to /splash mid-attempt. If the call
      // then fails, the redirect re-evaluates from /splash (not /auth),
      // sees `!loggedIn`, and sends them to /intro instead of back to
      // /auth — so `AuthScreen` never gets a chance to show its error
      // banner (it's already been unmounted by the time `_submit()`
      // resumes). Staying put during a loading attempt on /auth itself
      // fixes both: the error banner shows, and a successful login skips
      // an unnecessary splash flash too.
      if (authState.isLoading) return (isSplash || isAuth || isAuthAdjacent) ? null : AppRoutes.splash;
      if (!loggedIn) return (isIntro || isAuth || isAuthAdjacent) ? null : AppRoutes.intro;
      if (loggedIn && !onboarded) return isOnboarding ? null : AppRoutes.onboarding;
      if (loggedIn && onboarded && (isSplash || isIntro || isAuth)) return AppRoutes.today;
      if (loggedIn && onboarded && isOnboarding && !postFlowActive) return AppRoutes.today;
      return null;
    },
    routes: [
      GoRoute(path: AppRoutes.splash, builder: (context, state) => const SplashScreen()),
      GoRoute(path: AppRoutes.intro, builder: (context, state) => const IntroScreen()),
      GoRoute(path: AppRoutes.auth, builder: (context, state) => const AuthScreen()),
      GoRoute(path: AppRoutes.forgotPassword, builder: (context, state) => const ForgotPasswordScreen()),
      GoRoute(
        path: AppRoutes.resetPassword,
        builder: (context, state) => ResetPasswordScreen(initialToken: state.uri.queryParameters['token']),
      ),
      GoRoute(path: AppRoutes.onboarding, builder: (context, state) => const OnboardingFlowScreen()),
      // Pushed on top of /onboarding once the quiz submits.
      GoRoute(path: AppRoutes.onboardingPlanPreview, builder: (context, state) => const PlanPreviewScreen()),
      GoRoute(path: AppRoutes.onboardingSavePlan, builder: (context, state) => const SaveYourPlanScreen()),

      // Full-screen flows launched from a tab — no bottom nav while active.
      GoRoute(
        path: '/workout/camera-precheck/:sessionId',
        builder: (context, state) => CameraPrecheckScreen(
          sessionId: state.pathParameters['sessionId']!,
          programExerciseId: state.uri.queryParameters['exerciseId'],
        ),
      ),
      GoRoute(
        path: '/workout/active/:sessionId',
        builder: (context, state) => ActiveWorkoutScreen(sessionId: state.pathParameters['sessionId']!),
      ),
      GoRoute(
        path: '/workout/summary/:sessionId',
        builder: (context, state) => WorkoutSummaryScreen(sessionId: state.pathParameters['sessionId']!),
      ),
      GoRoute(
        path: '/workout/form-report/:sessionId',
        builder: (context, state) => FormReportScreen(sessionId: state.pathParameters['sessionId']!),
      ),

      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: AppRoutes.today, builder: (context, state) => const TodayScreen())]),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.plan,
                builder: (context, state) => const PlanOverviewScreen(),
                routes: [
                  GoRoute(
                    path: 'day/:dayId',
                    builder: (context, state) => DayEditorScreen(dayId: state.pathParameters['dayId']!),
                  ),
                  GoRoute(path: 'exercises', builder: (context, state) => const ExerciseLibraryScreen()),
                  GoRoute(
                    path: 'exercises/:exerciseId',
                    builder: (context, state) => ExerciseDetailScreen(exerciseId: state.pathParameters['exerciseId']!),
                  ),
                  GoRoute(
                    path: 'session/:dayId',
                    builder: (context, state) => SessionPreviewScreen(dayId: state.pathParameters['dayId']!),
                  ),
                  GoRoute(path: 'history', builder: (context, state) => const WorkoutHistoryScreen()),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.progress,
                builder: (context, state) => const ProgressHubScreen(),
                routes: [
                  GoRoute(path: 'volume', builder: (context, state) => const VolumeDetailScreen()),
                  GoRoute(path: 'recovery', builder: (context, state) => const RecoveryDetailScreen()),
                  GoRoute(path: 'form-quality', builder: (context, state) => const FormQualityDetailScreen()),
                  GoRoute(path: 'consistency', builder: (context, state) => const ConsistencyDetailScreen()),
                ],
              ),
            ],
          ),
          StatefulShellBranch(routes: [GoRoute(path: AppRoutes.coach, builder: (context, state) => const CoachEntryScreen())]),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.profile,
                builder: (context, state) => const ProfileScreen(),
                routes: [
                  GoRoute(path: 'achievements', builder: (context, state) => const AchievementsListScreen()),
                  GoRoute(path: 'challenges', builder: (context, state) => const ChallengesListScreen()),
                  GoRoute(
                    path: 'settings',
                    builder: (context, state) => const SettingsScreen(),
                    routes: [
                      GoRoute(path: 'voice-coach', builder: (context, state) => const VoiceCoachSettingsScreen()),
                      GoRoute(path: 'language', builder: (context, state) => const LanguageScreen()),
                    ],
                  ),
                  GoRoute(path: 'premium', builder: (context, state) => const PremiumScreen()),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
