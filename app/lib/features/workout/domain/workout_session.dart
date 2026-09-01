import '../../programs/domain/exercise.dart';

class WorkoutSet {
  const WorkoutSet({
    required this.id,
    required this.exerciseId,
    required this.exercise,
    required this.setIndex,
    required this.setType,
    this.targetWeightKg,
    this.targetReps,
    this.actualWeightKg,
    this.actualReps,
    this.rpe,
    this.formScore,
    this.depthPct,
    this.isPr = false,
    required this.completedAt,
  });

  final String id;
  final String exerciseId;
  final Exercise exercise;
  final int setIndex;
  final String setType; // normal | warmup | drop
  final double? targetWeightKg;
  final int? targetReps;
  final double? actualWeightKg;
  final int? actualReps;
  final double? rpe;
  final int? formScore;
  final double? depthPct;
  final bool isPr;
  final DateTime completedAt;

  factory WorkoutSet.fromJson(Map<String, dynamic> json) => WorkoutSet(
    id: json['id'] as String,
    exerciseId: json['exercise_id'] as String,
    exercise: Exercise.fromJson(json['exercise'] as Map<String, dynamic>),
    setIndex: json['set_index'] as int,
    setType: json['set_type'] as String,
    targetWeightKg: (json['target_weight_kg'] as num?)?.toDouble(),
    targetReps: json['target_reps'] as int?,
    actualWeightKg: (json['actual_weight_kg'] as num?)?.toDouble(),
    actualReps: json['actual_reps'] as int?,
    rpe: (json['rpe'] as num?)?.toDouble(),
    formScore: json['form_score'] as int?,
    depthPct: (json['depth_pct'] as num?)?.toDouble(),
    isPr: json['is_pr'] as bool? ?? false,
    completedAt: DateTime.parse(json['completed_at'] as String),
  );
}

class WorkoutSession {
  const WorkoutSession({
    required this.id,
    this.programDayId,
    required this.label,
    required this.startedAt,
    this.endedAt,
    this.durationS,
    this.calories,
    this.avgFormScore,
    this.rpe,
    this.mood,
    this.notes,
    this.sets = const [],
  });

  final String id;
  final String? programDayId;
  final String label;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int? durationS;
  final int? calories;
  final double? avgFormScore;
  final double? rpe;
  final int? mood;
  final String? notes;
  final List<WorkoutSet> sets;

  bool get isFinished => endedAt != null;

  factory WorkoutSession.fromJson(Map<String, dynamic> json) => WorkoutSession(
    id: json['id'] as String,
    programDayId: json['program_day_id'] as String?,
    label: json['label'] as String,
    startedAt: DateTime.parse(json['started_at'] as String),
    endedAt: json['ended_at'] != null ? DateTime.parse(json['ended_at'] as String) : null,
    durationS: json['duration_s'] as int?,
    calories: json['calories'] as int?,
    avgFormScore: (json['avg_form_score'] as num?)?.toDouble(),
    rpe: (json['rpe'] as num?)?.toDouble(),
    mood: json['mood'] as int?,
    notes: json['notes'] as String?,
    sets: (json['sets'] as List<dynamic>? ?? []).map((e) => WorkoutSet.fromJson(e as Map<String, dynamic>)).toList(),
  );
}
