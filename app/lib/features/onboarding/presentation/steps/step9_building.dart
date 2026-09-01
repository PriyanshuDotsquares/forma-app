import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/router/app_router.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../programs/presentation/programs_providers.dart';
import '../onboarding_controller.dart';

/// The final "Building your plan" step. Runs a short staged checklist
/// animation while the real work happens underneath: PATCH `/onboarding`
/// with the collected answers, then POST `/programs/generate`. The
/// checklist is perceived-progress UI, not a fake progress bar — the
/// network calls are genuinely in flight while it plays.
class Step9Building extends ConsumerStatefulWidget {
  const Step9Building({super.key, required this.onCancel});

  final VoidCallback onCancel;

  @override
  ConsumerState<Step9Building> createState() => _Step9BuildingState();
}

class _Step9BuildingState extends ConsumerState<Step9Building> {
  static const _stepDelay = Duration(milliseconds: 520);

  late List<bool> _checked;
  double _progress = 0;
  Object? _error;
  bool _cancelled = false;
  int _run = 0;

  @override
  void initState() {
    super.initState();
    _checked = List.filled(_items(ref.read(onboardingControllerProvider)).length, false);
    _start();
  }

  List<String> _items(OnboardingAnswers answers) {
    final splitLabel = splitPreferenceLabel(answers.splitPreference, daysPerWeek: answers.daysPerWeek);
    final exerciseCount = 48 + answers.canonicalEquipment.length * 27;
    return [
      'Chose your split — $splitLabel',
      'Found $exerciseCount exercises you can actually do',
      'Setting your starting weights',
      'Checking weekly volume',
      'Writing your first week',
    ];
  }

  Future<void> _start() async {
    final myRun = ++_run;
    _cancelled = false;
    setState(() {
      _error = null;
      _checked = List.filled(_items(ref.read(onboardingControllerProvider)).length, false);
      _progress = 0;
    });

    await Future.wait([_animateChecklist(myRun), _submit(myRun)]);

    if (_cancelled || myRun != _run || !mounted) return;
    if (_error == null) {
      // A plain Navigator.push here used to lose a race against the
      // router's redirect-on-onboarded logic, which would swap out
      // /onboarding (and this pushed page with it) before it ever showed.
      context.push(AppRoutes.onboardingPlanPreview);
    }
  }

  Future<void> _animateChecklist(int myRun) async {
    final total = _checked.length;
    for (var i = 0; i < total; i++) {
      await Future.delayed(_stepDelay);
      if (_cancelled || myRun != _run || !mounted) return;
      setState(() {
        _checked[i] = true;
        _progress = (i + 1) / total;
      });
    }
  }

  Future<void> _submit(int myRun) async {
    try {
      final answers = ref.read(onboardingControllerProvider);

      // Generate the plan FIRST, passing the quiz answers directly as
      // overrides — not via the saved profile, which doesn't exist yet.
      // `submitOnboarding` is what flips `onboarding_completed` to true,
      // and the router redirects to /today the instant that happens; if it
      // ran first, the redirect would race ahead of plan generation and
      // land the user on an empty dashboard even though the plan is about
      // to succeed a moment later. Generating first means the program
      // already exists by the time that redirect can fire.
      await ref
          .read(programsRepositoryProvider)
          .generateProgram(
            goal: answers.goal,
            experienceLevel: answers.experienceLevel,
            daysPerWeek: answers.daysPerWeek,
            sessionMinutes: answers.sessionMinutes,
            splitPreference: answers.splitPreference,
            equipment: answers.canonicalEquipment,
          );

      final payload = answers.toOnboardingPayload();
      // Set before submitting: this is what keeps the router's redirect
      // from bouncing to /today the instant `onboarding_completed` flips,
      // before the plan-preview push below even runs.
      ref.read(onboardingPostFlowActiveProvider.notifier).state = true;
      await ref.read(authControllerProvider.notifier).submitOnboarding(payload);
    } catch (e) {
      if (_cancelled || myRun != _run || !mounted) return;
      setState(() => _error = e);
    }
  }

  void _cancel() {
    _cancelled = true;
    widget.onCancel();
  }

  @override
  Widget build(BuildContext context) {
    final answers = ref.watch(onboardingControllerProvider);
    final items = _items(answers);

    if (_error != null) {
      final message = _error is ApiException ? (_error as ApiException).message : 'Something went wrong while building your plan.';
      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Center(
              child: FormaEmptyState(
                icon: Icons.error_outline,
                iconColor: AppColors.error,
                title: "That didn't work",
                message: message,
                primaryLabel: 'Try again',
                onPrimary: _start,
                secondaryLabel: 'Back to review',
                onSecondary: widget.onCancel,
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Text(AppLocalizations.of(context)!.step9Title, textAlign: TextAlign.center, style: AppTypography.display(size: 30)),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Crunching your answers into your first week.',
                textAlign: TextAlign.center,
                style: AppTypography.body(size: 14, color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.xl),
              for (var i = 0; i < items.length; i++) ...[
                _ChecklistRow(label: items[i], checked: _checked[i]),
                const SizedBox(height: AppSpacing.sm),
              ],
              const SizedBox(height: AppSpacing.lg),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: _progress, minHeight: 8),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                _progress >= 1 ? 'Finishing up…' : '${(_progress * 100).round()}%',
                textAlign: TextAlign.center,
                style: AppTypography.mono(size: 13, color: AppColors.textSecondary),
              ),
              const Spacer(),
              Center(child: TextButton(onPressed: _cancel, child: const Text('CANCEL'))),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChecklistRow extends StatelessWidget {
  const _ChecklistRow({required this.label, required this.checked});

  final String label;
  final bool checked;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: checked ? 1 : 0.5,
      duration: const Duration(milliseconds: 200),
      child: Row(
        children: [
          Icon(
            checked ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 20,
            color: checked ? AppColors.accentGreen : AppColors.outline,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(label, style: AppTypography.body(size: 14))),
        ],
      ),
    );
  }
}
