import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/app_router.dart';
import '../../auth/domain/user.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../camera_coach/domain/form_heuristics.dart';
import '../../programs/domain/exercise.dart';
import '../../programs/domain/program.dart';
import '../../programs/presentation/programs_providers.dart';
import '../domain/workout_session.dart';
import 'widgets/exercise_picker_sheet.dart';
import 'widgets/live_tracking_overlay.dart';
import 'widgets/post_set_summary_sheet.dart';
import 'widgets/pr_celebration_overlay.dart';
import 'widgets/rest_timer_sheet.dart';
import 'widgets/set_entry_sheet.dart';
import 'workout_providers.dart';

final _activeProgramProvider = FutureProvider.autoDispose<Program?>(
  (ref) => ref.watch(programsRepositoryProvider).getActiveProgram(),
);

/// One exercise slot in the on-screen plan — either a prescribed
/// `ProgramExercise` from the day the session was started against, or (in
/// freestyle mode, or if the program couldn't be loaded) a slot synthesized
/// from whatever's already been logged / picked ad hoc.
class _PlanExercise {
  _PlanExercise({
    required this.exercise,
    required this.programExerciseId,
    required this.repRangeLow,
    required this.repRangeHigh,
    required this.loadType,
    required this.targetValue,
    required this.notes,
    required this.coachWithCamera,
    required int plannedSets,
  }) : setCount = plannedSets;

  final Exercise exercise;
  final String? programExerciseId;
  final int repRangeLow;
  final int repRangeHigh;
  final String loadType; // weight | percent_1rm | rpe
  final double? targetValue;
  final String? notes;
  final bool coachWithCamera;
  int setCount;

  bool get supportsCoaching => coachWithCamera || exercise.supportsCamera;
  String get repRangeLabel => repRangeLow == repRangeHigh ? '$repRangeLow' : '$repRangeLow-$repRangeHigh';
}

/// One row's worth of locally-editable entry state, merged with the
/// backend `WorkoutSet` once it's been logged.
class _SetEntry {
  _SetEntry({this.weightKg, this.reps});

  double? weightKg;
  int? reps;
  String setType = 'normal';
  WorkoutSet? logged;
  int? formScoreHint;
  double? romHint;
  int? goodRepsHint;
  int? badRepsHint;
  FlaggedJoint? flaggedJointHint;

  bool get isDone => logged != null;
}

String _fmtWeight(double v) => v == v.truncateToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

