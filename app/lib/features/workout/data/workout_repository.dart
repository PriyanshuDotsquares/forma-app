import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../domain/workout_session.dart';

class WorkoutRepository {
  WorkoutRepository(this._client);

  final ApiClient _client;

  Future<WorkoutSession> startSession({String? programDayId, String label = 'Workout'}) async {
    try {
      final response = await _client.dio.post(
        '/workouts/sessions',
        data: {if (programDayId != null) 'program_day_id': programDayId, 'label': label},
      );
      return WorkoutSession.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<List<WorkoutSession>> listSessions({int skip = 0, int limit = 20}) async {
    try {
      final response = await _client.dio.get('/workouts/sessions', queryParameters: {'skip': skip, 'limit': limit});
      return (response.data as List).map((e) => WorkoutSession.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<WorkoutSession> getSession(String sessionId) async {
    try {
      final response = await _client.dio.get('/workouts/sessions/$sessionId');
      return WorkoutSession.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<void> deleteSession(String sessionId) async {
    try {
      await _client.dio.delete('/workouts/sessions/$sessionId');
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<WorkoutSet> logSet(
    String sessionId, {
    required String exerciseId,
    required int setIndex,
    String setType = 'normal',
    double? targetWeightKg,
    int? targetReps,
    double? actualWeightKg,
    int? actualReps,
    double? rpe,
    int? formScore,
    double? depthPct,
  }) async {
    try {
      final response = await _client.dio.post(
        '/workouts/sessions/$sessionId/sets',
        data: {
          'exercise_id': exerciseId,
          'set_index': setIndex,
          'set_type': setType,
          'target_weight_kg': targetWeightKg,
          'target_reps': targetReps,
          'actual_weight_kg': actualWeightKg,
          'actual_reps': actualReps,
          'rpe': rpe,
          'form_score': formScore,
          'depth_pct': depthPct,
        },
      );
      return WorkoutSet.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<void> deleteSet(String setId) async {
    try {
      await _client.dio.delete('/workouts/sets/$setId');
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<WorkoutSession> finishSession(
    String sessionId, {
    int? durationS,
    int? calories,
    double? rpe,
    int? mood,
    String? notes,
  }) async {
    try {
      final response = await _client.dio.post(
        '/workouts/sessions/$sessionId/finish',
        data: {'duration_s': durationS, 'calories': calories, 'rpe': rpe, 'mood': mood, 'notes': notes},
      );
      return WorkoutSession.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
