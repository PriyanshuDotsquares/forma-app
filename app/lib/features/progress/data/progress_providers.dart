import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/providers.dart';
import '../../programs/domain/exercise.dart';
import '../../programs/presentation/programs_providers.dart';
import '../domain/progress_models.dart';
import 'progress_repository.dart';

/// Single source of truth for [ProgressRepository] access — mirrors
/// `authRepositoryProvider` in the auth feature.
final progressRepositoryProvider = Provider<ProgressRepository>((ref) {
  return ProgressRepository(ref.watch(apiClientProvider));
});

/// Below: thin `FutureProvider.family` wrappers per repository call so the
/// progress screens can `ref.watch` a period/filter directly and get an
/// `AsyncValue` with built-in caching + auto-refetch when the filter changes,
/// rather than every screen hand-rolling its own fetch-on-didUpdateWidget.

final progressSummaryProvider = FutureProvider.autoDispose.family<ProgressSummary, String>((ref, period) {
  return ref.watch(progressRepositoryProvider).summary(period: period);
});

final volumeByMuscleProvider = FutureProvider.autoDispose.family<List<VolumeByMuscle>, String>((ref, period) {
  return ref.watch(progressRepositoryProvider).volumeByMuscle(period: period);
});

final volumeTrendProvider = FutureProvider.autoDispose.family<List<VolumeTrendPoint>, String>((ref, period) {
  return ref.watch(progressRepositoryProvider).volumeTrend(period: period);
});

final recoveryProvider = FutureProvider.autoDispose<List<RecoveryItem>>((ref) {
  return ref.watch(progressRepositoryProvider).recovery();
});

typedef StrengthTrendParams = ({String exerciseId, String period});

final strengthTrendProvider = FutureProvider.autoDispose.family<List<StrengthPoint>, StrengthTrendParams>((ref, params) {
  return ref.watch(progressRepositoryProvider).strengthTrend(exerciseId: params.exerciseId, period: params.period);
});

typedef FormQualityParams = ({String period, String? exerciseId});

final formQualityTrendProvider = FutureProvider.autoDispose.family<List<FormQualityPoint>, FormQualityParams>((
  ref,
  params,
) {
  return ref.watch(progressRepositoryProvider).formQualityTrend(period: params.period, exerciseId: params.exerciseId);
});

typedef ConsistencyParams = ({int year, int month});

final consistencyCalendarProvider = FutureProvider.autoDispose.family<List<ConsistencyDay>, ConsistencyParams>((
  ref,
  params,
) {
  return ref.watch(progressRepositoryProvider).consistencyCalendar(year: params.year, month: params.month);
});

/// Single-exercise lookup — used to resolve a PR's/strength-trend's exercise
/// name for display. Not achievements- or programs-specific, so it lives
/// here rather than forcing every caller to depend on the programs feature
/// directly.
final exerciseByIdProvider = FutureProvider.autoDispose.family<Exercise, String>((ref, exerciseId) {
  return ref.watch(programsRepositoryProvider).getExercise(exerciseId);
});

/// Small exercise list for the form-quality exercise picker.
final exerciseListProvider = FutureProvider.autoDispose<List<Exercise>>((ref) {
  return ref.watch(programsRepositoryProvider).listExercises();
});
