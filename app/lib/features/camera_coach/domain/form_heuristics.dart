import 'rep_counter.dart';

/// A broad movement pattern used to pick a generic set of "ideal" joint-
/// angle ranges for form scoring, instead of hand-tuning each of FORMA's
/// ~46 seeded exercises individually. These patterns cover the bulk of the
/// library; anything that doesn't match falls back to [generic].
enum MovementPattern { press, squat, hinge, pull, bentOverRow, generic }

/// Infers a [MovementPattern] from an exercise's name and primary muscles.
/// This is a keyword heuristic, not a classifier — it's meant to be good
/// enough to pick a reasonable ideal-range table, not to be a taxonomically
/// perfect movement classification.
MovementPattern inferMovementPattern({required String exerciseName, required List<String> primaryMuscles}) {
  final name = exerciseName.toLowerCase();
  final muscles = primaryMuscles.map((m) => m.toLowerCase()).toSet();

  bool nameHasAny(List<String> words) => words.any(name.contains);

  if (nameHasAny(['squat', 'lunge', 'leg press', 'leg extension']) || muscles.contains('quads')) {
    return MovementPattern.squat;
  }
  if (nameHasAny(['deadlift', 'hip thrust', 'romanian', 'rdl', 'good morning', 'leg curl']) ||
      muscles.contains('hamstrings') ||
      muscles.contains('glutes')) {
    return MovementPattern.hinge;
  }
  if (nameHasAny(['press', 'push-up', 'pushup', 'dip', 'fly']) ||
      muscles.contains('chest') ||
      muscles.contains('shoulders') ||
      muscles.contains('triceps')) {
    return MovementPattern.press;
  }
  // Checked ahead of the generic pull match below: a bent-over row is
  // deliberately performed with the torso already hinged forward, so
  // `pull`'s "torso not swinging" hip band (tuned for an upright seated
  // row / lat pulldown) would read a textbook bent-over row's resting
  // posture as a fault on every rep. See MovementPattern.bentOverRow's
  // rule comment below.
  if (nameHasAny(['bent-over', 'bent over'])) {
    return MovementPattern.bentOverRow;
  }
  if (nameHasAny(['row', 'pull', 'curl', 'lat pulldown', 'shrug']) ||
      muscles.contains('back') ||
      muscles.contains('lats') ||
      muscles.contains('biceps')) {
    return MovementPattern.pull;
  }
  return MovementPattern.generic;
}

enum _Joint { elbow, hip, knee }

/// One scored cue: a joint, its coach-authored ideal range, how much this
/// rule contributes to the 100-point form-score budget for its pattern, and
/// the spoken-style correction to surface when the joint strays outside
/// that range. Wording deliberately echoes the short, imperative tone of
/// `Exercise.proCues` / `Exercise.mistakes` (e.g. "Tuck elbows to ~60°" in
/// the bench-press seed data) for flavor consistency, without being sourced
/// from them — those are per-exercise, this table is per-pattern.
class _Rule {
  const _Rule({required this.joint, required this.idealLow, required this.idealHigh, required this.weight, required this.cue});

  final _Joint joint;
  final double idealLow;
  final double idealHigh;
  final double weight;
  final String cue;
}

