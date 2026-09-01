class VoiceCoachSettings {
  const VoiceCoachSettings({
    this.enabled = true,
    this.verbosity = 'standard',
    this.voice = 'alex_en_gb',
    this.countReps = false,
    this.encouragement = true,
    this.volume = 0.7,
    this.duckMusic = true,
  });

  final bool enabled;
  final String verbosity; // off | minimal | standard | detailed
  final String voice;
  final bool countReps;
  final bool encouragement;
  final double volume;
  final bool duckMusic;

  factory VoiceCoachSettings.fromJson(Map<String, dynamic> json) => VoiceCoachSettings(
    enabled: json['enabled'] as bool? ?? true,
    verbosity: json['verbosity'] as String? ?? 'standard',
    voice: json['voice'] as String? ?? 'alex_en_gb',
    countReps: json['count_reps'] as bool? ?? false,
    encouragement: json['encouragement'] as bool? ?? true,
    volume: (json['volume'] as num?)?.toDouble() ?? 0.7,
    duckMusic: json['duck_music'] as bool? ?? true,
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'verbosity': verbosity,
    'voice': voice,
    'count_reps': countReps,
    'encouragement': encouragement,
    'volume': volume,
    'duck_music': duckMusic,
  };

  VoiceCoachSettings copyWith({
    bool? enabled,
    String? verbosity,
    String? voice,
    bool? countReps,
    bool? encouragement,
    double? volume,
    bool? duckMusic,
  }) => VoiceCoachSettings(
    enabled: enabled ?? this.enabled,
    verbosity: verbosity ?? this.verbosity,
    voice: voice ?? this.voice,
    countReps: countReps ?? this.countReps,
    encouragement: encouragement ?? this.encouragement,
    volume: volume ?? this.volume,
    duckMusic: duckMusic ?? this.duckMusic,
  );
}

class Injury {
  const Injury({required this.part, required this.side, required this.severity, this.note});

  final String part; // e.g. "shoulder"
  final String side; // "left" | "right" | "both"
  final String severity; // "mild" | "moderate" | "avoid"
  final String? note;

  factory Injury.fromJson(Map<String, dynamic> json) => Injury(
    part: json['part'] as String,
    side: json['side'] as String,
    severity: json['severity'] as String,
    note: json['note'] as String?,
  );

  Map<String, dynamic> toJson() => {'part': part, 'side': side, 'severity': severity, if (note != null) 'note': note};
}

class NotificationPrefs {
  const NotificationPrefs({
    this.workoutReminders = true,
    this.achievementAlerts = true,
    this.weeklySummary = true,
    this.challengeUpdates = true,
  });

  final bool workoutReminders;
  final bool achievementAlerts;
  final bool weeklySummary;
  final bool challengeUpdates;

  factory NotificationPrefs.fromJson(Map<String, dynamic> json) => NotificationPrefs(
    workoutReminders: json['workout_reminders'] as bool? ?? true,
    achievementAlerts: json['achievement_alerts'] as bool? ?? true,
    weeklySummary: json['weekly_summary'] as bool? ?? true,
    challengeUpdates: json['challenge_updates'] as bool? ?? true,
  );

  Map<String, dynamic> toJson() => {
    'workout_reminders': workoutReminders,
    'achievement_alerts': achievementAlerts,
    'weekly_summary': weeklySummary,
    'challenge_updates': challengeUpdates,
  };

  NotificationPrefs copyWith({
    bool? workoutReminders,
    bool? achievementAlerts,
    bool? weeklySummary,
    bool? challengeUpdates,
  }) => NotificationPrefs(
    workoutReminders: workoutReminders ?? this.workoutReminders,
    achievementAlerts: achievementAlerts ?? this.achievementAlerts,
    weeklySummary: weeklySummary ?? this.weeklySummary,
    challengeUpdates: challengeUpdates ?? this.challengeUpdates,
  );
}

class User {
  const User({
    required this.id,
    required this.email,
    this.fullName,
    this.avatarUrl,
    this.dob,
    this.gender,
    this.heightCm,
    this.weightKg,
    this.goal,
    this.experienceLevel,
    this.daysPerWeek,
    this.sessionMinutes,
    this.splitPreference,
    this.gymLocation,
    this.equipment = const [],
    this.injuries = const [],
    this.units = 'metric',
    this.onboardingCompleted = false,
    this.voiceCoach = const VoiceCoachSettings(),
    this.restTimerDefaultS = 90,
    this.xp = 0,
    this.subscriptionTier = 'free',
    this.notificationPrefs = const NotificationPrefs(),
    this.locale = 'en',
  });

  final String id;
  final String email;
  final String? fullName;
  final String? avatarUrl;
  final DateTime? dob;
  final String? gender;
  final double? heightCm;
  final double? weightKg;
  final String? goal;
  final String? experienceLevel;
  final int? daysPerWeek;
  final int? sessionMinutes;
  final String? splitPreference;
  final String? gymLocation;
  final List<String> equipment;
  final List<Injury> injuries;
  final String units;
  final bool onboardingCompleted;
  final VoiceCoachSettings voiceCoach;
  final int restTimerDefaultS;
  final int xp;
  final String subscriptionTier;
  final NotificationPrefs notificationPrefs;
  final String locale;

  bool get isPro => subscriptionTier == 'pro';

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      email: json['email'] as String,
      fullName: json['full_name'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      dob: json['dob'] != null ? DateTime.tryParse(json['dob'] as String) : null,
      gender: json['gender'] as String?,
      heightCm: (json['height_cm'] as num?)?.toDouble(),
      weightKg: (json['weight_kg'] as num?)?.toDouble(),
      goal: json['goal'] as String?,
      experienceLevel: json['experience_level'] as String?,
      daysPerWeek: json['days_per_week'] as int?,
      sessionMinutes: json['session_minutes'] as int?,
      splitPreference: json['split_preference'] as String?,
      gymLocation: json['gym_location'] as String?,
      equipment: (json['equipment'] as List<dynamic>? ?? []).cast<String>(),
      injuries: (json['injuries'] as List<dynamic>? ?? [])
          .map((e) => Injury.fromJson(e as Map<String, dynamic>))
          .toList(),
      units: json['units'] as String? ?? 'metric',
      onboardingCompleted: json['onboarding_completed'] as bool? ?? false,
      voiceCoach: json['voice_coach'] != null
          ? VoiceCoachSettings.fromJson(json['voice_coach'] as Map<String, dynamic>)
          : const VoiceCoachSettings(),
      restTimerDefaultS: json['rest_timer_default_s'] as int? ?? 90,
      xp: json['xp'] as int? ?? 0,
      subscriptionTier: json['subscription_tier'] as String? ?? 'free',
      notificationPrefs: json['notification_prefs'] != null
          ? NotificationPrefs.fromJson(json['notification_prefs'] as Map<String, dynamic>)
          : const NotificationPrefs(),
      locale: json['locale'] as String? ?? 'en',
    );
  }
}
