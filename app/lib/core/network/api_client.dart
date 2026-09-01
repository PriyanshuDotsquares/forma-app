import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/env.dart';

const _authTokenKey = 'auth_token';
const _installMarkerKey = 'forma_install_marker';

/// Thin wrapper around [Dio] configured for the FORMA API.
class ApiClient {
  ApiClient({Dio? dio, FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage(),
      dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: Env.apiBaseUrl,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 15),
            ),
          ) {
    this.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _storage.read(key: _authTokenKey);
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          if (error.response?.statusCode == 401) {
            await clearToken();
            onUnauthorized?.call();
          }
          handler.next(error);
        },
      ),
    );
  }

  final Dio dio;
  final FlutterSecureStorage _storage;

  /// Invoked whenever a request comes back 401 — the caller (auth layer)
  /// hooks in here to reset app-wide auth state.
  void Function()? onUnauthorized;

  Future<void> saveToken(String token) => _storage.write(key: _authTokenKey, value: token);

  Future<String?> readToken() => _storage.read(key: _authTokenKey);

  Future<void> clearToken() => _storage.delete(key: _authTokenKey);

  /// iOS's Keychain (what `flutter_secure_storage` writes to under the
  /// hood) survives a full app deletion — unlike every other kind of local
  /// storage on the device. Delete FORMA, reinstall it, and a stale auth
  /// token can still be sitting there, silently logging the "fresh" install
  /// straight back in instead of showing the intro/sign-in flow.
  /// `SharedPreferences` genuinely does get wiped on delete, so its absence
  /// is a reliable "this is a fresh install" signal — used here to
  /// proactively clear any Keychain-orphaned token before it's ever read.
  /// Android's Keystore-backed storage doesn't have this problem, but
  /// running this unconditionally is harmless there too.
  Future<void> clearStaleTokenOnFreshInstall() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_installMarkerKey) == true) return;
    await clearToken();
    await prefs.setBool(_installMarkerKey, true);
  }
}
