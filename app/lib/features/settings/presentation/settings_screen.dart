import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/app_router.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../auth/domain/user.dart';
import '../../auth/presentation/auth_controller.dart';
import 'language_screen.dart';
import 'widgets/settings_row.dart';

class _LabeledOption {
  const _LabeledOption(this.value, this.label);
  final String value;
  final String label;
}

const _goalOptions = [
  _LabeledOption('build_muscle', 'Build muscle'),
  _LabeledOption('get_stronger', 'Get stronger'),
  _LabeledOption('lose_fat', 'Lose fat'),
  _LabeledOption('general_health', 'General health'),
  _LabeledOption('athletic_performance', 'Athletic performance'),
  _LabeledOption('move_better', 'Move better'),
];

const _experienceOptions = [
  _LabeledOption('new', 'New to lifting'),
  _LabeledOption('machines', 'I know the machines'),
  _LabeledOption('free_weights', 'Free weights, confidently'),
  _LabeledOption('programs_own', 'I program my own training'),
];

class _EquipmentOption {
  const _EquipmentOption(this.token, this.label, this.icon);
  final String token;
  final String label;
  final IconData icon;
}

// The exercise library only understands this fixed vocabulary (see
// onboarding's `EquipmentCatalog` doc comment) — `User.equipment` stores
// exactly these tokens, so the settings editor targets them directly
// rather than re-deriving them from a granular picker.
const _equipmentOptions = [
  _EquipmentOption('barbell', 'Barbell', Icons.fitness_center),
  _EquipmentOption('dumbbell', 'Dumbbells', Icons.sports_gymnastics),
  _EquipmentOption('kettlebell', 'Kettlebells', Icons.sports_kabaddi),
  _EquipmentOption('cable', 'Cables', Icons.cable),
  _EquipmentOption('machine', 'Machines', Icons.precision_manufacturing),
  _EquipmentOption('bodyweight', 'Bodyweight only', Icons.accessibility_new),
];

const _bodyParts = ['shoulder', 'knee', 'lower_back', 'hip', 'elbow', 'wrist', 'ankle', 'neck'];

const _sessionMinuteOptions = [30, 45, 60, 75, 90];

String _humanize(String? raw) {
  if (raw == null || raw.isEmpty) return 'Not set';
  return raw.split('_').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
}

String _goalRowLabel(String? goal) {
  if (goal == null) return 'Not set';
  for (final o in _goalOptions) {
    if (o.value == goal) return o.label;
  }
  return _humanize(goal);
}

