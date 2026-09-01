import 'package:flutter/material.dart';

import '../../../../core/design_system/design_system.dart';

/// The flat, 1px-bordered card shell reused across every progress screen —
/// stat rows, chart cards, the hub's row-links. No elevation/shadow per the
/// "Cast Iron & Chalk Dust" anti-pattern list.
class ProgressCard extends StatelessWidget {
  const ProgressCard({super.key, required this.child, this.padding = const EdgeInsets.all(AppSpacing.md), this.onTap});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surfaceBase,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: child,
    );
    if (onTap == null) return content;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Material(color: Colors.transparent, child: InkWell(onTap: onTap, child: content)),
    );
  }
}
