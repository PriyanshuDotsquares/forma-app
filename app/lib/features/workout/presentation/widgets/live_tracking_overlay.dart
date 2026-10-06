import 'dart:async';

import 'package:flutter/material.dart';
import '../../../../core/design_system/design_system.dart';
import '../../../camera_coach/data/mediapipe/pose_types.dart';
import '../../../auth/domain/user.dart';
import '../../../camera_coach/data/pose_service.dart';
import '../../../camera_coach/data/voice_coach.dart';
import '../../../camera_coach/domain/form_heuristics.dart';
import '../../../camera_coach/domain/rep_counter.dart';
import '../../../camera_coach/domain/tempo_summary.dart';
import '../../../programs/domain/exercise.dart';
import 'pose_angle_mapper.dart';
import 'camera_cover_preview.dart';

/// What a live-coached set produced, handed back to the active-workout
/// screen so it can prefill the normal (still-editable) reps/weight entry
/// for that set — this widget never calls the workout API itself, logging
/// stays the single responsibility of the LOG SET button.
class LiveSetResult {
  const LiveSetResult({
    required this.reps,
    required this.formScore,
    this.romPct,
    required this.goodReps,
    required this.badReps,
    this.dominantFlaggedJoint,
    this.tempo,
  });

  final int reps;
  final int formScore;
  final double? romPct;

  /// Reps where form stayed within the ideal range the whole time
  /// (`reps - badReps`); `badReps` is how many were flagged at the moment
  /// they completed. Together these answer "how many good vs. bad reps",
  /// distinct from [formScore] which is a single 0-100 average for the
  /// whole set.
  final int goodReps;
  final int badReps;

  /// Whichever joint was flagged most across the set, if any — lets the
  /// caller surface an exercise-specific [Exercise.mistakes] entry instead
  /// of a generic note.
  final FlaggedJoint? dominantFlaggedJoint;

  /// Overall lowering/lifting tempo for the set, or null when no rep could be
  /// timed. Reported only — never part of [formScore].
  final TempoSummary? tempo;
}

/// Full-screen live camera coaching for one set: camera preview, a pose
/// skeleton overlay, a rep counter, a rolling form score, and spoken cues —
/// wiring together every piece of the `camera_coach` engine
/// (PoseCoachService + RepCounter + FormHeuristics + VoiceCoach).
class LiveTrackingOverlay extends StatefulWidget {
  const LiveTrackingOverlay({
    super.key,
    required this.exercise,
    required this.voiceCoachSettings,
    required this.onFinish,
    required this.onCancel,
    this.targetReps,
  });

  final Exercise exercise;
  final VoiceCoachSettings voiceCoachSettings;
  final ValueChanged<LiveSetResult> onFinish;
  final VoidCallback onCancel;

  /// The planned rep count for this set, if known. Once the live counter
  /// reaches it, the set auto-finishes (same as tapping "Finish set")
  /// instead of waiting for the lifter to stop and tap manually.
  final int? targetReps;

  @override
  State<LiveTrackingOverlay> createState() => _LiveTrackingOverlayState();
}

class _LiveTrackingOverlayState extends State<LiveTrackingOverlay> {
  final PoseCoachService _poseService = PoseCoachService();
  final VoiceCoach _voiceCoach = VoiceCoach();
  late final RepCounter _repCounter;
  late final FormHeuristics _formHeuristics;

  bool _initializing = true;
  PoseServiceInitResult? _initResult;
  bool _paused = false;

  FormSnapshot _snapshot = FormSnapshot.empty;
  RepResult? _lastRep;
  final List<bool> _repFlags = []; // one per completed rep; true = flagged/red

  /// One entry per completed rep, in lowering/lifting terms. Feeds the live
  /// per-rep readout and, at the end of the set, the overall tempo summary.
  final List<RepTempo> _repTempos = [];
  late final bool _fallingIsLowering;

