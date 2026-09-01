import 'package:flutter/material.dart';

import '../../../../core/design_system/design_system.dart';

/// Total number of steps shown in the "STEP N OF 9" progress header.
const kOnboardingTotalSteps = 9;

/// Shared chrome for steps 1-8 of the onboarding quiz: a "STEP N OF 9"
/// progress bar with an optional back arrow, a scrollable body, and a
/// pinned footer (usually a Continue button, sometimes with a skip link
/// underneath it).
class OnboardingStepScaffold extends StatelessWidget {
  const OnboardingStepScaffold({
    super.key,
    required this.stepNumber,
    required this.totalSteps,
    required this.title,
    this.subtitle,
    this.onBack,
    required this.child,
    this.footer,
    this.headerTrailing,
    this.scrollable = true,
  });

  final int stepNumber;
  final int totalSteps;
  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final Widget child;
  final Widget? footer;
  final Widget? headerTrailing;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final body = Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTypography.display(size: 28)),
          if (subtitle != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(subtitle!, style: AppTypography.body(size: 15, color: AppColors.textSecondary)),
          ],
          const SizedBox(height: AppSpacing.lg),
          child,
        ],
      ),
    );

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.sm, AppSpacing.lg, AppSpacing.sm),
              child: Row(
                children: [
                  SizedBox(
                    width: 40,
                    child: onBack != null
                        ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: onBack)
                        : null,
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          'STEP $stepNumber OF $totalSteps',
                          style: AppTypography.body(size: 11, weight: FontWeight.w700, color: AppColors.textMuted).copyWith(letterSpacing: 1.2),
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(value: stepNumber / totalSteps, minHeight: 4),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 40, child: headerTrailing),
                ],
              ),
            ),
            Expanded(child: scrollable ? SingleChildScrollView(child: body) : body),
            if (footer != null) Padding(padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg), child: footer!),
          ],
        ),
      ),
    );
  }
}
