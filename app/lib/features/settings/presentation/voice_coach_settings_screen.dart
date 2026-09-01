import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../../core/design_system/design_system.dart';
import '../../auth/domain/user.dart';
import '../../auth/presentation/auth_controller.dart';
import 'widgets/settings_row.dart';

class _VerbosityOption {
  const _VerbosityOption(this.value, this.title, this.subtitle);
  final String value;
  final String title;
  final String subtitle;
}

const _verbosityOptions = [
  _VerbosityOption('off', 'Off', 'Visual cues only, on screen'),
  _VerbosityOption('minimal', 'Minimal', 'Only safety-critical calls'),
  _VerbosityOption('standard', 'Standard', 'One correction per set, plus a summary'),
  _VerbosityOption('detailed', 'Detailed', 'Every issue we spot, as it happens'),
];

class _VoiceOption {
  const _VoiceOption(this.id, this.label);
  final String id;
  final String label;
}

// Cosmetic only: `flutter_tts` exposes whatever voices happen to be
// installed on the device, and that catalog varies wildly by platform —
// there's no real cross-platform "voice" to select. This is a small static
// list of plausible display names mapped to arbitrary ids; it's persisted
// as a preference string but doesn't drive an actual TTS engine voice.
const _voiceOptions = [
  _VoiceOption('alex_en_gb', 'Alex (British)'),
  _VoiceOption('sam_en_us', 'Sam (American)'),
  _VoiceOption('priya_en_in', 'Priya (Indian)'),
];

String _voiceLabel(String id) {
  for (final v in _voiceOptions) {
    if (v.id == id) return v.label;
  }
  return _voiceOptions.first.label;
}

String _sampleCueFor(String verbosity) {
  switch (verbosity) {
    case 'off':
      return "Voice coaching is off — you'll only see visual cues.";
    case 'minimal':
      return 'Careful — knees caving in.';
    case 'detailed':
      return 'Elbows flaring, brace your core, and drive through your heels on the way up.';
    case 'standard':
    default:
      return 'Nice depth. Keep your chest up on the next rep.';
  }
}

/// The full voice-coach preference editor, reached from Settings > "Voice
/// coach". Every control updates local state immediately for a snappy feel;
/// most controls persist on every change (`updateProfile` is a cheap PATCH),
/// but the volume slider only persists on `onChangeEnd` so dragging doesn't
/// fire a request per pixel.
class VoiceCoachSettingsScreen extends ConsumerStatefulWidget {
  const VoiceCoachSettingsScreen({super.key});

  @override
  ConsumerState<VoiceCoachSettingsScreen> createState() => _VoiceCoachSettingsScreenState();
}

