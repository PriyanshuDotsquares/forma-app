import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/domain/user.dart';
import 'steps/equipment_catalog.dart';

/// Sentinel used by [OnboardingAnswers.copyWith] so optional fields (dob,
/// gender, height, weight) can be explicitly cleared — e.g. skipping step 3
/// — rather than merely "not passed this time".
const _unset = Object();

/// Everything collected across the 9-step quiz, held in memory until the
/// final "Build my plan" submit. Mirrors the fields on [User] /
/// `OnboardingUpdate`, plus a couple of UI-only bits (the granular equipment
/// picker selection) that get collapsed down to the backend vocabulary only
/// at submit time.
class OnboardingAnswers {
  const OnboardingAnswers({
    this.goal,
    this.experienceLevel,
    this.units = 'metric',
    this.dob,
    this.gender,
    this.heightCm,
    this.weightKg,
    this.gymLocation = 'commercial_gym',
    this.equipmentItems = const <String>{},
    this.daysPerWeek,
    this.sessionMinutes,
    this.splitPreference = 'auto',
    this.injuries = const <Injury>[],
  });

  final String? goal; // build_muscle | get_stronger | lose_fat | general_health | athletic_performance | move_better
  final String? experienceLevel; // new | machines | free_weights | programs_own
  final String units; // metric | imperial
  final DateTime? dob;
  final String? gender; // male | female | prefer_not
  final double? heightCm;
  final double? weightKg;
  final String gymLocation; // commercial_gym | home_gym | bodyweight | mixed
  final Set<String> equipmentItems; // raw picker ids, e.g. "leg_press"
  final int? daysPerWeek;
  final int? sessionMinutes;
  final String splitPreference; // auto | upper_lower | push_pull_legs | full_body | body_part
  final List<Injury> injuries;

  /// The picker selection collapsed to the fixed vocabulary the exercise
  /// library understands. Falls back to bodyweight-only training if nothing
  /// is checked, so the plan generator always has something to work with.
  List<String> get canonicalEquipment {
    final tokens = <String>{for (final id in equipmentItems) EquipmentCatalog.canonicalTokenFor(id)};
    if (tokens.isEmpty) tokens.add('bodyweight');
    final list = tokens.toList()..sort();
    return list;
  }

  int? get ageYears {
    final d = dob;
    if (d == null) return null;
    final now = DateTime.now();
    var age = now.year - d.year;
    if (now.month < d.month || (now.month == d.month && now.day < d.day)) age--;
    return age;
  }

  OnboardingAnswers copyWith({
    Object? goal = _unset,
    Object? experienceLevel = _unset,
    String? units,
    Object? dob = _unset,
    Object? gender = _unset,
    Object? heightCm = _unset,
    Object? weightKg = _unset,
    String? gymLocation,
    Set<String>? equipmentItems,
    Object? daysPerWeek = _unset,
    Object? sessionMinutes = _unset,
    String? splitPreference,
    List<Injury>? injuries,
  }) {
    return OnboardingAnswers(
      goal: identical(goal, _unset) ? this.goal : goal as String?,
      experienceLevel: identical(experienceLevel, _unset) ? this.experienceLevel : experienceLevel as String?,
      units: units ?? this.units,
      dob: identical(dob, _unset) ? this.dob : dob as DateTime?,
      gender: identical(gender, _unset) ? this.gender : gender as String?,
      heightCm: identical(heightCm, _unset) ? this.heightCm : heightCm as double?,
      weightKg: identical(weightKg, _unset) ? this.weightKg : weightKg as double?,
      gymLocation: gymLocation ?? this.gymLocation,
      equipmentItems: equipmentItems ?? this.equipmentItems,
      daysPerWeek: identical(daysPerWeek, _unset) ? this.daysPerWeek : daysPerWeek as int?,
      sessionMinutes: identical(sessionMinutes, _unset) ? this.sessionMinutes : sessionMinutes as int?,
      splitPreference: splitPreference ?? this.splitPreference,
      injuries: injuries ?? this.injuries,
    );
  }

  /// PATCH `/onboarding` payload — snake_case, matches `OnboardingUpdate`.
  Map<String, dynamic> toOnboardingPayload() {
    return {
      'dob': dob?.toIso8601String().split('T').first,
      'gender': gender,
      'height_cm': heightCm,
      'weight_kg': weightKg,
      'goal': goal,
      'experience_level': experienceLevel,
      'days_per_week': daysPerWeek,
      'session_minutes': sessionMinutes,
      'split_preference': splitPreference,
      'gym_location': gymLocation,
      'equipment': canonicalEquipment,
      'injuries': injuries.map((i) => i.toJson()).toList(),
      'onboarding_completed': true,
    };
  }
}