String _formatMmSs(int seconds) {
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// The settings form — reached from the profile hub's "Settings" row. The
/// Figma frame's own header copy reads "< Achievements" (a mislabel carried
/// over from a duplicated frame), so this uses "Settings" as the real title.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).valueOrNull;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: user == null
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xxl),
                children: [
                  SettingsSection(
                    title: l10n.sectionTraining,
                    rows: [
                      SettingsRow(
                        // Figma's icon is concentric rings (a bullseye), not a flag.
                        icon: Icons.track_changes,
                        label: l10n.rowGoalsExperience,
                        valueText: _goalRowLabel(user.goal),
                        onTap: () => _showGoalsSheet(context, ref, user),
                      ),
                      SettingsRow(
                        icon: Icons.calendar_today_outlined,
                        label: l10n.rowSchedule,
                        valueText: (user.daysPerWeek != null && user.sessionMinutes != null)
                            ? '${user.daysPerWeek} days · ${user.sessionMinutes} min'
                            : 'Not set',
                        onTap: () => _showScheduleSheet(context, ref, user),
                      ),
                      SettingsRow(
                        // Figma's icon is a kit-bag/case glyph, not a barbell.
                        icon: Icons.work_outline,
                        label: l10n.rowEquipment,
                        valueText: '${user.equipment.length} items',
                        onTap: () => _showEquipmentSheet(context, ref, user),
                      ),
                      SettingsRow(
                        icon: Icons.healing_outlined,
                        label: l10n.rowInjuries,
                        valueText: user.injuries.isEmpty ? 'None' : null,
                        trailing: user.injuries.isEmpty
                            ? null
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.accentRed),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '${user.injuries.length} active',
                                    style: AppTypography.body(size: 13, color: AppColors.textSecondary),
                                  ),
                                ],
                              ),
                        onTap: () => _showInjuriesSheet(context, ref, user),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  SettingsSection(
                    title: l10n.sectionCoachCamera,
                    rows: [
                      SettingsRow(
                        icon: Icons.record_voice_over_outlined,
                        label: l10n.rowVoiceCoach,
                        valueText: _humanize(user.voiceCoach.verbosity),
                        onTap: () => context.push(AppRoutes.voiceCoachSettings),
                      ),
                      SettingsRow(
                        icon: Icons.videocam_outlined,
                        label: l10n.rowCameraPrivacy,
                        onTap: () => _showCameraPrivacySheet(context),
                      ),
                      SettingsRow(
                        icon: Icons.timer_outlined,
                        label: l10n.rowRestTimer,
                        valueText: '${_formatMmSs(user.restTimerDefaultS)} default',
                        onTap: () => _showRestTimerSheet(context, ref, user),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  SettingsSection(
                    title: l10n.sectionApp,
                    rows: [
                      SettingsRow(
                        icon: Icons.dark_mode_outlined,
                        label: l10n.rowAppearance,
                        valueText: 'Dark',
                        showChevron: false,
                        enabled: false,
                      ),
                      SettingsRow(
                        icon: Icons.straighten_outlined,
                        label: l10n.rowUnits,
                        valueText: user.units == 'imperial' ? 'lb · ft' : 'kg · cm',
                        onTap: () => _showUnitsSheet(context, ref, user),
                      ),
                      SettingsRow(
                        icon: Icons.notifications_outlined,
                        label: l10n.rowNotifications,
                        onTap: () => _showNotificationsSheet(context, ref, user),
                      ),
                      SettingsRow(
                        icon: Icons.language_outlined,
                        label: l10n.rowLanguage,
                        valueText: localeDisplayName(user.locale),
                        onTap: () => context.push(AppRoutes.languageSettings),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  SettingsSection(
                    title: l10n.sectionAccount,
                    rows: [
                      SettingsRow(
                        icon: Icons.email_outlined,
                        label: l10n.rowEmail,
                        valueText: user.email,
                        onTap: () => _showChangeEmailSheet(context, ref),
                      ),
                      SettingsRow(
                        icon: Icons.lock_outline,
                        label: l10n.rowPassword,
                        onTap: () => _showChangePasswordSheet(context, ref),
                      ),
                      SettingsRow(
                        icon: Icons.logout,
                        label: l10n.rowSignOut,
                        destructive: true,
                        showChevron: false,
                        onTap: () => _confirmSignOut(context, ref),
                      ),
                      SettingsRow(
                        icon: Icons.delete_outline,
                        label: l10n.rowDeleteAccount,
                        destructive: true,
                        showChevron: false,
                        onTap: () => _confirmDeleteAccount(context),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}

Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Sign out?'),
      content: const Text("You'll need to sign back in to keep training."),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text('Sign out', style: AppTypography.body(weight: FontWeight.w700, color: AppColors.error)),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  await ref.read(authControllerProvider.notifier).logout();
  // The router's redirect also catches the cleared auth state automatically,
  // but navigate explicitly so the transition is immediate and clean.
  if (context.mounted) context.go(AppRoutes.intro);
}

void _confirmDeleteAccount(BuildContext context) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete account'),
      content: const Text(
        "Account deletion isn't available yet — there's no deletion endpoint on this build. Contact support if you'd like your account removed.",
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))],
    ),
  );
}

Future<void> _showGoalsSheet(BuildContext context, WidgetRef ref, User user) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => _GoalsExperienceSheet(initialGoal: user.goal, initialExperience: user.experienceLevel),
  );
}

class _GoalsExperienceSheet extends ConsumerStatefulWidget {
  const _GoalsExperienceSheet({required this.initialGoal, required this.initialExperience});
  final String? initialGoal;
  final String? initialExperience;

