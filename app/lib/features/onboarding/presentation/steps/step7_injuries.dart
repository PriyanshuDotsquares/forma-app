import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../auth/domain/user.dart';
import '../onboarding_controller.dart';
import '../widgets/onboarding_step_scaffold.dart';

class _BodyZone {
  const _BodyZone(this.part, this.side, this.dx, this.dy, {this.frontOnly = false, this.backOnly = false});
  final String part; // matches Injury.part
  final String side; // left | right | both
  final double dx; // fractional x within the body box
  final double dy; // fractional y within the body box
  final bool frontOnly;
  final bool backOnly;
}

const _zones = [
  _BodyZone('shoulder', 'left', 0.28, 0.19),
  _BodyZone('shoulder', 'right', 0.72, 0.19),
  _BodyZone('chest', 'both', 0.5, 0.28, frontOnly: true),
  _BodyZone('back', 'both', 0.5, 0.30, backOnly: true),
  _BodyZone('elbow', 'left', 0.18, 0.38),
  _BodyZone('elbow', 'right', 0.82, 0.38),
  _BodyZone('hip', 'both', 0.5, 0.52),
  _BodyZone('knee', 'left', 0.40, 0.77),
  _BodyZone('knee', 'right', 0.60, 0.77),
];

String _zoneLabel(String part, String side) {
  final label = part[0].toUpperCase() + part.substring(1);
  if (side == 'both') return label;
  final sideLabel = side == 'left' ? 'Left' : 'Right';
  return '$sideLabel $label';
}

Color _severityColor(String severity) {
  switch (severity) {
    case 'avoid':
      return AppColors.accentRed;
    case 'moderate':
      return AppColors.accentAmber;
    case 'mild':
    default:
      return AppColors.accentAmber.withValues(alpha: 0.55);
  }
}

String _severityLabel(String severity) {
  switch (severity) {
    case 'avoid':
      return 'Avoid';
    case 'moderate':
      return 'Moderate';
    case 'mild':
    default:
      return 'Mild';
  }
}

class Step7Injuries extends ConsumerStatefulWidget {
  const Step7Injuries({super.key, required this.onBack, required this.onContinue});

  final VoidCallback onBack;
  final VoidCallback onContinue;

  @override
  ConsumerState<Step7Injuries> createState() => _Step7InjuriesState();
}

class _Step7InjuriesState extends ConsumerState<Step7Injuries> {
  bool _front = true;
  _BodyZone? _activeZone;
  late final TextEditingController _noteController;

