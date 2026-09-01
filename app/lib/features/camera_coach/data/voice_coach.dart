import 'package:flutter_tts/flutter_tts.dart';

import '../../auth/domain/user.dart';

enum _Verbosity { off, minimal, standard, detailed }

_Verbosity _parseVerbosity(String value) {
  switch (value) {
    case 'off':
      return _Verbosity.off;
    case 'minimal':
      return _Verbosity.minimal;
    case 'detailed':
      return _Verbosity.detailed;
    case 'standard':
    default:
      return _Verbosity.standard;
  }
}

/// Wraps `flutter_tts` behind FORMA's [VoiceCoachSettings] (see
/// `features/auth/domain/user.dart`) so the rest of the app never talks to
/// `FlutterTts` directly. Two things this class is responsible for beyond
/// just forwarding to the plugin:
///
/// 1. Turning [VoiceCoachSettings.verbosity] into an actual rate limit in
///    front of [speak] — "detailed" narrates close to every cue, "standard"
///    holds corrections to roughly one every few seconds plus a set
///    summary, "minimal" only speaks the first cue of a set (safety-
///    critical cues always get through, regardless of verbosity), and
///    "off"/`enabled: false` speaks nothing at all.
/// 2. Keeping [duckMusic] as inert, documented state — see its doc comment
///    for why we don't attempt to act on it.
class VoiceCoach {
  VoiceCoach({FlutterTts? tts}) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;
  VoiceCoachSettings _settings = const VoiceCoachSettings();
  DateTime? _lastSpokenAt;
  String? _lastText;
  int _cuesThisSet = 0;

  VoiceCoachSettings get settings => _settings;

  /// Whether the user asked FORMA to duck background music while coaching
  /// speaks. Exposed purely as a getter for UI (e.g. a small icon) to read
  /// — there is no reliable, permission-less way to duck *another app's*
  /// audio session from a foreground `flutter_tts` call on either iOS or
  /// Android, so this class does not attempt it. Faking a ducked-audio
  /// indicator without actually lowering anything would be worse than not
  /// showing one.
  bool get duckMusic => _settings.duckMusic;

  /// Applies [settings] — call whenever the user's voice-coach preferences
  /// change (including once, at the start of a coached set).
  Future<void> configure({required VoiceCoachSettings settings}) async {
    _settings = settings;
    await _tts.setVolume(settings.volume.clamp(0.0, 1.0));
    // flutter_tts has no concept of FORMA's catalog voice ids (e.g.
    // "alex_en_gb" from VoiceCoachSettings.voice) — those are meant for a
    // hypothetical server-rendered voice catalog, not a platform TTS voice
    // name, so there's nothing meaningful to pass to setVoice() here. We
    // only apply the settings flutter_tts can actually act on.
    await _tts.setSpeechRate(0.5);
  }

  /// Speaks [text], subject to the verbosity rate-limiter described on the
  /// class doc. [interrupt] stops whatever is currently playing first.
  /// [isSafetyCritical] bypasses the rate limiter entirely (but still
  /// respects `enabled: false` / verbosity `off` — a fully-muted coach
  /// stays muted) for things like "stop, that's too heavy" style cues.
  Future<void> speak(String text, {bool interrupt = false, bool isSafetyCritical = false}) async {
    if (!_settings.enabled) return;
    final verbosity = _parseVerbosity(_settings.verbosity);
    if (verbosity == _Verbosity.off) return;
    if (!isSafetyCritical && !_shouldSpeak(verbosity, text)) return;

    if (interrupt || isSafetyCritical) {
      await _tts.stop();
    }
    _lastSpokenAt = DateTime.now();
    _lastText = text;
    _cuesThisSet += 1;
    await _tts.speak(text);
  }

  /// Announces a completed rep number (e.g. spoken as "3"), gated only by
  /// [VoiceCoachSettings.countReps] and `off`/disabled — distinct from
  /// [speak]'s corrective-cue rate limiter since rep counts are short,
  /// expected, and rhythmic rather than a correction competing for
  /// attention.
  Future<void> announceRep(int index) async {
    if (!_settings.enabled || !_settings.countReps) return;
    if (_parseVerbosity(_settings.verbosity) == _Verbosity.off) return;
    await _tts.speak('$index');
  }

  /// Speaks an encouragement line (e.g. "Nice lockout") only if the user
  /// has [VoiceCoachSettings.encouragement] enabled — still subject to the
  /// normal rate limiter so encouragement doesn't crowd out corrections.
  Future<void> speakEncouragement(String text) async {
    if (!_settings.encouragement) return;
    await speak(text);
  }

  /// Resets the per-set cue counter used by "minimal" verbosity — call this
  /// when a new set starts.
  void resetSetCounters() {
    _cuesThisSet = 0;
    _lastText = null;
  }

  bool _shouldSpeak(_Verbosity verbosity, String text) {
    final now = DateTime.now();
    switch (verbosity) {
      case _Verbosity.off:
        return false;
      case _Verbosity.minimal:
        // Only the very first cue of the set gets spoken.
        return _cuesThisSet == 0;
      case _Verbosity.standard:
        // Roughly one correction every 8 seconds, so the coach doesn't
        // talk over every rep.
        return _lastSpokenAt == null || now.difference(_lastSpokenAt!) > const Duration(seconds: 8);
      case _Verbosity.detailed:
        // Nearly every cue, but de-duplicate identical back-to-back text
        // and enforce a small floor so we don't talk over ourselves.
        return _lastText != text && (_lastSpokenAt == null || now.difference(_lastSpokenAt!) > const Duration(seconds: 2));
    }
  }

  Future<void> dispose() async {
    await _tts.stop();
  }
}
