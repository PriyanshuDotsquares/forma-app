import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../onboarding_controller.dart';
import '../widgets/onboarding_step_scaffold.dart';

class Step3Numbers extends ConsumerStatefulWidget {
  const Step3Numbers({super.key, required this.onBack, required this.onContinue});

  final VoidCallback onBack;
  final VoidCallback onContinue;

  @override
  ConsumerState<Step3Numbers> createState() => _Step3NumbersState();
}

class _Step3NumbersState extends ConsumerState<Step3Numbers> {
  late final TextEditingController _heightController;
  late final TextEditingController _weightController;
  DateTime? _dob;
  String? _gender;
  late String _units;

  @override
  void initState() {
    super.initState();
    final answers = ref.read(onboardingControllerProvider);
    _dob = answers.dob;
    _gender = answers.gender;
    _units = answers.units;
    _heightController = TextEditingController(text: _formatHeight(answers.heightCm, _units));
    _weightController = TextEditingController(text: _formatWeight(answers.weightKg, _units));
  }

  @override
  void dispose() {
    _heightController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  String _formatHeight(double? cm, String units) {
    if (cm == null) return '';
    final value = units == 'imperial' ? cm / 2.54 : cm;
    return value.toStringAsFixed(0);
  }

  String _formatWeight(double? kg, String units) {
    if (kg == null) return '';
    final value = units == 'imperial' ? kg * 2.20462 : kg;
    return value.toStringAsFixed(0);
  }

  void _switchUnits(String units) {
    if (units == _units) return;
    setState(() {
      final heightCm = _parsedHeightCm();
      final weightKg = _parsedWeightKg();
      _units = units;
      _heightController.text = _formatHeight(heightCm, units);
      _weightController.text = _formatWeight(weightKg, units);
    });
  }

  double? _parsedHeightCm() {
    final raw = double.tryParse(_heightController.text.trim());
    if (raw == null) return null;
    return _units == 'imperial' ? raw * 2.54 : raw;
  }

  double? _parsedWeightKg() {
    final raw = double.tryParse(_weightController.text.trim());
    if (raw == null) return null;
    return _units == 'imperial' ? raw / 2.20462 : raw;
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 25, now.month, now.day),
      firstDate: DateTime(now.year - 100),
      lastDate: now,
      initialDatePickerMode: DatePickerMode.year,
      helpText: 'DATE OF BIRTH',
    );
    if (picked != null) setState(() => _dob = picked);
  }

  void _saveAndContinue({bool skip = false}) {
    final notifier = ref.read(onboardingControllerProvider.notifier);
    notifier.setUnits(_units);
    if (skip) {
      notifier.setDob(null);
      notifier.setGender(null);
      notifier.setHeightCm(null);
      notifier.setWeightKg(null);
    } else {
      notifier.setDob(_dob);
      notifier.setGender(_gender);
      notifier.setHeightCm(_parsedHeightCm());
      notifier.setWeightKg(_parsedWeightKg());
    }
    widget.onContinue();
  }

  @override
  Widget build(BuildContext context) {
    final dobLabel = _dob == null
        ? 'Select date'
        : '${_dob!.year}-${_dob!.month.toString().padLeft(2, '0')}-${_dob!.day.toString().padLeft(2, '0')}';

    final l10n = AppLocalizations.of(context)!;
    return OnboardingStepScaffold(
      stepNumber: 3,
      totalSteps: kOnboardingTotalSteps,
      title: l10n.step3Title,
      subtitle: 'Used to estimate your starting weights and calories. Every field is optional.',
      onBack: widget.onBack,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: _UnitToggle(units: _units, onChanged: _switchUnits),
          ),
          const SizedBox(height: AppSpacing.lg),
          const SectionLabel('DATE OF BIRTH'),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _pickDob,
              icon: const Icon(Icons.calendar_today, size: 16),
              label: Align(alignment: Alignment.centerLeft, child: Text(dobLabel)),
              style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const SectionLabel('GENDER'),
          const SizedBox(height: AppSpacing.sm),
          _GenderControl(value: _gender, onChanged: (g) => setState(() => _gender = g)),
          const SizedBox(height: AppSpacing.lg),
          const SectionLabel('HEIGHT'),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _heightController,
            keyboardType: const TextInputType.numberWithOptions(decimal: false),
            decoration: InputDecoration(hintText: '0', suffixText: _units == 'imperial' ? 'in' : 'cm'),
          ),
          const SizedBox(height: AppSpacing.lg),
          const SectionLabel('WEIGHT'),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _weightController,
            keyboardType: const TextInputType.numberWithOptions(decimal: false),
            decoration: InputDecoration(hintText: '0', suffixText: _units == 'imperial' ? 'lb' : 'kg'),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            "Skip anything you'd rather not share — we'll just skip calorie estimates.",
            style: AppTypography.body(size: 12, color: AppColors.textMuted),
          ),
        ],
      ),
      footer: Column(
        children: [
          SizedBox(width: double.infinity, child: FilledButton(onPressed: () => _saveAndContinue(), child: Text(l10n.onboardingContinue))),
          TextButton(onPressed: () => _saveAndContinue(skip: true), child: Text(l10n.onboardingSkipStep)),
        ],
      ),
    );
  }
}

class _UnitToggle extends StatelessWidget {
  const _UnitToggle({required this.units, required this.onChanged});

  final String units;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: AppColors.surfaceHigh, borderRadius: BorderRadius.circular(AppRadius.button)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _UnitTab(label: 'KG / CM', selected: units == 'metric', onTap: () => onChanged('metric')),
          _UnitTab(label: 'LB / FT', selected: units == 'imperial', onTap: () => onChanged('imperial')),
        ],
      ),
    );
  }
}

class _UnitTab extends StatelessWidget {
  const _UnitTab({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.button - 4),
        ),
        child: Text(
          label,
          style: AppTypography.body(size: 11, weight: FontWeight.w700, color: selected ? AppColors.accentBlueDark : AppColors.textSecondary),
        ),
      ),
    );
  }
}

class _GenderControl extends StatelessWidget {
  const _GenderControl({required this.value, required this.onChanged});

  final String? value;
  final ValueChanged<String?> onChanged;

  static const _options = [('male', 'Male'), ('female', 'Female'), ('prefer_not', 'Prefer not')];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final option in _options) ...[
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(value == option.$1 ? null : option.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                decoration: BoxDecoration(
                  color: value == option.$1 ? AppColors.accentBlue : AppColors.surfaceBase,
                  borderRadius: BorderRadius.circular(AppRadius.field),
                  border: Border.all(color: value == option.$1 ? AppColors.accentBlue : AppColors.outlineVariant),
                ),
                child: Text(
                  option.$2,
                  textAlign: TextAlign.center,
                  style: AppTypography.body(
                    size: 13,
                    weight: FontWeight.w600,
                    color: value == option.$1 ? AppColors.accentBlueDark : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
          if (option != _options.last) const SizedBox(width: AppSpacing.sm),
        ],
      ],
    );
  }
}