  /// True while a tracked landmark sits at the edge of the frame this
  /// frame — takes priority over ordinary form cues (see
  /// `pose_angle_mapper.dart`'s `JointAngles.outOfFrame` doc comment for
  /// why a confidence check alone doesn't catch this).
  bool _outOfFrame = false;

  @override
  void initState() {
    super.initState();
    final pattern = inferMovementPattern(exerciseName: widget.exercise.name, primaryMuscles: widget.exercise.primaryMuscles);
    _formHeuristics = FormHeuristics(pattern: pattern);
    _fallingIsLowering = fallingPhaseIsLowering(pattern);
    final config = repCounterConfigFor(pattern);
    _repCounter = RepCounter(
      drivingJoint: config.drivingJoint,
      bottomThreshold: config.bottomThreshold,
      topThreshold: config.topThreshold,
      onRepCompleted: _handleRepCompleted,
    );
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _voiceCoach.configure(settings: widget.voiceCoachSettings);
    final result = await _poseService.initialize();
    if (!mounted) return;

    if (result == PoseServiceInitResult.ready) {
      setState(() {
        _initResult = result;
        _initializing = false;
      });
      _poseService.startStream(_handlePose);
    } else {
      setState(() {
        _initResult = result;
        _initializing = false;
      });
    }
  }

  void _handlePose(Pose? pose) {
    if (!mounted || _paused) return;
    // Not `controller.value.previewSize` — see `PoseCoachService.
    // lastFrameSize`'s doc comment for why that's unreliable on Android.
    // Already reflects *this* frame's size: `_frameFor` records it before
    // the detector ever runs, so it's current by the time this callback
    // fires with a result.
    final frameSize = _poseService.lastFrameSize;
    final angles = pose == null ? const JointAngles() : jointAnglesFromPose(pose, imageSize: frameSize);
    final snapshot = _formHeuristics.evaluateFrame(angles);
    _formHeuristics.addSample(angles);
    // Skip extrapolated landmarks feeding the *driving* joint specifically
    // (not JointAngles.outOfFrame's blanket every-landmark flag — a bench
    // press's legs are routinely cropped out of shot and are irrelevant to
    // whether the elbow angle driving its counter is trustworthy).
    final drivingJointOutOfFrame = pose != null && isDrivingJointOutOfFrame(pose, frameSize, _repCounter.drivingJoint);
    if (!drivingJointOutOfFrame) {
      _repCounter.addSample(angles);
    }

    if (!mounted) return;
    setState(() {
      _snapshot = snapshot;
      _outOfFrame = angles.outOfFrame;
    });
    // Out-of-frame takes priority over every other cue — a form rule
    // evaluated on an extrapolated landmark isn't meaningful, so it's
    // pointless (and confusing) to speak one instead.
    if (_outOfFrame) {
      unawaited(_voiceCoach.speak('Step back — you’re at the edge of the frame'));
    } else if (snapshot.cues.isNotEmpty) {
      unawaited(_voiceCoach.speak(snapshot.cues.first));
    }
  }

  bool _finishing = false;

  void _handleRepCompleted(RepResult result) {
    final flagged = !_formHeuristics.repLookedGood;
    _formHeuristics.markRepBoundary();
    if (!mounted) return;
    setState(() {
      _lastRep = result;
      _repFlags.add(flagged);
      _repTempos.add(RepTempo.fromRep(result, fallingIsLowering: _fallingIsLowering));
    });
    unawaited(_voiceCoach.announceRep(result.index));
    if (!flagged) {
      unawaited(_voiceCoach.speakEncouragement('Nice rep'));
    }
    final target = widget.targetReps;
    if (target != null && _repCounter.repCount >= target) {
      unawaited(_finish());
    }
  }

  Future<void> _togglePause() async {
    setState(() => _paused = !_paused);
    if (_paused) {
      await _poseService.stopStream();
    } else {
      _poseService.startStream(_handlePose);
    }
  }

