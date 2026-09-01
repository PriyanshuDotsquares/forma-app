import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../domain/user.dart';

class AuthRepository {
  AuthRepository(this._client);

  final ApiClient _client;

  Future<bool> hasStoredToken() async => (await _client.readToken()) != null;

  Future<User> register({required String email, required String password, String? fullName}) async {
    try {
      await _client.dio.post(
        '/auth/register',
        data: {'email': email, 'password': password, if (fullName != null && fullName.isNotEmpty) 'full_name': fullName},
      );
      return login(email: email, password: password);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<User> login({required String email, required String password}) async {
    try {
      final response = await _client.dio.post(
        '/auth/login',
        data: FormData.fromMap({'username': email, 'password': password}),
      );
      final token = response.data['access_token'] as String;
      await _client.saveToken(token);
      return fetchMe();
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<User> fetchMe() async {
    try {
      final response = await _client.dio.get('/users/me');
      return User.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<User> updateProfile({
    String? fullName,
    String? avatarUrl,
    String? units,
    int? restTimerDefaultS,
    Map<String, dynamic>? voiceCoach,
    Map<String, dynamic>? notificationPrefs,
    String? locale,
  }) async {
    try {
      final response = await _client.dio.patch(
        '/users/me',
        data: {
          if (fullName != null) 'full_name': fullName,
          if (avatarUrl != null) 'avatar_url': avatarUrl,
          if (units != null) 'units': units,
          if (restTimerDefaultS != null) 'rest_timer_default_s': restTimerDefaultS,
          if (voiceCoach != null) 'voice_coach': voiceCoach,
          if (notificationPrefs != null) 'notification_prefs': notificationPrefs,
          if (locale != null) 'locale': locale,
        },
      );
      return User.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Returns the confirmation message plus, only when no SMTP is configured
  /// server-side, a dev-mode reset token echoed back so the flow is
  /// testable without a real inbox — see `debug_token` handling on
  /// `POST /auth/password-reset/request`.
  Future<({String message, String? debugToken})> requestPasswordReset(String email) async {
    try {
      final response = await _client.dio.post('/auth/password-reset/request', data: {'email': email});
      final data = response.data as Map<String, dynamic>;
      return (message: data['message'] as String, debugToken: data['debug_token'] as String?);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<void> confirmPasswordReset({required String token, required String newPassword}) async {
    try {
      await _client.dio.post('/auth/password-reset/confirm', data: {'token': token, 'new_password': newPassword});
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<User> changePassword({required String currentPassword, required String newPassword}) async {
    try {
      final response = await _client.dio.post(
        '/users/me/change-password',
        data: {'current_password': currentPassword, 'new_password': newPassword},
      );
      return User.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<User> changeEmail({required String newEmail, required String password}) async {
    try {
      final response = await _client.dio.post(
        '/users/me/change-email',
        data: {'new_email': newEmail, 'password': password},
      );
      return User.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<User> submitOnboarding(Map<String, dynamic> payload) async {
    try {
      final response = await _client.dio.patch('/onboarding', data: payload);
      return User.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<void> logout() => _client.clearToken();
}