/// Human-readable label for a split preference, used on the review step and
/// the final "Chose your split" checklist line.
String splitPreferenceLabel(String splitPreference, {int? daysPerWeek}) {
  switch (splitPreference) {
    case 'upper_lower':
      return 'Upper/Lower';
    case 'push_pull_legs':
      return 'Push/Pull/Legs';
    case 'full_body':
      return 'Full body';
    case 'body_part':
      return 'Body part split';
    case 'auto':
    default:
      final days = daysPerWeek ?? 3;
      if (days >= 6) return 'Push/Pull/Legs';
      if (days == 5) return 'Body part split';
      if (days == 4) return 'Upper/Lower';
      return 'Full body';
  }
}

String experienceLevelLabel(String? level) {
  switch (level) {
    case 'new':
      return 'New to lifting';
    case 'machines':
      return 'I know the machines';
    case 'free_weights':
      return 'Free weights, confidently';
    case 'programs_own':
      return 'I program my own training';
    default:
      return 'Not set';
  }
}

String goalLabel(String? goal) {
  switch (goal) {
    case 'build_muscle':
      return 'Build muscle';
    case 'get_stronger':
      return 'Get stronger';
    case 'lose_fat':
      return 'Lose fat';
    case 'general_health':
      return 'General health';
    case 'athletic_performance':
      return 'Athletic performance';
    case 'move_better':
      return 'Move better';
    default:
      return 'Not set';
  }
}

String gymLocationLabel(String? location) {
  switch (location) {
    case 'commercial_gym':
      return 'Commercial gym';
    case 'home_gym':
      return 'Home gym';
    case 'bodyweight':
      return 'Bodyweight only';
    case 'mixed':
      return 'A mix';
    default:
      return 'Not set';
  }
}

/// Holds the in-progress quiz answers for the lifetime of the onboarding
/// flow. Nothing here is persisted remotely until the final submit on step
/// 9 — see `OnboardingFlowScreen` / `BuildingPlanStep`.
class OnboardingController extends Notifier<OnboardingAnswers> {
  @override
  OnboardingAnswers build() {
    // `OnboardingAnswers()` defaults `gymLocation` to 'commercial_gym' so it
    // reads as pre-selected on step 4a without the user tapping it — but
    // that means the equipment preset (normally applied as a side effect of
    // `setGymLocation`) never fires if they just hit Continue on the
    // default. Seed it here so the two stay in sync from the start.
    return OnboardingAnswers(equipmentItems: EquipmentCatalog.presetFor('commercial_gym'));
  }

  void setGoal(String goal) => state = state.copyWith(goal: goal);

  void setExperienceLevel(String level) => state = state.copyWith(experienceLevel: level);

  void setUnits(String units) => state = state.copyWith(units: units);

  void setDob(DateTime? dob) => state = state.copyWith(dob: dob);

  void setGender(String? gender) => state = state.copyWith(gender: gender);

  void setHeightCm(double? heightCm) => state = state.copyWith(heightCm: heightCm);

  void setWeightKg(double? weightKg) => state = state.copyWith(weightKg: weightKg);

  /// Choosing a gym location pre-checks a sensible equipment preset.
  void setGymLocation(String location) {
    state = state.copyWith(gymLocation: location, equipmentItems: EquipmentCatalog.presetFor(location));
  }

  void toggleEquipmentItem(String id) {
    final next = {...state.equipmentItems};
    if (!next.add(id)) next.remove(id);
    state = state.copyWith(equipmentItems: next);
  }

  void setSectionSelected(EquipmentSection section, bool selected) {
    final next = {...state.equipmentItems};
    for (final item in section.items) {
      if (selected) {
        next.add(item.id);
      } else {
        next.remove(item.id);
      }
    }
    state = state.copyWith(equipmentItems: next);
  }

  void deselectAllEquipment() => state = state.copyWith(equipmentItems: const {});

  void setDaysPerWeek(int days) {
    var next = state.copyWith(daysPerWeek: days);
    if (!_splitFitsDays(next.splitPreference, days)) {
      next = next.copyWith(splitPreference: 'auto');
    }
    state = next;
  }

  void setSessionMinutes(int minutes) => state = state.copyWith(sessionMinutes: minutes);

  void setSplitPreference(String split) => state = state.copyWith(splitPreference: split);

  void setInjury(Injury injury) {
    final next = [
      for (final existing in state.injuries)
        if (!(existing.part == injury.part && existing.side == injury.side)) existing,
      injury,
    ];
    state = state.copyWith(injuries: next);
  }

  void removeInjury(String part, String side) {
    final next = [
      for (final existing in state.injuries)
        if (!(existing.part == part && existing.side == side)) existing,
    ];
    state = state.copyWith(injuries: next);
  }

  void clearInjuries() => state = state.copyWith(injuries: const []);
}

bool _splitFitsDays(String split, int days) {
  switch (split) {
    case 'push_pull_legs':
      return days == 3 || days == 6;
    case 'body_part':
      return days >= 5;
    default:
      return true;
  }
}

final onboardingControllerProvider = NotifierProvider<OnboardingController, OnboardingAnswers>(OnboardingController.new);