  Future<void> _finish() async {
    if (_finishing) return;
    _finishing = true;
    await _poseService.stopStream();
    final badReps = _repFlags.where((flagged) => flagged).length;
    widget.onFinish(
      LiveSetResult(
        reps: _repCounter.repCount,
        formScore: _formHeuristics.computeScore(),
        romPct: _lastRep?.romPct,
        goodReps: _repFlags.length - badReps,
        badReps: badReps,
        dominantFlaggedJoint: _formHeuristics.dominantFlaggedJoint,
        tempo: TempoSummary.fromReps(_repTempos),
      ),
    );
  }

  Future<void> _switchCamera() async {
    final wasPaused = _paused;
    final result = await _poseService.switchCamera();
    if (!mounted) return;
    setState(() => _paused = wasPaused);
    if (result != PoseServiceInitResult.ready) return;
  }

  @override
  void dispose() {
    unawaited(_poseService.dispose());
    unawaited(_voiceCoach.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_initializing) {
      return const ColoredBox(color: AppColors.surfaceLowest, child: Center(child: CircularProgressIndicator()));
    }
    if (_initResult != PoseServiceInitResult.ready) {
      return _NoCameraState(onCancel: widget.onCancel);
    }

    return ColoredBox(
      color: AppColors.surfaceLowest,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CameraCoverPreview(_poseService.controller),
          SafeArea(
            child: Column(
              children: [
                _TopBar(exerciseName: widget.exercise.name, onSwitchCamera: _switchCamera, onClose: widget.onCancel),
                if (_outOfFrame)
                  const _CueBanner(cue: 'STEP BACK — you’re at the edge of the frame')
                else if (_snapshot.cues.isNotEmpty)
                  _CueBanner(cue: _snapshot.cues.first),
                const Spacer(),
                _BottomPanel(
                  repCount: _repCounter.repCount,
                  romPct: _lastRep?.romPct,
                  repFlags: _repFlags,
                  repTempos: _repTempos,
                  paused: _paused,
                  onTogglePause: _togglePause,
                  onFinishSet: _finish,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.exerciseName, required this.onSwitchCamera, required this.onClose});

  final String exerciseName;
  final VoidCallback onSwitchCamera;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surfaceLowest.withValues(alpha: 0.72),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      child: Row(
        children: [
          IconButton(icon: const Icon(Icons.close, color: AppColors.textPrimary), onPressed: onClose),
          Expanded(
            child: Text(
              exerciseName.toUpperCase(),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.body(size: 12, weight: FontWeight.w700, color: AppColors.textSecondary).copyWith(letterSpacing: 1.0),
            ),
          ),
          IconButton(icon: const Icon(Icons.cameraswitch_outlined, color: AppColors.textPrimary), onPressed: onSwitchCamera),
        ],
      ),
    );
  }
}

class _CueBanner extends StatelessWidget {
  const _CueBanner({required this.cue});
  final String cue;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.accentRed.withValues(alpha: 0.16),
        border: Border.all(color: AppColors.accentRed),
        borderRadius: BorderRadius.circular(AppRadius.field),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.accentRed, size: 18),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(cue, style: AppTypography.body(size: 14, weight: FontWeight.w700, color: AppColors.accentRed))),
        ],
      ),
    );
  }
}

class _BottomPanel extends StatelessWidget {
  const _BottomPanel({
    required this.repCount,
    required this.romPct,
    required this.repFlags,
    required this.repTempos,
    required this.paused,
    required this.onTogglePause,
    required this.onFinishSet,
  });

  final int repCount;
  final double? romPct;
  final List<bool> repFlags;
  final List<RepTempo> repTempos;
  final bool paused;
  final VoidCallback onTogglePause;
  final VoidCallback onFinishSet;

