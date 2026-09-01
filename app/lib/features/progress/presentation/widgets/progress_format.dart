import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/network/api_exception.dart';

/// Push/pull/upper/lower muscle buckets used by the volume "BALANCE RATIOS"
/// card. The backend only gives per-muscle set counts (`VolumeByMuscle`), not
/// a ready-made push/pull split, so this mapping is our own judgment call —
/// `core` is deliberately left unclassified rather than guessed into a side.
const kPushMuscles = {'chest', 'shoulders', 'triceps'};
const kPullMuscles = {'back', 'biceps'};
const kUpperMuscles = {...kPushMuscles, ...kPullMuscles};
const kLowerMuscles = {'quads', 'hamstrings', 'glutes', 'calves'};

/// "98.2k kg" / "1.24M kg" style compaction for large volume numbers, plain
/// thousands-separated otherwise.
String formatVolumeKg(double kg) {
  if (kg >= 1000000) return '${(kg / 1000000).toStringAsFixed(2)}M';
  if (kg >= 1000) return '${(kg / 1000).toStringAsFixed(1)}k';
  return NumberFormat('#,##0').format(kg);
}

/// Seconds -> "6h 42m" (or just "42m" under an hour).
String formatDurationHm(int seconds) {
  final totalMinutes = seconds ~/ 60;
  final h = totalMinutes ~/ 60;
  final m = totalMinutes % 60;
  if (h <= 0) return '${m}m';
  return '${h}h ${m.toString().padLeft(2, '0')}m';
}

/// Coarse relative-time label: "just now" / "3h ago" / "yesterday" / "5d
/// ago" / "3w ago" / falls back to "Jan 4" beyond that.
String formatRelativeDate(DateTime? dt) {
  if (dt == null) return 'never';
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays == 1) return 'yesterday';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  final weeks = (diff.inDays / 7).floor();
  if (weeks < 5) return '${weeks}w ago';
  return DateFormat('MMM d').format(dt);
}

/// Red -> amber -> green across a 0-100 recovery percentage. Not a
/// physiological measurement — see the explainer dialog on the recovery
/// screen for what this actually estimates.
Color recoveryColor(double pct) {
  final clamped = pct.clamp(0.0, 100.0);
  if (clamped < 50) return Color.lerp(AppColors.accentRed, AppColors.accentAmber, clamped / 50)!;
  return Color.lerp(AppColors.accentAmber, AppColors.accentGreen, (clamped - 50) / 50)!;
}

String titleCaseMuscle(String m) {
  if (m.isEmpty) return m;
  final cleaned = m.replaceAll('_', ' ');
  return cleaned.split(' ').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
}

const Map<String, String> kPeriodShortLabels = {'week': 'W', 'month': 'M', '3month': '3M', 'year': 'Y', 'all': 'ALL'};

const Map<String, String> kPeriodNounLabels = {
  'week': 'THIS WEEK',
  'month': 'THIS MONTH',
  '3month': 'LAST 3 MONTHS',
  'year': 'THIS YEAR',
  'all': 'ALL TIME',
};

const Map<String, String> kPeriodDistributionLabels = {
  'week': 'WEEKLY DISTRIBUTION',
  'month': 'MONTHLY DISTRIBUTION',
  '3month': '3-MONTH DISTRIBUTION',
  'year': 'YEARLY DISTRIBUTION',
  'all': 'ALL-TIME DISTRIBUTION',
};

String friendlyErrorMessage(Object error) =>
    error is ApiException ? error.message : 'Something went wrong. Please try again.';
