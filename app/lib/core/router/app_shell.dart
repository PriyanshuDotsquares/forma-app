import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/generated/app_localizations.dart';

/// Persistent bottom-nav scaffold for the five main tabs, used as the
/// `builder` of a `StatefulShellRoute.indexedStack` — each tab keeps its own
/// navigation stack alive when you switch away and back.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: navigationShell.currentIndex,
        onTap: (index) => navigationShell.goBranch(index, initialLocation: index == navigationShell.currentIndex),
        items: [
          BottomNavigationBarItem(icon: const Icon(Icons.calendar_today_outlined), label: l10n.tabToday),
          BottomNavigationBarItem(icon: const Icon(Icons.fitness_center_outlined), label: l10n.tabPlan),
          BottomNavigationBarItem(icon: const Icon(Icons.show_chart), label: l10n.tabProgress),
          BottomNavigationBarItem(icon: const Icon(Icons.chat_bubble_outline), label: l10n.tabCoach),
          BottomNavigationBarItem(icon: const Icon(Icons.person_outline), label: l10n.tabProfile),
        ],
      ),
    );
  }
}
