import 'package:flutter/material.dart';

import '../../../../core/design_system/design_system.dart';

/// Shared "No plan yet" empty state — shown on the plan overview and day
/// editor screens when the user has no active program (generation either
/// hasn't happened yet or failed and needs a retry).
class NoActiveProgramView extends StatelessWidget {
  const NoActiveProgramView({super.key, required this.onGenerate, this.loading = false});

  final VoidCallback onGenerate;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: FormaEmptyState(
          icon: Icons.auto_awesome_outlined,
          eyebrow: 'NO PLAN YET',
          title: 'No plan yet.',
          message: "Answer a few questions and we'll build your first week.",
          primaryLabel: loading ? 'BUILDING…' : 'BUILD MY PLAN',
          onPrimary: loading ? null : onGenerate,
        ),
      ),
    );
  }
}
