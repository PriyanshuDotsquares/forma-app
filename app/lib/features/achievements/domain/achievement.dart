class Achievement {
  const Achievement({
    required this.id,
    required this.key,
    required this.category,
    required this.title,
    required this.description,
    required this.icon,
    required this.isSecret,
  });

  final String id;
  final String key;
  final String category; // consistency | strength | volume | secret
  final String title;
  final String description;
  final String icon;
  final bool isSecret;

  factory Achievement.fromJson(Map<String, dynamic> json) => Achievement(
    id: json['id'] as String,
    key: json['key'] as String,
    category: json['category'] as String,
    title: json['title'] as String,
    description: json['description'] as String,
    icon: json['icon'] as String,
    isSecret: json['is_secret'] as bool,
  );
}

class UserAchievement {
  const UserAchievement({
    required this.id,
    required this.achievement,
    required this.progressValue,
    required this.targetValue,
    this.unlockedAt,
  });

  final String id;
  final Achievement achievement;
  final double progressValue;
  final double targetValue;
  final DateTime? unlockedAt;

  bool get isUnlocked => unlockedAt != null;
  double get progressFraction => targetValue <= 0 ? 0 : (progressValue / targetValue).clamp(0, 1);

  factory UserAchievement.fromJson(Map<String, dynamic> json) => UserAchievement(
    id: json['id'] as String,
    achievement: Achievement.fromJson(json['achievement'] as Map<String, dynamic>),
    progressValue: (json['progress_value'] as num).toDouble(),
    targetValue: (json['target_value'] as num).toDouble(),
    unlockedAt: json['unlocked_at'] != null ? DateTime.parse(json['unlocked_at'] as String) : null,
  );
}

class PersonalRecord {
  const PersonalRecord({
    required this.id,
    required this.exerciseId,
    required this.weightKg,
    required this.reps,
    required this.est1RmKg,
    required this.achievedAt,
  });

  final String id;
  final String exerciseId;
  final double weightKg;
  final int reps;
  final double est1RmKg;
  final DateTime achievedAt;

  factory PersonalRecord.fromJson(Map<String, dynamic> json) => PersonalRecord(
    id: json['id'] as String,
    exerciseId: json['exercise_id'] as String,
    weightKg: (json['weight_kg'] as num).toDouble(),
    reps: json['reps'] as int,
    est1RmKg: (json['est_1rm_kg'] as num).toDouble(),
    achievedAt: DateTime.parse(json['achieved_at'] as String),
  );
}