String _fmtElapsed(int totalSeconds) {
  final h = totalSeconds ~/ 3600;
  final m = (totalSeconds % 3600) ~/ 60;
  final s = totalSeconds % 60;
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

class ActiveWorkoutScreen extends ConsumerStatefulWidget {
  const ActiveWorkoutScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<ActiveWorkoutScreen> createState() => _ActiveWorkoutScreenState();
}

class _ActiveWorkoutScreenState extends ConsumerState<ActiveWorkoutScreen> {
  Timer? _ticker;
  int _elapsedSeconds = 0;
  bool _paused = false;
  bool _finishing = false;

  bool _planBuilt = false;
  bool _isFreestyle = false;
  final List<_PlanExercise> _plan = [];
  final Map<int, List<_SetEntry>> _sets = {};
  int _currentExerciseIndex = 0;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_paused || _finishing || !mounted) return;
      setState(() => _elapsedSeconds += 1);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _initializePlan(WorkoutSession session, ProgramDay? day) {
    _planBuilt = true;
    _elapsedSeconds = DateTime.now().difference(session.startedAt).inSeconds.clamp(0, 24 * 3600);
    _isFreestyle = day == null;

    _plan.clear();
    _sets.clear();

    if (day != null) {
      final exercises = [...day.exercises]..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
      for (final pe in exercises) {
        final index = _plan.length;
        _plan.add(
          _PlanExercise(
            exercise: pe.exercise,
            programExerciseId: pe.id,
            repRangeLow: pe.repRangeLow,
            repRangeHigh: pe.repRangeHigh,
            loadType: pe.loadType,
            targetValue: pe.targetValue,
            notes: pe.notes,
            coachWithCamera: pe.coachWithCamera,
            plannedSets: pe.sets,
          ),
        );
        _sets[index] = List.generate(
          pe.sets,
          (_) => _SetEntry(weightKg: pe.loadType == 'weight' ? pe.targetValue : null, reps: pe.repRangeHigh),
        );
      }
    } else {
      // Freestyle (or the program couldn't be loaded): seed exercise slots
      // from whatever's already been logged, in first-appearance order.
      final orderedIds = <String>[];
      final byId = <String, Exercise>{};
      for (final set in session.sets) {
        if (!byId.containsKey(set.exerciseId)) {
          byId[set.exerciseId] = set.exercise;
          orderedIds.add(set.exerciseId);
        }
      }
      for (final exerciseId in orderedIds) {
        final logged = session.sets.where((s) => s.exerciseId == exerciseId).toList()
          ..sort((a, b) => a.setIndex.compareTo(b.setIndex));
        final setCount = logged.isEmpty ? 3 : logged.map((s) => s.setIndex).reduce(math.max) + 1;
        final index = _plan.length;
        final exercise = byId[exerciseId]!;
        _plan.add(
          _PlanExercise(
            exercise: exercise,
            programExerciseId: null,
            repRangeLow: 8,
            repRangeHigh: 12,
            loadType: 'weight',
            targetValue: null,
            notes: null,
            coachWithCamera: exercise.supportsCamera,
            plannedSets: setCount,
          ),
        );
        _sets[index] = List.generate(setCount, (_) => _SetEntry(reps: 10));
      }
    }

    // Merge already-logged sets (from either flow above) into the plan.
    for (final loggedSet in session.sets) {
      final exerciseIndex = _plan.indexWhere((p) => p.exercise.id == loggedSet.exerciseId);
      if (exerciseIndex == -1) continue;
      final rows = _sets[exerciseIndex]!;
      while (rows.length <= loggedSet.setIndex) {
        rows.add(_SetEntry(reps: loggedSet.targetReps));
      }
      final row = rows[loggedSet.setIndex];
      row
        ..weightKg = loggedSet.actualWeightKg ?? row.weightKg
        ..reps = loggedSet.actualReps ?? row.reps
        ..setType = loggedSet.setType
        ..logged = loggedSet;
      if (_plan[exerciseIndex].setCount <= loggedSet.setIndex) {
        _plan[exerciseIndex].setCount = loggedSet.setIndex + 1;
      }
    }

    _currentExerciseIndex = 0;
    for (var i = 0; i < _plan.length; i++) {
      if ((_sets[i] ?? const []).any((s) => !s.isDone)) {
        _currentExerciseIndex = i;
        break;
      }
      if (i == _plan.length - 1) _currentExerciseIndex = i;
    }
  }

  int get _totalSets => _sets.values.fold(0, (sum, rows) => sum + rows.length);
  int get _completedSets => _sets.values.fold(0, (sum, rows) => sum + rows.where((s) => s.isDone).length);

  Future<void> _addFreestyleExercise() async {
    final exercise = await showExercisePickerSheet(context);
    if (exercise == null || !mounted) return;
    setState(() {
      final index = _plan.length;
      _plan.add(
        _PlanExercise(
          exercise: exercise,
          programExerciseId: null,
          repRangeLow: 8,
          repRangeHigh: 12,
          loadType: 'weight',
          targetValue: null,
          notes: null,
          coachWithCamera: exercise.supportsCamera,
          plannedSets: 3,
        ),
      );
      _sets[index] = List.generate(3, (_) => _SetEntry(reps: 10));
      _currentExerciseIndex = index;
    });
  }

  void _addSetToCurrentExercise() {
    setState(() {
      final rows = _sets[_currentExerciseIndex] ?? [];
      rows.add(_SetEntry(reps: rows.isNotEmpty ? rows.last.reps : _plan[_currentExerciseIndex].repRangeHigh, weightKg: rows.isNotEmpty ? rows.last.weightKg : null));
      _sets[_currentExerciseIndex] = rows;
      _plan[_currentExerciseIndex].setCount = rows.length;
    });
  }

  Future<void> _editRow(int rowIndex) async {
    final plan = _plan[_currentExerciseIndex];
    final row = _sets[_currentExerciseIndex]![rowIndex];
    final result = await showSetEntrySheet(
      context,
      initialWeightKg: row.weightKg,
      initialReps: row.reps,
      initialSetType: row.setType,
      showPlateMath: plan.loadType == 'weight' && plan.exercise.equipment.contains('barbell'),
    );
    if (result == null || !mounted) return;
    setState(() {
      row.weightKg = result.weightKg;
      row.reps = result.reps;
      row.setType = result.setType;
    });
  }

  String _targetLabel(_PlanExercise plan, _SetEntry? row) {
    final reps = row?.reps ?? plan.repRangeHigh;
    final weight = row?.weightKg;
    if (weight != null && weight > 0) return '${_fmtWeight(weight)}kg × $reps';
    return '${plan.repRangeLabel} reps';
  }

  String _describeNextSet({required bool advancingExercise}) {
    if (advancingExercise) {
      if (_currentExerciseIndex + 1 < _plan.length) {
        final next = _plan[_currentExerciseIndex + 1];
        final firstRow = (_sets[_currentExerciseIndex + 1] ?? const []).isNotEmpty ? _sets[_currentExerciseIndex + 1]!.first : null;
        return '${next.exercise.name} · Set 1 · ${_targetLabel(next, firstRow)}';
      }
      return 'Last set of the workout';
    }
    final rows = _sets[_currentExerciseIndex] ?? const [];
    final nextIndex = rows.indexWhere((s) => !s.isDone);
    final plan = _plan[_currentExerciseIndex];
    if (nextIndex == -1) return 'Last set of ${plan.exercise.name}';
    return '${plan.exercise.name} · Set ${nextIndex + 1} · ${_targetLabel(plan, rows[nextIndex])}';
  }

  static const Map<FlaggedJoint, List<String>> _jointMistakeKeywords = {
    FlaggedJoint.elbow: ['elbow', 'arm'],
    FlaggedJoint.hip: ['hip', 'back', 'torso', 'core', 'spine', 'chest', 'brace'],
    FlaggedJoint.knee: ['knee', 'depth', 'heel', 'foot'],
  };

  /// Prefers a specific, exercise-authored `Exercise.mistakes` entry (rich
  /// title/why/fix content written per-exercise) whose text mentions
  /// whichever joint the live camera coaching flagged most this set, over
  /// the generic score/depth-threshold note — this is what turns "form
  /// dipped" into an actual, exercise-specific correction.
  String? _coachingNoteFor(WorkoutSet set, {Exercise? exercise, FlaggedJoint? flaggedJoint}) {
    if (exercise != null && flaggedJoint != null) {
      final keywords = _jointMistakeKeywords[flaggedJoint] ?? const [];
      for (final mistake in exercise.mistakes) {
        final haystack = '${mistake.title} ${mistake.why} ${mistake.fix}'.toLowerCase();
        if (keywords.any(haystack.contains)) {
          return '${mistake.title} — ${mistake.fix}';
        }
      }
    }
    if (set.formScore != null && set.formScore! < 75) {
      return 'Form dipped to ${set.formScore}/100 on that set — reset your setup before the next one.';
    }
    if (set.depthPct != null && set.depthPct! < 70) {
      return 'That set came in a little short on range of motion — aim to go deeper next time.';
    }
    return null;
  }

  Future<void> _logCurrentSet() async {
    final rows = _sets[_currentExerciseIndex] ?? const [];
    final rowIndex = rows.indexWhere((s) => !s.isDone);
    if (rowIndex == -1) return;
    final plan = _plan[_currentExerciseIndex];
    final row = rows[rowIndex];
    final messenger = ScaffoldMessenger.of(context);

    try {
      final loggedSet = await ref
          .read(workoutRepositoryProvider)
          .logSet(
            widget.sessionId,
            exerciseId: plan.exercise.id,
            setIndex: rowIndex,
            setType: row.setType,
            targetWeightKg: plan.loadType == 'weight' ? plan.targetValue : null,
            targetReps: plan.repRangeHigh,
            actualWeightKg: row.weightKg,
            actualReps: row.reps,
            formScore: row.formScoreHint,
            depthPct: row.romHint,
          );
      if (!mounted) return;

      setState(() {
        row.logged = loggedSet;
        row.weightKg = loggedSet.actualWeightKg ?? row.weightKg;
        row.reps = loggedSet.actualReps ?? row.reps;
      });

      // Snapshot the "last time" baseline before invalidating the list below
      // — the same same-label-session pattern `workout_summary_screen.dart`
      // uses, just matched down to the individual set index.
      final currentLabel = ref.read(sessionProvider(widget.sessionId)).valueOrNull?.label;
      final recentSessions = ref.read(sessionListProvider).valueOrNull ?? const [];
      WorkoutSet? baselineSet;
      if (currentLabel != null) {
        for (final other in recentSessions) {
          if (other.id != widget.sessionId && other.isFinished && other.label == currentLabel) {
            for (final s in other.sets) {
              if (s.exerciseId == plan.exercise.id && s.setIndex == rowIndex) {
                baselineSet = s;
                break;
              }
            }
            break;
          }
        }
      }

      ref.invalidate(sessionListProvider);

      final exerciseFinished = rows.every((s) => s.isDone);
      final workoutComplete = exerciseFinished && _currentExerciseIndex == _plan.length - 1;

      if (loggedSet.isPr) {
        // Best prior set for this exercise across recent (up to 20) sessions —
        // not full history, so this can under-report a genuinely older best,
        // but it's real data rather than a fabricated comparison.
        WorkoutSet? previousBest;
        for (final other in recentSessions) {
          if (other.id == widget.sessionId) continue;
          for (final s in other.sets) {
            if (s.exerciseId == plan.exercise.id && s.actualWeightKg != null) {
              if (previousBest == null || s.actualWeightKg! > previousBest.actualWeightKg!) previousBest = s;
            }
          }
        }
        await showPrCelebration(
          context,
          exerciseName: plan.exercise.name,
          weightKg: row.weightKg ?? 0,
          reps: row.reps ?? 0,
          previousWeightKg: previousBest?.actualWeightKg,
          previousReps: previousBest?.actualReps,
        );
        if (!mounted) return;
      }

      await showPostSetSummarySheet(
        context,
        setIndex: rowIndex,
        exerciseName: plan.exercise.name,
        loggedSet: loggedSet,
        coachingNote: _coachingNoteFor(loggedSet, exercise: plan.exercise, flaggedJoint: row.flaggedJointHint),
        baselineSet: baselineSet,
        isLastSetOfWorkout: workoutComplete,
        goodReps: row.goodRepsHint,
        badReps: row.badRepsHint,
      );
      if (!mounted) return;

      if (workoutComplete) {
        await _finishWorkout();
        return;
      }

      final user = ref.read(authControllerProvider).valueOrNull;
      await showRestTimerSheet(
        context,
        initialSeconds: user?.restTimerDefaultS ?? 90,
        nextSetLabel: _describeNextSet(advancingExercise: exerciseFinished),
        coachingNote: _coachingNoteFor(loggedSet, exercise: plan.exercise, flaggedJoint: row.flaggedJointHint),
      );
      if (!mounted) return;

      if (exerciseFinished) {
        setState(() => _currentExerciseIndex += 1);
      }
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _finishWorkout() async {
    if (_finishing) return;
    _finishing = true;
    try {
      await ref.read(workoutRepositoryProvider).finishSession(widget.sessionId, durationS: _elapsedSeconds);
      ref.invalidate(sessionListProvider);
      ref.invalidate(sessionProvider(widget.sessionId));
      if (!mounted) return;
      context.go(AppRoutes.workoutSummary(widget.sessionId));
    } on ApiException catch (e) {
      _finishing = false;
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  void _openCameraPrecheck() {
    final plan = _plan[_currentExerciseIndex];
    context.push(AppRoutes.workoutCameraPrecheck(widget.sessionId, programExerciseId: plan.programExerciseId));
  }

  void _handleLiveSetFinished(LiveSetResult result) {
    ref.read(pendingCameraCoachProvider.notifier).state = null;
    final rows = _sets[_currentExerciseIndex];
    if (rows == null) return;
    final rowIndex = rows.indexWhere((s) => !s.isDone);
    if (rowIndex == -1) {
      setState(() {});
      return;
    }
    setState(() {
      if (result.reps > 0) rows[rowIndex].reps = result.reps;
      rows[rowIndex].formScoreHint = result.formScore;
      rows[rowIndex].romHint = result.romPct;
      rows[rowIndex].goodRepsHint = result.goodReps;
      rows[rowIndex].badRepsHint = result.badReps;
      rows[rowIndex].flaggedJointHint = result.dominantFlaggedJoint;
    });
  }

  void _handleLiveTrackingCancel() {
    ref.read(pendingCameraCoachProvider.notifier).state = null;
    setState(() {});
  }

  Future<void> _confirmExit() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceHigh,
        title: const Text('Leave this workout?'),
        content: Text(
          'Your progress is saved — you can resume this session later.',
          style: AppTypography.body(size: 13, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('CANCEL')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('LEAVE')),
        ],
      ),
    );
    if (leave == true && mounted) context.go(AppRoutes.today);
  }

  Future<void> _handleMenu(String action) async {
    if (action == 'finish') {
      await _finishWorkout();
    } else if (action == 'delete') {
      try {
        await ref.read(workoutRepositoryProvider).deleteSession(widget.sessionId);
        ref.invalidate(sessionListProvider);
        if (mounted) context.go(AppRoutes.today);
      } on ApiException catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessionAsync = ref.watch(sessionProvider(widget.sessionId));

    return sessionAsync.when(
      loading: () => const Scaffold(backgroundColor: AppColors.surfaceLowest, body: Center(child: CircularProgressIndicator())),
      error: (error, stack) => Scaffold(
        backgroundColor: AppColors.surfaceLowest,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: FormaEmptyState(
                icon: Icons.error_outline,
                title: "That didn't work.",
                message: error is ApiException ? error.message : 'Could not load this workout.',
                primaryLabel: 'RETRY',
                onPrimary: () => ref.invalidate(sessionProvider(widget.sessionId)),
              ),
            ),
          ),
        ),
      ),
      data: (session) {
        if (session.isFinished) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) context.go(AppRoutes.workoutSummary(session.id));
          });
          return const Scaffold(backgroundColor: AppColors.surfaceLowest, body: Center(child: CircularProgressIndicator()));
        }

        if (!_planBuilt) {
          if (session.programDayId != null) {
            final programAsync = ref.watch(_activeProgramProvider);
            return programAsync.when(
              loading: () => const Scaffold(backgroundColor: AppColors.surfaceLowest, body: Center(child: CircularProgressIndicator())),
              error: (error, stack) {
                _initializePlan(session, null);
                return _buildScaffold(context, session);
              },
              data: (program) {
                ProgramDay? day;
                if (program != null) {
                  for (final d in program.days) {
                    if (d.id == session.programDayId) {
                      day = d;
                      break;
                    }
                  }
                }
                _initializePlan(session, day);
                return _buildScaffold(context, session);
              },
            );
          }
          _initializePlan(session, null);
        }
        return _buildScaffold(context, session);
      },
    );
  }

  Widget _buildScaffold(BuildContext context, WorkoutSession session) {
    final pendingCoachSessionId = ref.watch(pendingCameraCoachProvider);
    if (pendingCoachSessionId == widget.sessionId && _plan.isNotEmpty && _currentExerciseIndex < _plan.length) {
      final user = ref.read(authControllerProvider).valueOrNull;
      return Scaffold(
        backgroundColor: AppColors.surfaceLowest,
        body: LiveTrackingOverlay(
          exercise: _plan[_currentExerciseIndex].exercise,
          voiceCoachSettings: user?.voiceCoach ?? const VoiceCoachSettings(),
          onFinish: _handleLiveSetFinished,
          onCancel: _handleLiveTrackingCancel,
        ),
      );
    }

    final currentPlan = _plan.isEmpty ? null : _plan[_currentExerciseIndex];
    final currentRows = _plan.isEmpty ? const <_SetEntry>[] : (_sets[_currentExerciseIndex] ?? const []);
    final canLog = currentRows.any((s) => !s.isDone);
    final firstUndoneIndex = currentRows.indexWhere((s) => !s.isDone);
    final currentSetNumber = firstUndoneIndex == -1 ? currentRows.length : firstUndoneIndex + 1;

    return Scaffold(
      backgroundColor: AppColors.surfaceLowest,
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(
              elapsedLabel: _fmtElapsed(_elapsedSeconds),
              paused: _paused,
              onClose: _confirmExit,
              onTogglePause: () => setState(() => _paused = !_paused),
              onMenuSelected: _handleMenu,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: LoadStrip(total: _totalSets, completed: _completedSets),
            ),
            const SizedBox(height: AppSpacing.xs),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Text(
                '$_completedSets/$_totalSets SETS',
                style: AppTypography.body(size: 11, weight: FontWeight.w700, color: AppColors.textMuted).copyWith(letterSpacing: 1.0),
              ),
            ),
            Expanded(
              child: currentPlan == null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: FormaEmptyState(
                          icon: Icons.add_circle_outline,
                          title: 'Add your first exercise.',
                          message: 'Freestyle workouts start empty — pick what you want to train.',
                          primaryLabel: 'ADD EXERCISE',
                          onPrimary: _addFreestyleExercise,
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.lg),
                      children: [
                        _ExerciseNavRow(
                          index: _currentExerciseIndex,
                          total: _plan.length,
                          onPrev: _currentExerciseIndex > 0 ? () => setState(() => _currentExerciseIndex -= 1) : null,
                          onNext: _currentExerciseIndex < _plan.length - 1 ? () => setState(() => _currentExerciseIndex += 1) : null,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        _ExerciseCard(plan: currentPlan, currentSetNumber: currentSetNumber, totalSets: currentRows.length),
                        if (currentPlan.notes != null && currentPlan.notes!.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.md),
                          InfoBanner(title: 'COACHING NOTE', body: currentPlan.notes, icon: Icons.info_outline),
                        ],
                        const SizedBox(height: AppSpacing.lg),
                        _SetTable(
                          plan: currentPlan,
                          rows: currentRows,
                          onEditRow: (i) => _editRow(i),
                          targetLabel: (row) => _targetLabel(currentPlan, row),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        TextButton.icon(
                          onPressed: _addSetToCurrentExercise,
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('ADD SET'),
                        ),
                        if (_isFreestyle) ...[
                          const SizedBox(height: AppSpacing.sm),
                          TextButton.icon(
                            onPressed: _addFreestyleExercise,
                            icon: const Icon(Icons.add_circle_outline, size: 16),
                            label: const Text('ADD EXERCISE'),
                          ),
                        ],
                      ],
                    ),
            ),
            if (currentPlan != null)
              _BottomActionBar(
                showCoachButton: currentPlan.supportsCoaching && canLog,
                canLog: canLog,
                onCoachSet: _openCameraPrecheck,
                onLogSet: canLog ? _logCurrentSet : null,
              ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.elapsedLabel,
    required this.paused,
    required this.onClose,
    required this.onTogglePause,
    required this.onMenuSelected,
  });

  final String elapsedLabel;
  final bool paused;
  final VoidCallback onClose;
  final VoidCallback onTogglePause;
  final ValueChanged<String> onMenuSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Row(
        children: [
          IconButton(icon: const Icon(Icons.close), onPressed: onClose),
          Expanded(
            child: Center(
              child: Text(elapsedLabel, style: AppTypography.mono(size: 18, weight: FontWeight.w700)),
            ),
          ),
          IconButton(icon: Icon(paused ? Icons.play_arrow : Icons.pause), onPressed: onTogglePause),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: onMenuSelected,
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'finish', child: Text('End workout now')),
              PopupMenuItem(value: 'delete', child: Text('Delete workout')),
            ],
          ),
        ],
      ),
    );
  }
}