/// Ideal ranges are rough averages for a mid-rep position, sourced from
/// common strength-coaching cues rather than any captured motion-capture
/// ground truth — see the class doc on [FormHeuristics] for why this is a
/// heuristic and not a trained model. Each pattern's rule weights sum to
/// 100, so [FormHeuristics.computeScore] can spend the full 0-100 budget
/// across the pattern's rules.
const Map<MovementPattern, List<_Rule>> _rulesByPattern = {
  MovementPattern.press: [
    // Bench/overhead-press elbow flare: too tucked loses chest drive, too
    // flared (>70°) loads the anterior shoulder. ~45-70° from the torso is
    // the commonly-cited safe/effective band.
    _Rule(joint: _Joint.elbow, idealLow: 45, idealHigh: 70, weight: 60, cue: 'Tuck your elbows in'),
    // Excess lower-back arch (hip opening up) turns a flat/overhead press
    // into an incline press — hips should stay close to extended/neutral.
    _Rule(joint: _Joint.hip, idealLow: 150, idealHigh: 180, weight: 40, cue: 'Keep your ribs down'),
  ],
  MovementPattern.squat: [
    // Depth: hip crease should get at or below the knee, which reads as a
    // knee angle roughly 70-100° at the bottom.
    _Rule(joint: _Joint.knee, idealLow: 70, idealHigh: 100, weight: 55, cue: 'Sit a little deeper'),
    // Torso lean: too much forward lean (small hip angle) shifts load
    // forward; 45-90° covers upright-to-moderate lean depending on stance.
    _Rule(joint: _Joint.hip, idealLow: 45, idealHigh: 90, weight: 45, cue: 'Keep your chest up'),
  ],
  MovementPattern.hinge: [
    // The hip should do most of the work — a hip angle that never closes
    // much below 100° means the lifter is squatting the hinge instead of
    // pushing the hips back.
    _Rule(joint: _Joint.hip, idealLow: 45, idealHigh: 100, weight: 60, cue: 'Push your hips back further'),
    // Knees should stay softly bent, not locked or heavily bent (that
    // turns a hinge into a squat).
    _Rule(joint: _Joint.knee, idealLow: 150, idealHigh: 175, weight: 40, cue: 'Keep a soft bend in your knees'),
  ],
  MovementPattern.pull: [
    // Rows/pulldowns/curls: elbows should drive back/down rather than
    // flaring out to the sides.
    _Rule(joint: _Joint.elbow, idealLow: 30, idealHigh: 80, weight: 60, cue: 'Drive your elbows back'),
    // Torso swinging (hip angle moving well off extended) means momentum
    // is doing the work instead of the target muscle.
    _Rule(joint: _Joint.hip, idealLow: 150, idealHigh: 180, weight: 40, cue: "Keep your torso from swinging"),
  ],
  MovementPattern.bentOverRow: [
    // Same elbow-drive-back mechanics as MovementPattern.pull.
    _Rule(joint: _Joint.elbow, idealLow: 30, idealHigh: 80, weight: 60, cue: 'Drive your elbows back'),
    // A bent-over row's correct starting posture *is* a closed hip angle
    // (that's what "bent-over" means) — pull's 150-180° upright band would
    // flag that as a fault every rep. The actual failure mode here is
    // standing the hips up to heave the weight, so the ideal band mirrors
    // a hinge stance instead.
    _Rule(joint: _Joint.hip, idealLow: 45, idealHigh: 100, weight: 40, cue: 'Keep your hinge — avoid standing up to heave the weight'),
  ],
  MovementPattern.generic: [
    // No pattern-specific cue table — just flag genuinely extreme,
    // unlikely-to-be-controlled elbow positions so the fallback isn't
    // silent.
    _Rule(joint: _Joint.elbow, idealLow: 20, idealHigh: 175, weight: 100, cue: 'Control the movement'),
  ],
};

/// How far outside a rule's ideal range (in the rule's own units — degrees
/// for every current rule) a sample has to be before it eats that rule's
/// entire weight. Deviation between 0 and this ramp is penalized linearly.
const double _fullPenaltyRampDeg = 30;

/// A single frame's evaluation against the current [MovementPattern]: which
/// cues are active right now, and which joints triggered them (for driving
/// the skeleton-overlay coloring in the UI).
class FormSnapshot {
  const FormSnapshot({required this.cues, required this.flaggedElbow, required this.flaggedHip, required this.flaggedKnee});

  final List<String> cues;
  final bool flaggedElbow;
  final bool flaggedHip;
  final bool flaggedKnee;

  bool get hasFlag => flaggedElbow || flaggedHip || flaggedKnee;

  static const empty = FormSnapshot(cues: [], flaggedElbow: false, flaggedHip: false, flaggedKnee: false);
}

/// Public mirror of the private [_Joint] enum, for callers outside this
/// file (e.g. the workout screen matching [FormHeuristics.dominantFlaggedJoint]
/// against an `Exercise.mistakes` entry) that need to know *which* joint
/// was flagged without reaching into this file's internals.
enum FlaggedJoint { elbow, hip, knee }

/// Scores form and surfaces correction cues for one exercise/set, using
/// simple weighted deviation-from-ideal-range rules keyed by
/// [MovementPattern] (see [_rulesByPattern] above for the exact ranges and
/// weights).
///
/// **This is a heuristic, not a trained model.** It has no ground-truth
/// motion-capture data behind it, doesn't account for individual limb
/// proportions or camera angle, and only looks at 2D joint angles derived
/// from a single camera. Treat its score and cues as an approximate,
/// good-faith training aid — not a biomechanical assessment.
class FormHeuristics {
  FormHeuristics({required this.pattern});

  factory FormHeuristics.forExercise({required String exerciseName, required List<String> primaryMuscles}) =>
      FormHeuristics(pattern: inferMovementPattern(exerciseName: exerciseName, primaryMuscles: primaryMuscles));

  final MovementPattern pattern;

  final List<double> _sampleScores = [];
  final Map<_Joint, int> _flagCounts = {};
  final Map<_Joint, bool> _inRangeThisRep = {};

