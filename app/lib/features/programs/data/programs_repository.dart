import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../domain/exercise.dart';
import '../domain/program.dart';

class ProgramsRepository {
  ProgramsRepository(this._client);

  final ApiClient _client;

  Future<List<Exercise>> listExercises({String? search, String? muscle, String? equipment}) async {
    try {
      final response = await _client.dio.get(
        '/exercises',
        queryParameters: {
          if (search != null && search.isNotEmpty) 'search': search,
          if (muscle != null) 'muscle': muscle,
          if (equipment != null) 'equipment': equipment,
          'limit': 100,
        },
      );
      return (response.data as List).map((e) => Exercise.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<Exercise> getExercise(String exerciseId) async {
    try {
      final response = await _client.dio.get('/exercises/$exerciseId');
      return Exercise.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<Program> generateProgram({
    String? goal,
    String? experienceLevel,
    int? daysPerWeek,
    int? sessionMinutes,
    String? splitPreference,
    List<String>? equipment,
  }) async {
    try {
      final response = await _client.dio.post(
        '/programs/generate',
        data: {
          if (goal != null) 'goal': goal,
          if (experienceLevel != null) 'experience_level': experienceLevel,
          if (daysPerWeek != null) 'days_per_week': daysPerWeek,
          if (sessionMinutes != null) 'session_minutes': sessionMinutes,
          if (splitPreference != null) 'split_preference': splitPreference,
          if (equipment != null) 'equipment': equipment,
        },
      );
      return Program.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<Program?> getActiveProgram() async {
    try {
      final response = await _client.dio.get('/programs/active');
      return Program.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      throw ApiException.fromDioException(e);
    }
  }

  Future<List<Program>> listPrograms() async {
    try {
      final response = await _client.dio.get('/programs');
      return (response.data as List).map((e) => Program.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<void> deleteProgram(String programId) async {
    try {
      await _client.dio.delete('/programs/$programId');
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<ProgramDay> addDay(
    String programId, {
    required int orderIndex,
    int? weekday,
    required String label,
    List<String> muscleTags = const [],
    bool isRest = false,
    int? estimatedMinutes,
  }) async {
    try {
      final response = await _client.dio.post(
        '/programs/$programId/days',
        data: {
          'order_index': orderIndex,
          'weekday': weekday,
          'label': label,
          'muscle_tags': muscleTags,
          'is_rest': isRest,
          'estimated_minutes': estimatedMinutes,
        },
      );
      return ProgramDay.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<ProgramDay> updateDay(String dayId, Map<String, dynamic> patch) async {
    try {
      final response = await _client.dio.patch('/programs/days/$dayId', data: patch);
      return ProgramDay.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<void> deleteDay(String dayId) async {
    try {
      await _client.dio.delete('/programs/days/$dayId');
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// "Let AI fill this day" — appends exercises the backend's plan-builder
  /// heuristic picks for the day's existing muscle tags/equipment, on top
  /// of whatever's already there.
  Future<ProgramDay> fillDay(String dayId) async {
    try {
      final response = await _client.dio.post('/programs/days/$dayId/fill');
      return ProgramDay.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<ProgramExercise> addExerciseToDay(
    String dayId, {
    required String exerciseId,
    required int orderIndex,
    int sets = 3,
    int repRangeLow = 8,
    int repRangeHigh = 12,
    String loadType = 'weight',
    double? targetValue,
    String? tempo,
    String? supersetGroup,
    String? notes,
    bool coachWithCamera = false,
  }) async {
    try {
      final response = await _client.dio.post(
        '/programs/days/$dayId/exercises',
        data: {
          'exercise_id': exerciseId,
          'order_index': orderIndex,
          'sets': sets,
          'rep_range_low': repRangeLow,
          'rep_range_high': repRangeHigh,
          'load_type': loadType,
          'target_value': targetValue,
          'tempo': tempo,
          'superset_group': supersetGroup,
          'notes': notes,
          'coach_with_camera': coachWithCamera,
        },
      );
      return ProgramExercise.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<ProgramExercise> updateProgramExercise(String programExerciseId, Map<String, dynamic> patch) async {
    try {
      final response = await _client.dio.patch('/programs/exercises/$programExerciseId', data: patch);
      return ProgramExercise.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<void> removeProgramExercise(String programExerciseId) async {
    try {
      await _client.dio.delete('/programs/exercises/$programExerciseId');
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