class _VoiceCoachSettingsScreenState extends ConsumerState<VoiceCoachSettingsScreen> {
  late VoiceCoachSettings _settings =
      ref.read(authControllerProvider).valueOrNull?.voiceCoach ?? const VoiceCoachSettings();
  final _tts = FlutterTts();

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  Future<void> _persist(VoiceCoachSettings next) async {
    setState(() => _settings = next);
    try {
      await ref.read(authControllerProvider.notifier).updateProfile(voiceCoach: next.toJson());
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not save. Try again.')));
      }
    }
  }

  Future<void> _playSample() async {
    try {
      await _tts.setVolume(_settings.volume.clamp(0.0, 1.0));
      await _tts.speak(_sampleCueFor(_settings.verbosity));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Could not play a preview on this device.')));
      }
    }
  }

  Future<void> _pickVoice() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionLabel('Voice'),
            const SizedBox(height: AppSpacing.xs),
            for (final v in _voiceOptions)
              RadioListTile<String>(
                value: v.id,
                groupValue: _settings.voice,
                onChanged: (val) => Navigator.of(context).pop(val),
                title: Text(v.label),
                contentPadding: EdgeInsets.zero,
              ),
          ],
        ),
      ),
    );
    if (picked != null && picked != _settings.voice) {
      await _persist(_settings.copyWith(voice: picked));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Voice Coach')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xxl),
          children: [
            _ToggleCard(
              icon: Icons.record_voice_over_outlined,
              title: 'Voice Coaching',
              subtitle: 'Spoken corrections while you train',
              value: _settings.enabled,
              onChanged: (v) => _persist(_settings.copyWith(enabled: v)),
            ),
            const SizedBox(height: AppSpacing.lg),
            const SectionLabel('How much'),
            const SizedBox(height: AppSpacing.sm),
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(color: AppColors.outlineVariant, borderRadius: BorderRadius.circular(AppRadius.card)),
              child: Column(
                children: [
                  for (var i = 0; i < _verbosityOptions.length; i++) ...[
                    if (i != 0) const SizedBox(height: 1),
                    _VerbosityCard(
                      option: _verbosityOptions[i],
                      selected: _settings.verbosity == _verbosityOptions[i].value,
                      onTap: () => _persist(_settings.copyWith(verbosity: _verbosityOptions[i].value)),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            SettingsSection(
              title: 'Voice',
              rows: [
                SettingsRow(label: 'Voice', valueText: _voiceLabel(_settings.voice), onTap: _pickVoice),
                SettingsRow(
                  label: 'Count reps out loud',
                  subtitle: 'Say the number on each rep',
                  showChevron: false,
                  trailing: Switch(
                    value: _settings.countReps,
                    onChanged: (v) => _persist(_settings.copyWith(countReps: v)),
                  ),
                ),
                SettingsRow(
                  label: 'Encouragement',
                  subtitle: 'A word when a set goes well',
                  showChevron: false,
                  trailing: Switch(
                    value: _settings.encouragement,
                    onChanged: (v) => _persist(_settings.copyWith(encouragement: v)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            const SectionLabel('Audio mix'),
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.surfaceBase,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: AppColors.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Coach Volume', style: AppTypography.body(size: 15, weight: FontWeight.w600)),
                      Text(
                        '${(_settings.volume * 100).round()}%',
                        style: AppTypography.mono(size: 13, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                  Slider(
                    value: _settings.volume.clamp(0.0, 1.0),
                    onChanged: (v) => setState(() => _settings = _settings.copyWith(volume: v)),
                    onChangeEnd: (v) => _persist(_settings.copyWith(volume: v)),
                  ),
                  const Divider(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Lower music for cues', style: AppTypography.body(size: 15, weight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text(
                              'Ducks background audio while the coach talks',
                              style: AppTypography.body(size: 12, color: AppColors.textMuted),
                            ),
                          ],
                        ),
                      ),
                      Switch(value: _settings.duckMusic, onChanged: (v) => _persist(_settings.copyWith(duckMusic: v))),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            _ExamplePreviewCard(phrase: _sampleCueFor(_settings.verbosity), onPlay: _playSample),
          ],
        ),
      ),
    );
  }
}

class _ToggleCard extends StatelessWidget {
  const _ToggleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

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
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: AppColors.accentBlue.withValues(alpha: 0.1), shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Icon(icon, size: 22, color: AppColors.accentBlue),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.display(size: 18)),
                const SizedBox(height: 2),
                Text(subtitle, style: AppTypography.body(size: 13, color: AppColors.textSecondary)),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _VerbosityCard extends StatelessWidget {
  const _VerbosityCard({required this.option, required this.selected, required this.onTap});

  final _VerbosityOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Rows sit flush inside a shared grouping card (see the caller), so —
    // unlike a standalone selectable card — only the selected row gets a
    // border; the outer container's radius and hairline gaps do the rest.
    final fillColor = selected ? AppColors.accentBlue.withValues(alpha: 0.12) : AppColors.surfaceBase;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: fillColor,
            border: selected ? Border.all(color: AppColors.accentBlue, width: 2) : null,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(option.title, style: AppTypography.body(size: 15, weight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(option.subtitle, style: AppTypography.body(size: 13, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                color: selected ? AppColors.accentBlue : AppColors.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The "hear an example" card: the sample cue on top, a divider, then a
/// labeled play control — mirrors the Figma layout more closely than a
/// single-row banner would (the label call-out is the point of the card).
class _ExamplePreviewCard extends StatelessWidget {
  const _ExamplePreviewCard({required this.phrase, required this.onPlay});

  final String phrase;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.accentBlue.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.format_quote, size: 18, color: AppColors.textPrimary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  '"$phrase"',
                  style: AppTypography.body(size: 16, weight: FontWeight.w500).copyWith(fontStyle: FontStyle.italic),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'HEAR AN EXAMPLE',
                style: AppTypography.body(
                  size: 12,
                  weight: FontWeight.w700,
                  color: AppColors.accentBlue,
                ).copyWith(letterSpacing: 0.96),
              ),
              IconButton.filled(
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.accentBlue.withValues(alpha: 0.1),
                  foregroundColor: AppColors.accentBlue,
                ),
                onPressed: onPlay,
                icon: const Icon(Icons.play_arrow, size: 16),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
