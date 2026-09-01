import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/router/app_router.dart';
import '../../../l10n/generated/app_localizations.dart';

class _IntroPage {
  const _IntroPage(this.icon, this.badgeBig, this.badgeSmall, this.title, this.body);
  final IconData icon;
  final String badgeBig;
  final String badgeSmall;
  final String title;
  final String body;
}

List<_IntroPage> _pagesFor(AppLocalizations l10n) => [
  _IntroPage(Icons.accessibility_new, '7', 'REPS', l10n.introTitle1, l10n.introBody1),
  _IntroPage(Icons.graphic_eq, '●', 'LIVE', l10n.introTitle2, l10n.introBody2),
  _IntroPage(Icons.show_chart, '+12%', 'THIS WEEK', l10n.introTitle3, l10n.introBody3),
];

class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key});

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final pages = _pagesFor(l10n);
    return Scaffold(
      backgroundColor: AppColors.surfaceLowest,
      body: Column(
        children: [
          Expanded(
            flex: 6,
            child: Stack(
              fit: StackFit.expand,
              children: [
                PageView.builder(
                  controller: _controller,
                  itemCount: pages.length,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (context, i) => _Hero(page: pages[i]),
                ),
                SafeArea(
                  child: Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      child: TextButton(
                        onPressed: () => context.go(AppRoutes.auth),
                        child: Text(l10n.skip),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 5,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: IndexedStack(
                        index: _page,
                        children: [
                          for (final page in pages)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(page.title, style: AppTypography.display(size: 26)),
                                const SizedBox(height: AppSpacing.sm),
                                Text(page.body, style: AppTypography.body(size: 14, color: AppColors.textSecondary)),
                              ],
                            ),
                        ],
                      ),
                    ),
                    Row(
                      children: List.generate(
                        pages.length,
                        (i) => AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.only(right: 4),
                          width: i == _page ? 20 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: i == _page ? AppColors.accentBlue : AppColors.surfaceHighest,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => context.go(AppRoutes.auth),
                        child: Text(l10n.getStarted),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Center(
                      child: TextButton(
                        onPressed: () => context.go(AppRoutes.auth),
                        child: Text(l10n.alreadyHaveAccount),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-bleed "hero" for one intro page. The design shows a real photo (an
/// athlete mid-lift with a pose-tracking skeleton overlay) — there's no
/// photography asset in this project, so this substitutes a dark gradient
/// plate with a large silhouette icon standing in for it.
class _Hero extends StatelessWidget {
  const _Hero({required this.page});

  final _IntroPage page;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.surfaceBase, AppColors.surfaceLowest],
        ),
      ),
      child: Stack(
        children: [
          Center(
            child: Icon(page.icon, size: 180, color: AppColors.accentBlue.withValues(alpha: 0.16)),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xxl, right: AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(page.badgeBig, style: AppTypography.display(size: 32)),
                    Text(
                      page.badgeSmall,
                      style: AppTypography.body(size: 11, weight: FontWeight.w700, color: AppColors.textMuted).copyWith(letterSpacing: 1.2),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