  @override
  Widget build(BuildContext context) {
    final romValue = ((romPct ?? 0) / 100).clamp(0.0, 1.0);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.lg),
      color: AppColors.surfaceLowest.withValues(alpha: 0.85),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (repFlags.isNotEmpty) ...[
            Wrap(
              spacing: 4,
              children: repFlags
                  .map(
                    (flagged) => Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: flagged ? AppColors.accentRed : AppColors.accentGreen,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          if (repTempos.isNotEmpty) ...[
            _LiveTempoStrip(repTempos: repTempos),
            const SizedBox(height: AppSpacing.md),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Column(
                children: [
                  Text('$repCount', style: AppTypography.mono(size: 64, weight: FontWeight.w700)),
                  Text('REPS', style: AppTypography.body(size: 11, weight: FontWeight.w700, color: AppColors.textMuted).copyWith(letterSpacing: 1.2)),
                ],
              ),
              const SizedBox(width: AppSpacing.xl),
              SizedBox(
                width: 64,
                height: 64,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: romValue,
                      strokeWidth: 5,
                      backgroundColor: AppColors.surfaceHighest,
                      color: AppColors.accentBlue,
                    ),
                    Text('${(romValue * 100).round()}%', style: AppTypography.mono(size: 13, weight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onTogglePause,
                  icon: Icon(paused ? Icons.play_arrow : Icons.pause),
                  label: Text(paused ? 'RESUME' : 'PAUSE'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                flex: 2,
                child: FilledButton(onPressed: onFinishSet, child: const Text('FINISH SET')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The last rep's tempo, plus the running average once there are two timed reps.
///
/// Arrow down = lowering phase, arrow up = lifting phase, pause icon = time held
/// at the bottom (shown for every rep, however short). A phase that could not
/// be timed shows "—" rather than a made-up number. Purely informational: no
/// colour judgement, because tempo is reported and never graded.
class _LiveTempoStrip extends StatelessWidget {
  const _LiveTempoStrip({required this.repTempos});

  final List<RepTempo> repTempos;

  @override
  Widget build(BuildContext context) {
    final last = repTempos.last;
    final summary = TempoSummary.fromReps(repTempos);
    final showAverage = summary != null && summary.timedReps >= 2;

    Widget phase(IconData icon, double? seconds) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.accentBlue),
        const SizedBox(width: 2),
        Text(TempoSummary.fmt(seconds), style: AppTypography.mono(size: 14, weight: FontWeight.w600)),
      ],
    );

    Widget label(String text) =>
        Text(text, style: AppTypography.body(size: 10, weight: FontWeight.w700, color: AppColors.textMuted).copyWith(letterSpacing: 1.0));

    Widget line(String name, double? lowering, double? lifting, double? pause) => Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(width: 52, child: label(name)),
        phase(Icons.arrow_downward, lowering),
        const SizedBox(width: AppSpacing.md),
        phase(Icons.arrow_upward, lifting),
        const SizedBox(width: AppSpacing.md),
        phase(Icons.pause, pause),
      ],
    );

    // Two short lines rather than one long one: with a pause on each, a single
    // row for "this rep" plus "average" would not fit a phone's width.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        line('REP ${last.index}', last.loweringSeconds, last.liftingSeconds, last.pauseSeconds),
        if (showAverage) ...[
          const SizedBox(height: 2),
          line('AVG', summary.avgLoweringSeconds, summary.avgLiftingSeconds, summary.avgPauseSeconds),
        ],
      ],
    );
  }
}

class _NoCameraState extends StatelessWidget {
  const _NoCameraState({required this.onCancel});
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.surfaceLowest,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: FormaEmptyState(
              icon: Icons.videocam_off_outlined,
              title: 'Camera unavailable.',
              message: "We couldn't start the camera for live tracking. You can still log this set manually.",
              primaryLabel: 'BACK TO SET',
              onPrimary: onCancel,
            ),
          ),
        ),
      ),
    );
  }
}
