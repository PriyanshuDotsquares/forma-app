import 'package:flutter/material.dart';

import '../../../../core/design_system/design_system.dart';
import 'plate_math.dart';

class SetEntryResult {
  const SetEntryResult({required this.weightKg, required this.reps, required this.setType});
  final double? weightKg;
  final int? reps;
  final String setType; // normal | warmup | drop
}

/// Opens the numeric-entry bottom sheet for one set: a big weight/reps
/// display, quick-adjust chips, a plate-math breakdown (for barbell
/// exercises), a NORMAL/WARM-UP/DROP toggle, and a custom numeric keypad.
/// Returns `null` if dismissed without confirming.
Future<SetEntryResult?> showSetEntrySheet(
  BuildContext context, {
  required double? initialWeightKg,
  required int? initialReps,
  required String initialSetType,
  required bool showPlateMath,
}) {
  return showModalBottomSheet<SetEntryResult>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SetEntrySheet(
      initialWeightKg: initialWeightKg,
      initialReps: initialReps,
      initialSetType: initialSetType,
      showPlateMath: showPlateMath,
    ),
  );
}

enum _ActiveField { weight, reps }

class SetEntrySheet extends StatefulWidget {
  const SetEntrySheet({
    super.key,
    required this.initialWeightKg,
    required this.initialReps,
    required this.initialSetType,
    required this.showPlateMath,
  });

  final double? initialWeightKg;
  final int? initialReps;
  final String initialSetType;
  final bool showPlateMath;

  @override
  State<SetEntrySheet> createState() => _SetEntrySheetState();
}

class _SetEntrySheetState extends State<SetEntrySheet> {
  late String _weightText = widget.initialWeightKg == null || widget.initialWeightKg == 0 ? '' : _trim(widget.initialWeightKg!);
  late String _repsText = (widget.initialReps == null || widget.initialReps == 0) ? '' : widget.initialReps.toString();
  late String _setType = widget.initialSetType;
  _ActiveField _active = _ActiveField.weight;

  double? get _weight => double.tryParse(_weightText);
  int? get _reps => int.tryParse(_repsText);

  static String _trim(double v) => v == v.truncateToDouble() ? v.toStringAsFixed(0) : v.toString();

  void _adjustWeight(double delta) {
    final next = ((_weight ?? 0) + delta).clamp(0, 500).toDouble();
    setState(() {
      _weightText = next == 0 ? '' : _trim(next);
      _active = _ActiveField.weight;
    });
  }

  void _keyTap(String key) {
    setState(() {
      final isWeight = _active == _ActiveField.weight;
      final buffer = isWeight ? _weightText : _repsText;
      String next;
      if (key == 'back') {
        next = buffer.isEmpty ? buffer : buffer.substring(0, buffer.length - 1);
      } else if (key == '.') {
        if (!isWeight || buffer.contains('.')) return;
        next = '$buffer.';
      } else {
        next = '$buffer$key';
      }
      if (isWeight) {
        _weightText = next;
      } else {
        _repsText = next;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final weight = _weight;
    final plate = widget.showPlateMath && weight != null && weight > 0 ? computePlateBreakdown(weight) : null;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(color: AppColors.outline, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: _BigNumberField(
                      label: 'KG',
                      value: _weightText.isEmpty ? '0' : _weightText,
                      selected: _active == _ActiveField.weight,
                      onTap: () => setState(() => _active = _ActiveField.weight),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: _BigNumberField(
                      label: 'REPS',
                      value: _repsText.isEmpty ? '0' : _repsText,
                      selected: _active == _ActiveField.reps,
                      onTap: () => setState(() => _active = _ActiveField.reps),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  _QuickChip(label: '-5', onTap: () => _adjustWeight(-5)),
                  _QuickChip(label: '-2.5', onTap: () => _adjustWeight(-2.5)),
                  _QuickChip(label: '+2.5', onTap: () => _adjustWeight(2.5)),
                  _QuickChip(label: '+5', onTap: () => _adjustWeight(5)),
                ],
              ),
              if (plate != null && !plate.isEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(plate.label, style: AppTypography.mono(size: 12, color: AppColors.textSecondary)),
              ],
              const SizedBox(height: AppSpacing.lg),
              _SetTypeToggle(value: _setType, onChanged: (v) => setState(() => _setType = v)),
              const SizedBox(height: AppSpacing.lg),
              _Keypad(onKeyTap: _keyTap),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(
                    context,
                  ).pop(SetEntryResult(weightKg: _weight, reps: _reps, setType: _setType)),
                  child: const Text('DONE'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BigNumberField extends StatelessWidget {
  const _BigNumberField({required this.label, required this.value, required this.selected, required this.onTap});

  final String label;
  final String value;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(AppRadius.field),
          border: Border.all(color: selected ? AppColors.accentBlue : AppColors.outlineVariant, width: selected ? 1.5 : 1),
        ),
        child: Column(
          children: [
            Text(value, style: AppTypography.mono(size: 34, weight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(label, style: AppTypography.body(size: 11, weight: FontWeight.w700, color: AppColors.textMuted).copyWith(letterSpacing: 1.0)),
          ],
        ),
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  const _QuickChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm)),
      child: Text(label, style: AppTypography.mono(size: 13, weight: FontWeight.w600)),
    );
  }
}

class _SetTypeToggle extends StatelessWidget {
  const _SetTypeToggle({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  static const _options = [('normal', 'NORMAL'), ('warmup', 'WARM-UP'), ('drop', 'DROP')];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: AppColors.surfaceHigh, borderRadius: BorderRadius.circular(AppRadius.button)),
      child: Row(
        children: _options
            .map(
              (option) => Expanded(
                child: GestureDetector(
                  onTap: () => onChanged(option.$1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: value == option.$1 ? AppColors.accentBlue : Colors.transparent,
                      borderRadius: BorderRadius.circular(AppRadius.button - 4),
                    ),
                    child: Text(
                      option.$2,
                      textAlign: TextAlign.center,
                      style: AppTypography.body(
                        size: 12,
                        weight: FontWeight.w700,
                        color: value == option.$1 ? AppColors.accentBlueDark : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({required this.onKeyTap});
  final ValueChanged<String> onKeyTap;

  static const _keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '.', '0', 'back'];

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: AppSpacing.sm,
      crossAxisSpacing: AppSpacing.sm,
      childAspectRatio: 2.2,
      children: _keys.map((key) {
        return Material(
          color: AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(AppRadius.field),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.field),
            onTap: () => onKeyTap(key),
            child: Center(
              child: key == 'back'
                  ? const Icon(Icons.backspace_outlined, size: 18, color: AppColors.textPrimary)
                  : Text(key, style: AppTypography.mono(size: 18, weight: FontWeight.w600)),
            ),
          ),
        );
      }).toList(),
    );
  }
}
