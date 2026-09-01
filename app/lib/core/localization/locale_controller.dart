import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const supportedLocales = [Locale('en'), Locale('hi')];
const _prefsKey = 'forma_locale';

/// The app's current UI locale. Seeded from whatever was persisted locally
/// on a previous launch (fast — no network needed before first paint);
/// `setLocale` updates both that local copy and, when signed in, the
/// account's `locale` field via the caller (see `LanguageScreen`) so the
/// choice follows the user across devices too.
class LocaleController extends Notifier<Locale> {
  @override
  Locale build() {
    _restore();
    return const Locale('en');
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_prefsKey);
    if (code != null && supportedLocales.any((l) => l.languageCode == code)) {
      state = Locale(code);
    }
  }

  Future<void> setLocale(String languageCode) async {
    state = Locale(languageCode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, languageCode);
  }
}

final localeControllerProvider = NotifierProvider<LocaleController, Locale>(LocaleController.new);