class _ExerciseNavRow extends StatelessWidget {
  const _ExerciseNavRow({required this.index, required this.total, required this.onPrev, required this.onNext});

  final int index;
  final int total;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(icon: const Icon(Icons.chevron_left), onPressed: onPrev),
        Text(
          'EXERCISE ${index + 1}/$total',
          style: AppTypography.body(size: 12, weight: FontWeight.w700, color: AppColors.textMuted).copyWith(letterSpacing: 1.0),
        ),
        IconButton(icon: const Icon(Icons.chevron_right), onPressed: onNext),
      ],
    );
  }
}

class _ExerciseCard extends StatelessWidget {
  const _ExerciseCard({required this.plan, required this.currentSetNumber, required this.totalSets});

  final _PlanExercise plan;
  final int currentSetNumber;
  final int totalSets;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceBase,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.surfaceHigh,
              borderRadius: BorderRadius.circular(AppRadius.field),
              border: Border.all(color: AppColors.outlineVariant),
            ),
            child: const Icon(Icons.fitness_center, color: AppColors.textMuted),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(plan.exercise.name, style: AppTypography.display(size: 18)),
                const SizedBox(height: 2),
                Text(plan.exercise.muscleSummary, style: AppTypography.body(size: 12, color: AppColors.textSecondary)),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: 4,
                  children: [
                    if (plan.supportsCoaching)
                      _Chip(text: 'CAMERA READY · ${(plan.exercise.cameraView ?? 'side').toUpperCase()} VIEW', color: AppColors.accentGreen),
                    _Chip(text: 'SET $currentSetNumber/$totalSets', color: AppColors.accentBlue),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(border: Border.all(color: color), borderRadius: BorderRadius.circular(AppRadius.chip)),
      child: Text(text, style: AppTypography.body(size: 10, weight: FontWeight.w700, color: color).copyWith(letterSpacing: 0.4)),
    );
  }
}