  @override
  ConsumerState<_GoalsExperienceSheet> createState() => _GoalsExperienceSheetState();
}

class _GoalsExperienceSheetState extends ConsumerState<_GoalsExperienceSheet> {
  late String? _goal = widget.initialGoal;
  late String? _experience = widget.initialExperience;
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      // `/onboarding` applies only the keys present in the payload (see
      // `OnboardingUpdate` — FastAPI's `exclude_unset`), so this can be
      // reused as a general-purpose partial profile-field editor without
      // disturbing anything else already on the account.
      await ref.read(authControllerProvider.notifier).submitOnboarding({
        if (_goal != null) 'goal': _goal,
        if (_experience != null) 'experience_level': _experience,
      });
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not save. Try again.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionLabel('Goal'),
            const SizedBox(height: AppSpacing.xs),
            for (final o in _goalOptions)
              RadioListTile<String>(
                value: o.value,
                groupValue: _goal,
                onChanged: (v) => setState(() => _goal = v),
                title: Text(o.label),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            const SizedBox(height: AppSpacing.md),
            const SectionLabel('Experience'),
            const SizedBox(height: AppSpacing.xs),
            for (final o in _experienceOptions)
              RadioListTile<String>(
                value: o.value,
                groupValue: _experience,
                onChanged: (v) => setState(() => _experience = v),
                title: Text(o.label),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showScheduleSheet(BuildContext context, WidgetRef ref, User user) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => _ScheduleSheet(initialDays: user.daysPerWeek, initialMinutes: user.sessionMinutes),
  );
}

class _ScheduleSheet extends ConsumerStatefulWidget {
  const _ScheduleSheet({required this.initialDays, required this.initialMinutes});
  final int? initialDays;
  final int? initialMinutes;

  @override
  ConsumerState<_ScheduleSheet> createState() => _ScheduleSheetState();
}

class _ScheduleSheetState extends ConsumerState<_ScheduleSheet> {
  late int _days = widget.initialDays ?? 3;
  late int _minutes = widget.initialMinutes ?? 45;
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(authControllerProvider.notifier).submitOnboarding({'days_per_week': _days, 'session_minutes': _minutes});
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not save. Try again.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionLabel('Days per week'),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (var d = 1; d <= 7; d++)
                  ChoiceChip(
                    label: Text('$d'),
                    selected: _days == d,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _days = d),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            const SectionLabel('Session length'),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final m in _sessionMinuteOptions)
                  ChoiceChip(
                    label: Text('$m min'),
                    selected: _minutes == m,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _minutes = m),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showEquipmentSheet(BuildContext context, WidgetRef ref, User user) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => _EquipmentSheet(initial: user.equipment),
  );
}

class _EquipmentSheet extends ConsumerStatefulWidget {
  const _EquipmentSheet({required this.initial});
  final List<String> initial;

  @override
  ConsumerState<_EquipmentSheet> createState() => _EquipmentSheetState();
}

class _EquipmentSheetState extends ConsumerState<_EquipmentSheet> {
  late final Set<String> _selected = {...widget.initial};
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(authControllerProvider.notifier).submitOnboarding({'equipment': (_selected.toList()..sort())});
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not save. Try again.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionLabel('Equipment'),
            const SizedBox(height: AppSpacing.xs),
            for (final o in _equipmentOptions)
              CheckboxListTile(
                value: _selected.contains(o.token),
                onChanged: (v) => setState(() {
                  if (v == true) {
                    _selected.add(o.token);
                  } else {
                    _selected.remove(o.token);
                  }
                }),
                title: Text(o.label),
                secondary: Icon(o.icon),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showInjuriesSheet(BuildContext context, WidgetRef ref, User user) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => _InjuriesSheet(initial: user.injuries),
  );
}

class _InjuriesSheet extends ConsumerStatefulWidget {
  const _InjuriesSheet({required this.initial});
  final List<Injury> initial;

  @override
  ConsumerState<_InjuriesSheet> createState() => _InjuriesSheetState();
}

