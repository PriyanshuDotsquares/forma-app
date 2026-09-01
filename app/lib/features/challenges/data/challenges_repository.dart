import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../domain/challenge.dart';

class ChallengesRepository {
  ChallengesRepository(this._client);

  final ApiClient _client;

  Future<List<UserChallenge>> listChallenges() async {
    try {
      final response = await _client.dio.get('/challenges');
      return (response.data as List).map((e) => UserChallenge.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<UserChallenge> join(String challengeId) async {
    try {
      final response = await _client.dio.post('/challenges/$challengeId/join');
      return UserChallenge.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<void> leave(String challengeId) async {
    try {
      await _client.dio.post('/challenges/$challengeId/leave');
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<List<LeaderboardEntry>> leaderboard(String challengeId) async {
    try {
      final response = await _client.dio.get('/challenges/$challengeId/leaderboard');
      return (response.data as List).map((e) => LeaderboardEntry.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
