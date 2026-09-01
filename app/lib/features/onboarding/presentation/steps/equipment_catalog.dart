import 'package:flutter/material.dart';

/// One checkable card in the "What can you train with?" step. [id] is the
/// granular picker token (what the UI checks/unchecks and remembers across
/// visits); [canonicalToken] is what actually gets sent to the backend in
/// the `equipment` list, since the seeded exercise library only understands
/// a small fixed vocabulary: barbell, dumbbell, cable, machine, kettlebell,
/// bodyweight.
class EquipmentItem {
  const EquipmentItem({
    required this.id,
    required this.label,
    required this.canonicalToken,
    required this.icon,
    this.subtitle,
  });

  final String id;
  final String label;
  final String? subtitle;
  final String canonicalToken;
  final IconData icon;
}

class EquipmentSection {
  const EquipmentSection(this.title, this.items);

  final String title;
  final List<EquipmentItem> items;
}

/// Static catalog backing the equipment picker + the gym-location presets
/// that pre-check it.
class EquipmentCatalog {
  EquipmentCatalog._();

  static const sections = <EquipmentSection>[
    EquipmentSection('BARBELL & PLATES', [
      EquipmentItem(id: 'barbell', label: 'Barbell', canonicalToken: 'barbell', icon: Icons.fitness_center),
      EquipmentItem(id: 'plates', label: 'Plates', canonicalToken: 'barbell', icon: Icons.album),
      EquipmentItem(id: 'blocks', label: 'Blocks', subtitle: 'Partial-range pulls', canonicalToken: 'barbell', icon: Icons.widgets),
    ]),
    EquipmentSection('DUMBBELLS & KETTLEBELLS', [
      EquipmentItem(id: 'dumbbell', label: 'Dumbbells', subtitle: '2.5 - 40 kg', canonicalToken: 'dumbbell', icon: Icons.sports_gymnastics),
      EquipmentItem(id: 'kettlebell', label: 'Kettlebells', canonicalToken: 'kettlebell', icon: Icons.sports_kabaddi),
    ]),
    EquipmentSection('MACHINES & CABLES', [
      EquipmentItem(id: 'cable', label: 'Cables', canonicalToken: 'cable', icon: Icons.cable),
      EquipmentItem(id: 'leg_press', label: 'Leg Press', canonicalToken: 'machine', icon: Icons.chair_alt),
      EquipmentItem(id: 'lat_pulldown', label: 'Lat Pulldown', canonicalToken: 'machine', icon: Icons.expand_less),
      EquipmentItem(id: 'chest_press', label: 'Chest Press', canonicalToken: 'machine', icon: Icons.open_in_full),
      EquipmentItem(id: 'seated_row', label: 'Seated Row', canonicalToken: 'machine', icon: Icons.swap_horiz),
      EquipmentItem(id: 'smith_machine', label: 'Smith Machine', canonicalToken: 'machine', icon: Icons.view_column),
      EquipmentItem(id: 'leg_curl', label: 'Leg Curl', canonicalToken: 'machine', icon: Icons.accessibility_new),
    ]),
    EquipmentSection('BARS & BENCHES', [
      EquipmentItem(id: 'bench', label: 'Bench', canonicalToken: 'barbell', icon: Icons.event_seat),
      EquipmentItem(id: 'pull_up_bar', label: 'Pull-up Bar', canonicalToken: 'machine', icon: Icons.horizontal_rule),
      EquipmentItem(id: 'dip_station', label: 'Dip Station', canonicalToken: 'machine', icon: Icons.height),
    ]),
  ];

  static List<EquipmentItem> get all => sections.expand((s) => s.items).toList();

  static String canonicalTokenFor(String id) {
    for (final item in all) {
      if (item.id == id) return item.canonicalToken;
    }
    return 'bodyweight';
  }

  /// Starting equipment preset for a gym-location choice, keyed by item id
  /// (not the canonical token) so the picker's checkboxes come pre-filled.
  static Set<String> presetFor(String gymLocation) {
    switch (gymLocation) {
      case 'commercial_gym':
        // Everything except Blocks — a niche accessory most commercial gyms
        // don't rack, left for the user to opt into.
        return all.map((e) => e.id).where((id) => id != 'blocks').toSet();
      case 'home_gym':
        return const {'barbell', 'plates', 'dumbbell', 'kettlebell', 'bench', 'pull_up_bar'};
      case 'bodyweight':
        return const {};
      case 'mixed':
      default:
        return const {};
    }
  }
}
