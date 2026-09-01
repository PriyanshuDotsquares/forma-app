class Challenge {
  const Challenge({
    required this.id,
    required this.key,
    required this.title,
    required this.description,
    required this.metric,
    required this.period,
    required this.targetValue,
    required this.icon,
    required this.isGroup,
  });

  final String id;
  final String key;
  final String title;
  final String description;
  final String metric; // volume_kg | session_count | streak_days
  final String period; // weekly | monthly | ongoing
  final double targetValue;
  final String icon;
  final bool isGroup;

  factory Challenge.fromJson(Map<String, dynamic> json) => Challenge(
    id: json['id'] as String,
    key: json['key'] as String,
    title: json['title'] as String,
    description: json['description'] as String,
    metric: json['metric'] as String,
    period: json['period'] as String,
    targetValue: (json['target_value'] as num).toDouble(),
    icon: json['icon'] as String,
    isGroup: json['is_group'] as bool,
  );
}

class UserChallenge {
  const UserChallenge({
    required this.challenge,
    required this.joined,
    required this.progressValue,
    this.periodStart,
    this.completedAt,
  });

  final Challenge challenge;
  final bool joined;
  final double progressValue;
  final DateTime? periodStart;
  final DateTime? completedAt;

  bool get isCompleted => completedAt != null;
  double get progressFraction => challenge.targetValue <= 0 ? 0 : (progressValue / challenge.targetValue).clamp(0, 1);

  factory UserChallenge.fromJson(Map<String, dynamic> json) => UserChallenge(
    challenge: Challenge.fromJson(json['challenge'] as Map<String, dynamic>),
    joined: json['joined'] as bool,
    progressValue: (json['progress_value'] as num).toDouble(),
    periodStart: json['period_start'] != null ? DateTime.parse(json['period_start'] as String) : null,
    completedAt: json['completed_at'] != null ? DateTime.parse(json['completed_at'] as String) : null,
  );
}

class LeaderboardEntry {
  const LeaderboardEntry({required this.rank, required this.displayName, required this.progressValue, required this.isMe});

  final int rank;
  final String displayName;
  final double progressValue;
  final bool isMe;

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) => LeaderboardEntry(
    rank: json['rank'] as int,
    displayName: json['display_name'] as String,
    progressValue: (json['progress_value'] as num).toDouble(),
    isMe: json['is_me'] as bool,
  );
}
