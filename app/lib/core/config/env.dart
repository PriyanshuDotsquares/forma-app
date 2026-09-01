import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;

/// Runtime configuration for the app.
///
/// Override at build/run time with:
///   flutter run --dart-define=API_BASE_URL=http://localhost:8000/api/v1
///
/// A physical device (Android or iOS) can't reach the host machine via
/// `localhost` OR `10.0.2.2` — it needs the host's actual LAN IP, e.g.:
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.23:8000/api/v1
class Env {
  Env._();

  static const String _override = String.fromEnvironment('API_BASE_URL');

  /// The Android emulator's own `localhost` is the emulator, not the host
  /// machine — `10.0.2.2` is the documented alias Android provides for the
  /// host's loopback interface. Every other target this app runs on (iOS
  /// simulator, macOS, web) already resolves `localhost` to the host
  /// machine, so only the Android-emulator case needs a different default.
  static String get apiBaseUrl {
    if (_override.isNotEmpty) return _override;
    if (!kIsWeb && Platform.isAndroid) return 'http://10.0.2.2:8000/api/v1';
    return 'http://localhost:8000/api/v1';
  }
}

