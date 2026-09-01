import 'package:flutter/material.dart';

import '../../../../core/design_system/design_system.dart';

/// Small circular icon badge for one achievement — amber-tinted when
/// unlocked, dimmed/muted otherwise. Used in the profile hub's "BADGES" row
/// and the achievements list's cards/grid. Material icon only — the design
/// bans emoji even for badge art.
class AchievementBadge extends StatelessWidget {
  const AchievementBadge({super.key, required this.icon, this.unlocked = true, this.size = 44});

  final IconData icon;
  final bool unlocked;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: unlocked ? AppColors.accentAmber.withValues(alpha: 0.16) : AppColors.surfaceHigh,
        border: Border.all(color: unlocked ? AppColors.accentAmber.withValues(alpha: 0.5) : AppColors.outlineVariant),
      ),
      child: Icon(icon, size: size * 0.46, color: unlocked ? AppColors.accentAmber : AppColors.textMuted),
    );
  }
}