  @override
  void initState() {
    super.initState();
    _noteController = TextEditingController();
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Injury? _injuryFor(_BodyZone zone, List<Injury> injuries) {
    for (final injury in injuries) {
      if (injury.part == zone.part && injury.side == zone.side) return injury;
    }
    return null;
  }

  void _selectZone(_BodyZone zone, List<Injury> injuries) {
    final existing = _injuryFor(zone, injuries);
    setState(() {
      _activeZone = zone;
      _noteController.text = existing?.note ?? '';
    });
  }

  void _saveSeverity(String severity) {
    final zone = _activeZone;
    if (zone == null) return;
    ref
        .read(onboardingControllerProvider.notifier)
        .setInjury(Injury(part: zone.part, side: zone.side, severity: severity, note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim()));
  }

  void _saveNote(String note) {
    final zone = _activeZone;
    if (zone == null) return;
    final existing = _injuryFor(zone, ref.read(onboardingControllerProvider).injuries);
    ref
        .read(onboardingControllerProvider.notifier)
        .setInjury(Injury(part: zone.part, side: zone.side, severity: existing?.severity ?? 'mild', note: note.trim().isEmpty ? null : note.trim()));
  }

  void _removeActiveZone() {
    final zone = _activeZone;
    if (zone == null) return;
    ref.read(onboardingControllerProvider.notifier).removeInjury(zone.part, zone.side);
    setState(() => _activeZone = null);
  }

  @override
  Widget build(BuildContext context) {
    final answers = ref.watch(onboardingControllerProvider);
    final injuries = answers.injuries;
    final visibleZones = _zones.where((z) => _front ? !z.backOnly : !z.frontOnly).toList();

    final l10n = AppLocalizations.of(context)!;
    return OnboardingStepScaffold(
      stepNumber: 7,
      totalSteps: kOnboardingTotalSteps,
      title: l10n.step7Title,
      subtitle: "Tap any area that's injured, painful, or limited. We'll build the plan around it.",
      onBack: widget.onBack,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.center,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(color: AppColors.surfaceHigh, borderRadius: BorderRadius.circular(AppRadius.button)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ViewTab(label: 'FRONT', selected: _front, onTap: () => setState(() => _front = true)),
                  _ViewTab(label: 'BACK', selected: !_front, onTap: () => setState(() => _front = false)),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Center(
            child: SizedBox(
              width: 220,
              height: 360,
              child: Stack(
                children: [
                  Positioned.fill(child: CustomPaint(painter: _BodyPainter(front: _front))),
                  for (final zone in visibleZones)
                    Positioned(
                      left: zone.dx * 220 - 14,
                      top: zone.dy * 360 - 14,
                      child: _Hotspot(
                        injury: _injuryFor(zone, injuries),
                        active: _activeZone?.part == zone.part && _activeZone?.side == zone.side,
                        onTap: () => _selectZone(zone, injuries),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (_activeZone != null) _ZoneEditor(
            zone: _activeZone!,
            injury: _injuryFor(_activeZone!, injuries),
            noteController: _noteController,
            onSeverityChanged: _saveSeverity,
            onNoteChanged: _saveNote,
            onRemove: _removeActiveZone,
            onClose: () => setState(() => _activeZone = null),
          ),
          if (injuries.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            const SectionLabel('AREAS YOU FLAGGED'),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final injury in injuries)
                  _InjuryChip(
                    injury: injury,
                    onTap: () => _selectZone(
                      _zones.firstWhere((z) => z.part == injury.part && z.side == injury.side, orElse: () => _zones.first),
                      injuries,
                    ),
                    onRemove: () => ref.read(onboardingControllerProvider.notifier).removeInjury(injury.part, injury.side),
                  ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          OutlinedButton(
            onPressed: () {
              ref.read(onboardingControllerProvider.notifier).clearInjuries();
              widget.onContinue();
            },
            child: Text(l10n.onboardingNothingToReport),
          ),
          const SizedBox(height: AppSpacing.lg),
          InfoBanner(
            title: 'Not medical advice',
            body: 'FORMA gives coaching cues, not medical advice. Check with a professional before starting, and stop if anything hurts.',
            icon: Icons.shield_outlined,
            accent: AppColors.accentAmber,
          ),
        ],
      ),
      footer: SizedBox(
        width: double.infinity,
        child: FilledButton(onPressed: widget.onContinue, child: Text(l10n.onboardingContinue)),
      ),
    );
  }
}

class _ViewTab extends StatelessWidget {
  const _ViewTab({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.button - 4),
        ),
        child: Text(
          label,
          style: AppTypography.body(size: 12, weight: FontWeight.w700, color: selected ? AppColors.accentBlueDark : AppColors.textSecondary),
        ),
      ),
    );
  }
}

class _Hotspot extends StatelessWidget {
  const _Hotspot({required this.injury, required this.active, required this.onTap});

  final Injury? injury;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = injury != null ? _severityColor(injury!.severity) : AppColors.surfaceHigh;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(color: active ? AppColors.accentBlue : AppColors.outline, width: active ? 2 : 1),
        ),
        child: injury != null ? const Icon(Icons.priority_high, size: 14, color: AppColors.surfaceLowest) : null,
      ),
    );
  }
}

class _BodyPainter extends CustomPainter {
  _BodyPainter({required this.front});

  final bool front;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final w = size.width;
    final h = size.height;