class _SetTable extends StatelessWidget {
  const _SetTable({required this.plan, required this.rows, required this.onEditRow, required this.targetLabel});

  final _PlanExercise plan;
  final List<_SetEntry> rows;
  final ValueChanged<int> onEditRow;
  final String Function(_SetEntry?) targetLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
          child: Row(
            children: [
              _headerCell('SET', flex: 2),
              _headerCell('TARGET', flex: 4),
              _headerCell('KG', flex: 2),
              _headerCell('REPS', flex: 2),
              const SizedBox(width: 28),
            ],
          ),
        ),
        for (var i = 0; i < rows.length; i++) _SetRow(index: i, entry: rows[i], target: targetLabel(rows[i]), onTap: () => onEditRow(i)),
      ],
    );
  }

  Widget _headerCell(String text, {required int flex}) {
    return Expanded(
      flex: flex,
      child: Text(text, style: AppTypography.body(size: 10, weight: FontWeight.w700, color: AppColors.textMuted).copyWith(letterSpacing: 0.8)),
    );
  }
}

class _SetRow extends StatelessWidget {
  const _SetRow({required this.index, required this.entry, required this.target, required this.onTap});

  final int index;
  final _SetEntry entry;
  final String target;
  final VoidCallback onTap;

  String get _setLabel {
    switch (entry.setType) {
      case 'warmup':
        return 'W${index + 1}';
      case 'drop':
        return 'D${index + 1}';
      default:
        return '${index + 1}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final done = entry.isDone;
    return InkWell(
      onTap: done ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.outlineVariant))),
        child: Row(
          children: [
            Expanded(flex: 2, child: Text(_setLabel, style: AppTypography.mono(size: 13, weight: FontWeight.w600))),
            Expanded(flex: 4, child: Text(target, style: AppTypography.body(size: 12, color: AppColors.textSecondary))),
            Expanded(
              flex: 2,
              child: Text(
                entry.weightKg == null ? '—' : _fmtWeight(entry.weightKg!),
                style: AppTypography.mono(size: 14, weight: FontWeight.w600),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(entry.reps?.toString() ?? '—', style: AppTypography.mono(size: 14, weight: FontWeight.w600)),
            ),
            SizedBox(
              width: 28,
              child: Icon(
                done ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 18,
                color: done ? AppColors.accentGreen : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomActionBar extends StatelessWidget {
  const _BottomActionBar({required this.showCoachButton, required this.canLog, required this.onCoachSet, required this.onLogSet});

  final bool showCoachButton;
  final bool canLog;
  final VoidCallback onCoachSet;
  final VoidCallback? onLogSet;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.md),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.outlineVariant))),
      child: Row(
        children: [
          if (showCoachButton) ...[
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onCoachSet,
                icon: const Icon(Icons.videocam_outlined, size: 18),
                label: const Text('COACH SET'),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          Expanded(flex: 2, child: FilledButton(onPressed: onLogSet, child: const Text('LOG SET'))),
        ],
      ),
    );
  }
}
