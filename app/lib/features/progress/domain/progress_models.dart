class ProgressSummary {
  const ProgressSummary({
    required this.period,
    required this.workouts,
    required this.volumeKg,
    required this.timeS,
    this.avgFormScore,
    required this.streakDays,
  });

  final String period;
  final int workouts;
  final double volumeKg;
  final int timeS;
  final double? avgFormScore;
  final int streakDays;

  factory ProgressSummary.fromJson(Map<String, dynamic> json) => ProgressSummary(
    period: json['period'] as String,
    workouts: json['workouts'] as int,
    volumeKg: (json['volume_kg'] as num).toDouble(),
    timeS: json['time_s'] as int,
    avgFormScore: (json['avg_form_score'] as num?)?.toDouble(),
    streakDays: json['streak_days'] as int,
  );
}

class VolumeByMuscle {
  const VolumeByMuscle({required this.muscle, required this.sets, required this.volumeKg});

  final String muscle;
  final int sets;
  final double volumeKg;

  factory VolumeByMuscle.fromJson(Map<String, dynamic> json) => VolumeByMuscle(
    muscle: json['muscle'] as String,
    sets: json['sets'] as int,
    volumeKg: (json['volume_kg'] as num).toDouble(),
  );
}

class VolumeTrendPoint {
  const VolumeTrendPoint({required this.periodLabel, required this.volumeKg, this.isDeload = false});

  final String periodLabel;
  final double volumeKg;
  final bool isDeload;

  factory VolumeTrendPoint.fromJson(Map<String, dynamic> json) => VolumeTrendPoint(
    periodLabel: json['period_label'] as String,
    volumeKg: (json['volume_kg'] as num).toDouble(),
    isDeload: json['is_deload'] as bool? ?? false,
  );
}

class RecoveryItem {
  const RecoveryItem({
    required this.muscleGroup,
    this.lastTrained,
    required this.setsLastSession,
    required this.recoveredPct,
    this.freshInHours,
  });

  final String muscleGroup;
  final DateTime? lastTrained;
  final int setsLastSession;
  final double recoveredPct;
  final double? freshInHours;

  factory RecoveryItem.fromJson(Map<String, dynamic> json) => RecoveryItem(
    muscleGroup: json['muscle_group'] as String,
    lastTrained: json['last_trained'] != null ? DateTime.tryParse(json['last_trained'] as String) : null,
    setsLastSession: json['sets_last_session'] as int,
    recoveredPct: (json['recovered_pct'] as num).toDouble(),
    freshInHours: (json['fresh_in_hours'] as num?)?.toDouble(),
  );
}

class StrengthPoint {
  const StrengthPoint({required this.date, required this.est1RmKg});

  final DateTime date;
  final double est1RmKg;

  factory StrengthPoint.fromJson(Map<String, dynamic> json) =>
      StrengthPoint(date: DateTime.parse(json['date'] as String), est1RmKg: (json['est_1rm_kg'] as num).toDouble());
}

class FormQualityPoint {
  const FormQualityPoint({required this.weekLabel, required this.formScore});

  final String weekLabel;
  final double formScore;

  factory FormQualityPoint.fromJson(Map<String, dynamic> json) =>
      FormQualityPoint(weekLabel: json['week_label'] as String, formScore: (json['form_score'] as num).toDouble());
}

class ConsistencyDay {
  const ConsistencyDay({required this.date, required this.sessions, required this.volumeKg, required this.hasPr});

  final DateTime date;
  final int sessions;
  final double volumeKg;
  final bool hasPr;

  factory ConsistencyDay.fromJson(Map<String, dynamic> json) => ConsistencyDay(
    date: DateTime.parse(json['date'] as String),
    sessions: json['sessions'] as int,
    volumeKg: (json['volume_kg'] as num).toDouble(),
    hasPr: json['has_pr'] as bool,
  );
}