  List<_Rule> get _rules => _rulesByPattern[pattern] ?? _rulesByPattern[MovementPattern.generic]!;

  /// Whichever joint has been flagged (outside its ideal range) most often
  /// across every sample fed via [addSample] so far — the best single
  /// "what mostly went wrong this set" signal, used to pick a relevant
  /// [Exercise.mistakes](../../programs/domain/exercise.dart) entry for the
  /// post-set coaching note. `null` if nothing has been flagged yet.
  FlaggedJoint? get dominantFlaggedJoint {
    if (_flagCounts.isEmpty) return null;
    final sorted = _flagCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return switch (sorted.first.key) {
      _Joint.elbow => FlaggedJoint.elbow,
      _Joint.hip => FlaggedJoint.hip,
      _Joint.knee => FlaggedJoint.knee,
    };
  }

  /// Evaluates a single frame against the ideal ranges for [pattern] —
  /// does not depend on history, safe to call every frame for the live cue
  /// banner / skeleton coloring.
  FormSnapshot evaluateFrame(JointAngles angles) {
    final cues = <String>[];
    var flaggedElbow = false;
    var flaggedHip = false;
    var flaggedKnee = false;

    for (final rule in _rules) {
      final value = _extract(angles, rule.joint);
      if (value == null) continue;
      if (value < rule.idealLow || value > rule.idealHigh) {
        cues.add(rule.cue);
        switch (rule.joint) {
          case _Joint.elbow:
            flaggedElbow = true;
          case _Joint.hip:
            flaggedHip = true;
          case _Joint.knee:
            flaggedKnee = true;
        }
      }
    }

    return FormSnapshot(cues: cues, flaggedElbow: flaggedElbow, flaggedHip: flaggedHip, flaggedKnee: flaggedKnee);
  }

  /// Feeds one frame into the running form score for the set — call this
  /// alongside [evaluateFrame] (or instead of it, if only the eventual
  /// score is needed) once per pose frame.
  void addSample(JointAngles angles) {
    _sampleScores.add(_scoreFrame(angles));
    for (final rule in _rules) {
      final value = _extract(angles, rule.joint);
      if (value != null && value >= rule.idealLow && value <= rule.idealHigh) {
        _inRangeThisRep[rule.joint] = true;
      }
    }
  }

  /// Whether every rule's joint reached its ideal range at least once since
  /// the last [markRepBoundary] — i.e. "did the lifter get into a good
  /// position for every checked joint at some point during this rep".
  ///
  /// This has to look across the whole rep rather than at a single frame:
  /// a rep completes exactly when the driving joint crosses back to its
  /// extended "top" position (see [RepCounter]'s hysteresis), which is
  /// also the one moment a bottom-of-rep rule (e.g. squat depth, press
  /// elbow tuck) is *guaranteed* to read as deviated. Grading off that one
  /// frame would flag nearly every rep of nearly every exercise regardless
  /// of how the rep actually looked.
  bool get repLookedGood => _rules.every((rule) => _inRangeThisRep[rule.joint] == true);

  /// Resets per-rep in-range tracking — call right after grading a
  /// completed rep via [repLookedGood], so the next rep starts fresh.
  void markRepBoundary() => _inRangeThisRep.clear();

  double _scoreFrame(JointAngles angles) {
    var score = 100.0;
    for (final rule in _rules) {
      final value = _extract(angles, rule.joint);
      if (value == null) continue;
      final deviation = value < rule.idealLow
          ? rule.idealLow - value
          : value > rule.idealHigh
          ? value - rule.idealHigh
          : 0.0;
      if (deviation <= 0) continue;
      _flagCounts[rule.joint] = (_flagCounts[rule.joint] ?? 0) + 1;
      final penaltyFraction = (deviation / _fullPenaltyRampDeg).clamp(0.0, 1.0);
      score -= rule.weight * penaltyFraction;
    }
    return score.clamp(0, 100);
  }

  /// The 0-100 form score across every sample fed via [addSample] so far —
  /// a plain average of per-frame scores. Returns 100 (benefit of the
  /// doubt) if no samples have been recorded yet.
  int computeScore() {
    if (_sampleScores.isEmpty) return 100;
    final avg = _sampleScores.reduce((a, b) => a + b) / _sampleScores.length;
    return avg.round().clamp(0, 100);
  }

  void reset() {
    _sampleScores.clear();
    _flagCounts.clear();
    _inRangeThisRep.clear();
  }

  double? _extract(JointAngles angles, _Joint joint) {
    switch (joint) {
      case _Joint.elbow:
        return angles.elbowAngleDeg;
      case _Joint.hip:
        return angles.hipAngleDeg;
      case _Joint.knee:
        return angles.kneeAngleDeg;
    }
  }
}
