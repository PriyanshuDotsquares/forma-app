import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../domain/achievement.dart';

class AchievementsRepository {
  AchievementsRepository(this._client);

  final ApiClient _client;

  Future<List<UserAchievement>> listAchievements() async {
    try {
      final response = await _client.dio.get('/achievements');
      return (response.data as List).map((e) => UserAchievement.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<List<PersonalRecord>> listRecords() async {
    try {
      final response = await _client.dio.get('/records');
      return (response.data as List).map((e) => PersonalRecord.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
