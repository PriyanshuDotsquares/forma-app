import 'package:flutter/material.dart';

/// Maps the semantic icon-name strings the backend seeds achievements with
/// (literally Material icon names, e.g. "local_fire_department") to the
/// actual [IconData] constant. The design system forbids emoji icons
/// throughout — including for "badge" art — so every achievement, no matter
/// how playful, renders as a Material icon via this lookup.
IconData achievementIcon(String icon) {
  switch (icon) {
    case 'trophy':
      return Icons.emoji_events;
    case 'flag':
      return Icons.flag;
    case 'military_tech':
      return Icons.military_tech;
    case 'link':
      return Icons.link;
    case 'local_fire_department':
      return Icons.local_fire_department;
    case 'wb_sunny':
      return Icons.wb_sunny;
    case 'architecture':
      return Icons.architecture;
    case 'verified':
      return Icons.verified;
    case 'trending_up':
      return Icons.trending_up;
    case 'fitness_center':
      return Icons.fitness_center;
    case 'monitor_weight':
      return Icons.monitor_weight;
    case 'warehouse':
      return Icons.warehouse;
    case 'help_outline':
      return Icons.help_outline;
    case 'event_available':
      return Icons.event_available;
    default:
      return Icons.emoji_events;
  }
}
