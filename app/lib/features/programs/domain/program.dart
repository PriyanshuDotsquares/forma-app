import 'exercise.dart';

class ProgramExercise {
  const ProgramExercise({
    required this.id,
    required this.exerciseId,
    required this.exercise,
    required this.orderIndex,
    required this.sets,
    required this.repRangeLow,
    required this.repRangeHigh,
    required this.loadType,
    this.targetValue,
    this.tempo,
    this.supersetGroup,
    this.notes,
    this.coachWithCamera = false,
  });

  final String id;
  final String exerciseId;
  final Exercise exercise;
  final int orderIndex;
  final int sets;
  final int repRangeLow;
  final int repRangeHigh;
  final String loadType; // weight | percent_1rm | rpe
  final double? targetValue;
  final String? tempo;
  final String? supersetGroup;
  final String? notes;
  final bool coachWithCamera;

  String get repRangeLabel => '$repRangeLow-$repRangeHigh';

  factory ProgramExercise.fromJson(Map<String, dynamic> json) => ProgramExercise(
    id: json['id'] as String,
    exerciseId: json['exercise_id'] as String,
    exercise: Exercise.fromJson(json['exercise'] as Map<String, dynamic>),
    orderIndex: json['order_index'] as int,
    sets: json['sets'] as int,
    repRangeLow: json['rep_range_low'] as int,
    repRangeHigh: json['rep_range_high'] as int,
    loadType: json['load_type'] as String,
    targetValue: (json['target_value'] as num?)?.toDouble(),
    tempo: json['tempo'] as String?,
    supersetGroup: json['superset_group'] as String?,
    notes: json['notes'] as String?,
    coachWithCamera: json['coach_with_camera'] as bool? ?? false,
  );
}

class ProgramDay {
  const ProgramDay({
    required this.id,
    required this.orderIndex,
    this.weekday,
    required this.label,
    required this.muscleTags,
    required this.isRest,
    this.estimatedMinutes,
    this.exercises = const [],
  });

  final String id;
  final int orderIndex;
  final int? weekday; // 0=Mon .. 6=Sun
  final String label;
  final List<String> muscleTags;
  final bool isRest;
  final int? estimatedMinutes;
  final List<ProgramExercise> exercises;

  factory ProgramDay.fromJson(Map<String, dynamic> json) => ProgramDay(
    id: json['id'] as String,
    orderIndex: json['order_index'] as int,
    weekday: json['weekday'] as int?,
    label: json['label'] as String,
    muscleTags: (json['muscle_tags'] as List<dynamic>).cast<String>(),
    isRest: json['is_rest'] as bool,
    estimatedMinutes: json['estimated_minutes'] as int?,
    exercises: (json['exercises'] as List<dynamic>? ?? [])
        .map((e) => ProgramExercise.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

class Program {
  const Program({
    required this.id,
    required this.name,
    required this.splitType,
    required this.daysPerWeek,
    required this.durationWeeks,
    required this.source,
    required this.isActive,
    this.days = const [],
  });

  final String id;
  final String name;
  final String splitType;
  final int daysPerWeek;
  final int durationWeeks;
  final String source; // generated | manual
  final bool isActive;
  final List<ProgramDay> days;

  factory Program.fromJson(Map<String, dynamic> json) => Program(
    id: json['id'] as String,
    name: json['name'] as String,
    splitType: json['split_type'] as String,
    daysPerWeek: json['days_per_week'] as int,
    durationWeeks: json['duration_weeks'] as int,
    source: json['source'] as String,
    isActive: json['is_active'] as bool,
    days: (json['days'] as List<dynamic>? ?? []).map((e) => ProgramDay.fromJson(e as Map<String, dynamic>)).toList(),
  );
}
