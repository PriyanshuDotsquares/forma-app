class ExerciseMistake {
  const ExerciseMistake({required this.title, required this.why, required this.fix});

  final String title;
  final String why;
  final String fix;

  factory ExerciseMistake.fromJson(Map<String, dynamic> json) =>
      ExerciseMistake(title: json['title'] as String, why: json['why'] as String, fix: json['fix'] as String);
}

class Exercise {
  const Exercise({
    required this.id,
    required this.slug,
    required this.name,
    required this.primaryMuscles,
    required this.secondaryMuscles,
    required this.equipment,
    required this.difficulty,
    required this.executionSteps,
    required this.proCues,
    required this.mistakes,
    required this.supportsCamera,
    this.cameraView,
  });

  final String id;
  final String slug;
  final String name;
  final List<String> primaryMuscles;
  final List<String> secondaryMuscles;
  final List<String> equipment;
  final String difficulty;
  final List<String> executionSteps;
  final List<String> proCues;
  final List<ExerciseMistake> mistakes;
  final bool supportsCamera;
  final String? cameraView; // "front" | "side"

  String get muscleSummary => [...primaryMuscles, ...secondaryMuscles].take(3).map(_titleCase).join(' · ');

  factory Exercise.fromJson(Map<String, dynamic> json) => Exercise(
    id: json['id'] as String,
    slug: json['slug'] as String,
    name: json['name'] as String,
    primaryMuscles: (json['primary_muscles'] as List<dynamic>).cast<String>(),
    secondaryMuscles: (json['secondary_muscles'] as List<dynamic>).cast<String>(),
    equipment: (json['equipment'] as List<dynamic>).cast<String>(),
    difficulty: json['difficulty'] as String,
    executionSteps: (json['execution_steps'] as List<dynamic>).cast<String>(),
    proCues: (json['pro_cues'] as List<dynamic>).cast<String>(),
    mistakes: (json['mistakes'] as List<dynamic>)
        .map((e) => ExerciseMistake.fromJson(e as Map<String, dynamic>))
        .toList(),
    supportsCamera: json['supports_camera'] as bool,
    cameraView: json['camera_view'] as String?,
  );
}

String _titleCase(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1).replaceAll('_', ' ')}';