class _InjuriesSheetState extends ConsumerState<_InjuriesSheet> {
  late final Set<String> _active = {for (final i in widget.initial) i.part};
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    // Coarser than the onboarding quiz's granular per-side/severity picker
    // — a quick settings edit just tracks "avoid training this area", so
    // every checked part is stored as a moderate, both-sides limitation.
    final injuries = [for (final part in _active) Injury(part: part, side: 'both', severity: 'moderate')];
    try {
      await ref.read(authControllerProvider.notifier).submitOnboarding({'injuries': injuries.map((i) => i.toJson()).toList()});
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not save. Try again.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionLabel('Injuries & limits'),
            const SizedBox(height: 4),
            Text('Areas to train carefully around.', style: AppTypography.body(size: 13, color: AppColors.textSecondary)),
            const SizedBox(height: AppSpacing.sm),
            for (final part in _bodyParts)
              CheckboxListTile(
                value: _active.contains(part),
                onChanged: (v) => setState(() {
                  if (v == true) {
                    _active.add(part);
                  } else {
                    _active.remove(part);
                  }
                }),
                title: Text(_humanize(part)),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showRestTimerSheet(BuildContext context, WidgetRef ref, User user) {
  return showModalBottomSheet(
    context: context,
    builder: (context) => _RestTimerSheet(initial: user.restTimerDefaultS),
  );
}

class _RestTimerSheet extends ConsumerStatefulWidget {
  const _RestTimerSheet({required this.initial});
  final int initial;

  @override
  ConsumerState<_RestTimerSheet> createState() => _RestTimerSheetState();
}

class _RestTimerSheetState extends ConsumerState<_RestTimerSheet> {
  late int _seconds = widget.initial;
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(authControllerProvider.notifier).updateProfile(restTimerDefaultS: _seconds);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not save. Try again.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SectionLabel('Rest timer'),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: _seconds > 15 ? () => setState(() => _seconds = (_seconds - 15).clamp(15, 600)) : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              SizedBox(
                width: 110,
                child: Text(_formatMmSs(_seconds), textAlign: TextAlign.center, style: AppTypography.display(size: 32)),
              ),
              IconButton(
                onPressed: _seconds < 600 ? () => setState(() => _seconds = (_seconds + 15).clamp(15, 600)) : null,
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save'),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _showUnitsSheet(BuildContext context, WidgetRef ref, User user) {
  return showModalBottomSheet(
    context: context,
    builder: (context) => _UnitsSheet(initial: user.units),
  );
}

class _UnitsSheet extends ConsumerStatefulWidget {
  const _UnitsSheet({required this.initial});
  final String initial;

  @override
  ConsumerState<_UnitsSheet> createState() => _UnitsSheetState();
}

class _UnitsSheetState extends ConsumerState<_UnitsSheet> {
  bool _saving = false;

  Future<void> _select(String units) async {
    if (units == widget.initial) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(authControllerProvider.notifier).updateProfile(units: units);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not save. Try again.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('Units'),
          const SizedBox(height: AppSpacing.xs),
          RadioListTile<String>(
            value: 'metric',
            groupValue: widget.initial,
            onChanged: _saving ? null : (_) => _select('metric'),
            title: const Text('Metric — kg · cm'),
            contentPadding: EdgeInsets.zero,
          ),
          RadioListTile<String>(
            value: 'imperial',
            groupValue: widget.initial,
            onChanged: _saving ? null : (_) => _select('imperial'),
            title: const Text('Imperial — lb · ft'),
            contentPadding: EdgeInsets.zero,
          ),
          if (_saving) const Padding(padding: EdgeInsets.only(top: AppSpacing.sm), child: LinearProgressIndicator()),
        ],
      ),
    );
  }
}

Future<void> _showCameraPrivacySheet(BuildContext context) async {
  final status = await Permission.camera.status;
  if (!context.mounted) return;
  showModalBottomSheet(
    context: context,
    builder: (context) => Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('Camera & privacy'),
          const SizedBox(height: AppSpacing.md),
          InfoBanner(
            title: 'Camera access: ${_permissionLabel(status)}',
            body:
                'FORMA only uses your camera live, during a workout, to track your form. Nothing is uploaded or '
                'recorded without your say-so.',
            icon: Icons.videocam_outlined,
            accent: status.isGranted ? AppColors.accentGreen : AppColors.accentAmber,
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(onPressed: openAppSettings, child: const Text('Open system settings')),
          ),
        ],
      ),
    ),
  );
}

