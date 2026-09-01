import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../app_typography.dart';

/// Temporary stand-in for a screen not yet built out — a scaffold with a
/// title so navigation can be exercised end-to-end before every screen has
/// its real implementation.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.construction, color: AppColors.textMuted, size: 32),
              const SizedBox(height: 12),
              Text(title, style: AppTypography.display(size: 20), textAlign: TextAlign.center),
              if (subtitle != null) ...[
                const SizedBox(height: 8),
                Text(subtitle!, style: AppTypography.body(color: AppColors.textSecondary), textAlign: TextAlign.center),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
