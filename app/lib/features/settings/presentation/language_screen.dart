import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/localization/locale_controller.dart';
import '../../auth/presentation/auth_controller.dart';

const _localeLabels = {'en': 'English', 'hi': 'हिन्दी (Hindi)'};

String localeDisplayName(String code) => _localeLabels[code] ?? code;

/// Onboarding, the intro screen, auth, the main tab labels, and Settings
/// itself switch language immediately. Deeper feature screens (workout
/// tracking, camera coaching, progress detail, achievements, premium)
/// aren't translated yet and keep showing English regardless of this
/// choice — a deliberately bounded first pass, not a bug.
class LanguageScreen extends ConsumerStatefulWidget {
  const LanguageScreen({super.key});

  @override
  ConsumerState<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends ConsumerState<LanguageScreen> {
  bool _saving = false;

  Future<void> _select(String code) async {
    final current = ref.read(localeControllerProvider).languageCode;
    if (code == current) return;
    setState(() => _saving = true);
    await ref.read(localeControllerProvider.notifier).setLocale(code);
    try {
      await ref.read(authControllerProvider.notifier).updateProfile(locale: code);
    } catch (_) {
      // Locale already switched locally — a failed account sync isn't worth
      // blocking or reverting the UI language over.
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(localeControllerProvider).languageCode;

    return Scaffold(
      appBar: AppBar(title: const Text('Language')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xxl),
          children: [
            Text(
              "Switches the intro, sign-in, onboarding, tab bar, and Settings. Other screens stay in English for now.",
              style: AppTypography.body(size: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.lg),
            for (final locale in supportedLocales)
              RadioListTile<String>(
                value: locale.languageCode,
                groupValue: current,
                onChanged: _saving ? null : (v) => v == null ? null : _select(v),
                title: Text(localeDisplayName(locale.languageCode)),
                contentPadding: EdgeInsets.zero,
              ),
            if (_saving) const Padding(padding: EdgeInsets.only(top: AppSpacing.sm), child: LinearProgressIndicator()),
          ],
        ),
      ),
    );
  }
}