Future<void> _showNotificationsSheet(BuildContext context, WidgetRef ref, User user) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => _NotificationsSheet(initial: user.notificationPrefs),
  );
}

class _NotificationsSheet extends ConsumerStatefulWidget {
  const _NotificationsSheet({required this.initial});
  final NotificationPrefs initial;

  @override
  ConsumerState<_NotificationsSheet> createState() => _NotificationsSheetState();
}

class _NotificationsSheetState extends ConsumerState<_NotificationsSheet> {
  late NotificationPrefs _prefs = widget.initial;
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(authControllerProvider.notifier).updateProfile(notificationPrefs: _prefs.toJson());
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not save. Try again.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionLabel('Notifications'),
            const SizedBox(height: 4),
            Text(
              "These preferences are saved now and will govern what gets pushed to your device once FORMA's push "
              "notification service is wired up — no notifications send yet.",
              style: AppTypography.body(size: 12, color: AppColors.textMuted),
            ),
            const SizedBox(height: AppSpacing.sm),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Workout reminders'),
              value: _prefs.workoutReminders,
              onChanged: (v) => setState(() => _prefs = _prefs.copyWith(workoutReminders: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Achievement alerts'),
              value: _prefs.achievementAlerts,
              onChanged: (v) => setState(() => _prefs = _prefs.copyWith(achievementAlerts: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Weekly summary'),
              value: _prefs.weeklySummary,
              onChanged: (v) => setState(() => _prefs = _prefs.copyWith(weeklySummary: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Challenge updates'),
              value: _prefs.challengeUpdates,
              onChanged: (v) => setState(() => _prefs = _prefs.copyWith(challengeUpdates: v)),
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showChangePasswordSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => const _ChangePasswordSheet(),
  );
}

class _ChangePasswordSheet extends ConsumerStatefulWidget {
  const _ChangePasswordSheet();

  @override
  ConsumerState<_ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends ConsumerState<_ChangePasswordSheet> {
  final _formKey = GlobalKey<FormState>();
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).changePassword(
        currentPassword: _currentController.text,
        newPassword: _newController.text,
      );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password updated.')));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e is ApiException ? e.message : 'Could not update your password.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel('Change password'),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _currentController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'CURRENT PASSWORD'),
                validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _newController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'NEW PASSWORD'),
                validator: (v) => (v == null || v.length < 8) ? 'At least 8 characters' : null,
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(_error!, style: AppTypography.body(size: 13, color: AppColors.error)),
              ],
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _showChangeEmailSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => const _ChangeEmailSheet(),
  );
}

class _ChangeEmailSheet extends ConsumerStatefulWidget {
  const _ChangeEmailSheet();

  @override
  ConsumerState<_ChangeEmailSheet> createState() => _ChangeEmailSheetState();
}

class _ChangeEmailSheetState extends ConsumerState<_ChangeEmailSheet> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).changeEmail(
        newEmail: _emailController.text.trim(),
        password: _passwordController.text,
      );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Email updated.')));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e is ApiException ? e.message : 'Could not update your email.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel('Change email'),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'NEW EMAIL', hintText: 'you@example.com'),
                validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'CURRENT PASSWORD'),
                validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(_error!, style: AppTypography.body(size: 13, color: AppColors.error)),
              ],
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _permissionLabel(PermissionStatus status) {
  if (status.isGranted) return 'Allowed';
  if (status.isPermanentlyDenied) return 'Denied — enable in system settings';
  if (status.isRestricted) return 'Restricted';
  if (status.isLimited) return 'Limited';
  return 'Not yet granted';
}