    // Head.
    canvas.drawCircle(Offset(w * 0.5, h * 0.09), h * 0.055, paint);
    // Torso.
    final torso = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.32, h * 0.16, w * 0.36, h * 0.32),
      Radius.circular(w * 0.08),
    );
    canvas.drawRRect(torso, paint);
    // Spine line (back view only).
    if (!front) {
      canvas.drawLine(Offset(w * 0.5, h * 0.18), Offset(w * 0.5, h * 0.46), paint);
    }
    // Arms.
    canvas.drawLine(Offset(w * 0.32, h * 0.20), Offset(w * 0.16, h * 0.42), paint);
    canvas.drawLine(Offset(w * 0.68, h * 0.20), Offset(w * 0.84, h * 0.42), paint);
    // Forearms.
    canvas.drawLine(Offset(w * 0.16, h * 0.42), Offset(w * 0.20, h * 0.58), paint);
    canvas.drawLine(Offset(w * 0.84, h * 0.42), Offset(w * 0.80, h * 0.58), paint);
    // Pelvis.
    canvas.drawLine(Offset(w * 0.34, h * 0.48), Offset(w * 0.66, h * 0.48), paint);
    // Legs.
    canvas.drawLine(Offset(w * 0.42, h * 0.48), Offset(w * 0.40, h * 0.77), paint);
    canvas.drawLine(Offset(w * 0.58, h * 0.48), Offset(w * 0.60, h * 0.77), paint);
    // Shins.
    canvas.drawLine(Offset(w * 0.40, h * 0.77), Offset(w * 0.39, h * 0.96), paint);
    canvas.drawLine(Offset(w * 0.60, h * 0.77), Offset(w * 0.61, h * 0.96), paint);
  }

  @override
  bool shouldRepaint(covariant _BodyPainter oldDelegate) => oldDelegate.front != front;
}

class _ZoneEditor extends StatelessWidget {
  const _ZoneEditor({
    required this.zone,
    required this.injury,
    required this.noteController,
    required this.onSeverityChanged,
    required this.onNoteChanged,
    required this.onRemove,
    required this.onClose,
  });

  final _BodyZone zone;
  final Injury? injury;
  final TextEditingController noteController;
  final ValueChanged<String> onSeverityChanged;
  final ValueChanged<String> onNoteChanged;
  final VoidCallback onRemove;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final severity = injury?.severity ?? 'mild';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceBase,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: _severityColor(severity)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_zoneLabel(zone.part, zone.side), style: AppTypography.body(size: 15, weight: FontWeight.w700)),
              Row(
                children: [
                  if (injury != null) TextButton(onPressed: onRemove, child: const Text('REMOVE')),
                  GestureDetector(
                    onTap: onClose,
                    child: const Icon(Icons.close, size: 18, color: AppColors.textMuted),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              for (final s in const ['mild', 'moderate', 'avoid']) ...[
                Expanded(
                  child: GestureDetector(
                    onTap: () => onSeverityChanged(s),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: severity == s ? _severityColor(s) : AppColors.surfaceHigh,
                        borderRadius: BorderRadius.circular(AppRadius.field),
                        border: Border.all(color: severity == s ? _severityColor(s) : AppColors.outlineVariant),
                      ),
                      child: Text(
                        _severityLabel(s),
                        textAlign: TextAlign.center,
                        style: AppTypography.body(
                          size: 12,
                          weight: FontWeight.w700,
                          color: severity == s ? AppColors.surfaceLowest : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
                if (s != 'avoid') const SizedBox(width: AppSpacing.sm),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          const SectionLabel('ADD A NOTE'),
          const SizedBox(height: AppSpacing.xs),
          TextField(
            controller: noteController,
            maxLines: 2,
            decoration: const InputDecoration(hintText: 'e.g. Twinges on heavy overhead work'),
            onChanged: onNoteChanged,
          ),
        ],
      ),
    );
  }
}

class _InjuryChip extends StatelessWidget {
  const _InjuryChip({required this.injury, required this.onTap, required this.onRemove});

  final Injury injury;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(AppRadius.chip),
          border: Border.all(color: _severityColor(injury.severity)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${_zoneLabel(injury.part, injury.side)} · ${_severityLabel(injury.severity)}',
              style: AppTypography.body(size: 12, weight: FontWeight.w600),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: onRemove,
              child: const Icon(Icons.close, size: 14, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
