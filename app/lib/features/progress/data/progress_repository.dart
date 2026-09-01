import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../domain/progress_models.dart';

class ProgressRepository {
  ProgressRepository(this._client);

  final ApiClient _client;

  Future<ProgressSummary> summary({String period = 'month'}) async {
    try {
      final response = await _client.dio.get('/progress/summary', queryParameters: {'period': period});
      return ProgressSummary.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<List<VolumeByMuscle>> volumeByMuscle({String period = 'month'}) async {
    try {
      final response = await _client.dio.get('/progress/volume/by-muscle', queryParameters: {'period': period});
      return (response.data as List).map((e) => VolumeByMuscle.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<List<VolumeTrendPoint>> volumeTrend({String period = 'month'}) async {
    try {
      final response = await _client.dio.get('/progress/volume/trend', queryParameters: {'period': period});
      return (response.data as List).map((e) => VolumeTrendPoint.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<List<RecoveryItem>> recovery() async {
    try {
      final response = await _client.dio.get('/progress/recovery');
      return (response.data as List).map((e) => RecoveryItem.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<List<StrengthPoint>> strengthTrend({required String exerciseId, String period = 'year'}) async {
    try {
      final response = await _client.dio.get(
        '/progress/strength',
        queryParameters: {'exercise_id': exerciseId, 'period': period},
      );
      return (response.data as List).map((e) => StrengthPoint.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Throws [ApiException] with statusCode 402 when the caller isn't on
  /// FORMA Pro — the UI should catch that and show the paywall.
  Future<List<FormQualityPoint>> formQualityTrend({String period = '3month', String? exerciseId}) async {
    try {
      final response = await _client.dio.get(
        '/progress/form-quality',
        queryParameters: {'period': period, if (exerciseId != null) 'exercise_id': exerciseId},
      );
      return (response.data as List).map((e) => FormQualityPoint.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<List<ConsistencyDay>> consistencyCalendar({required int year, required int month}) async {
    try {
      final response = await _client.dio.get('/progress/consistency', queryParameters: {'year': year, 'month': month});
      return (response.data as List).map((e) => ConsistencyDay.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
