Status: Approved (Retroactive Baseline — documents behavior as implemented, dated 2026-09-10)
Owner: Engineering team (retroactive)
Related: n/a

## Summary

The **008-achievements** module covers two things that live in the same
feature folder (`app/lib/features/achievements/`):

1. **Achievements/badges** — a fixed, server-seeded catalog of 16 achievement
   definitions (`backend/app/db/seed_data.py::ACHIEVEMENTS`) that users
   progress toward and unlock by working out. Progress is computed
   server-side (`backend/app/services/achievements.py::evaluate_achievements`)
   and surfaced through `GET /achievements` and `GET /records`.
2. **Profile tab** — `profile_screen.dart`, the landing screen for the app's
   "Profile" bottom-nav destination. It shows the user's avatar, a
   client-derived Level/XP progress card, four lifetime stat tiles, a row of
   recently-unlocked badges, and a navigation list to Achievements,
   Level & XP (in-sheet), Streak (in-dialog), Challenges, Ask the Coach, and
   Settings. Settings, Challenges, Premium, and Ask the Coach are owned by
   other modules — this spec documents only the links out to them, not their
   internal behavior.

## Background / Problem

Workout logging alone gives no sense of long-term progress or motivation
beyond a single session. This module retroactively documents the existing
gamification layer: a badge/achievement system tied to cumulative training
stats (sessions, streaks, form quality, PRs, volume, estimated 1RM), a simple
XP/Level display derived from workout completion, and a profile hub that
aggregates all of this plus links to the rest of the account-management
surface.

## User Stories

- As a user, I want to see which achievements I've unlocked, which are in
  progress, and which are still locked, so I can see tangible proof of my
  training progress.
- As a user, I want locked "secret" achievements to stay mysterious until I
  unlock them, so there's an element of surprise.
- As a user, I want a single Profile screen that shows my avatar, level, key
  lifetime stats (workouts, volume, time, PRs), and recent badges at a
  glance, so I don't have to dig through multiple screens.
- As a user, I want quick access from Profile to my full achievements list,
  streak, active challenges, the AI coach, and account settings.
- As a user, I want my achievement progress to update automatically as I
  keep training, without needing to do anything manual.

## Acceptance Criteria (EARS format: "WHEN/IF ... THE SYSTEM SHALL ...")

- WHEN a signed-in user's client calls `GET /achievements` for the first
  time (no existing `UserAchievement` rows), THE SYSTEM SHALL compute
  initial progress against every seeded `Achievement` definition and persist
  one `UserAchievement` row per achievement before returning the list
  (`backend/app/api/v1/endpoints/achievements.py:22-32`).
- WHEN a user finishes a workout session (`POST /sessions/{id}/finish`), THE
  SYSTEM SHALL award XP (`50 + 5 * set_count + 20 * pr_count` added to
  `User.xp`) and THEN re-evaluate all achievement progress for that user
  (`backend/app/api/v1/endpoints/workouts.py:148-152`).
- WHEN achievement progress is (re-)evaluated, THE SYSTEM SHALL compute
  each achievement's current value from the stat named by its
  `criteria.type` (`session_count`, `volume_kg_total`, `pr_count`,
  `high_form_sets`, `streak_days`, `sessions_in_best_week`,
  `early_sessions`, `max_est_1rm_kg`, `max_bodyweight_ratio`), clamp
  `progress_value` to `target_value`, and set `unlocked_at` to the current
  timestamp the first time `progress >= target`
  (`backend/app/services/achievements.py:93-124`).
- IF an achievement's `unlocked_at` is already set, THE SYSTEM SHALL NOT
  clear or re-set it on subsequent evaluations, even if the underlying stat
  later drops below target (e.g. a broken streak) — unlocks are permanent
  (`backend/app/services/achievements.py:119-120`).
- WHEN the achievements list is rendered and an achievement has
  `is_secret = true` and is not yet unlocked, THE SYSTEM SHALL display the
  title as `'???'` instead of its real title
  (`app/lib/features/achievements/presentation/achievements_list_screen.dart:30`).
- WHEN the achievements list screen loads, THE SYSTEM SHALL group
  achievements into "Recently unlocked" (top 3 by most-recent
  `unlockedAt`), "In progress" (locked, `progressValue > 0`, sorted by
  descending completion fraction), and "Locked" (locked,
  `progressValue <= 0`), and SHALL let the user filter all three groups by
  category via chips derived from the data (`consistency`, `strength`,
  `volume`, plus any other non-`secret` category present), excluding
  `secret` from the filter chips
  (`app/lib/features/achievements/presentation/achievements_list_screen.dart:16-21,85-159`).
- IF an unlocked achievement was unlocked within the last 7 days, THE
  SYSTEM SHALL count it toward a "N New" badge pill shown next to
  "Recently unlocked" (`achievements_list_screen.dart:105,122-125`).
- WHEN the Profile tab loads, THE SYSTEM SHALL display: an avatar/name
  card with a client-computed Level and XP-into-level progress bar; a
  2x2 stat grid (Workouts, Volume, Time, PRs); a row of up to 5 most
  recently unlocked badges (with a "+N" overflow indicator); and a
  navigation list linking to Achievements, Level & XP, Streak, Challenges,
  Ask the Coach, and Settings (`profile_screen.dart:60-81,253-394`).
- WHEN the Profile tab's Workouts/Volume/Time stats are computed, THE
  SYSTEM SHALL fetch up to the most recent 100 finished workout sessions via
  `WorkoutRepository.listSessions(limit: 100)` and sum client-side — there is
  no server-side aggregate endpoint for this
  (`profile_screen.dart:33-49`).
- WHEN the Profile tab's "PRs" stat tile is computed, THE SYSTEM SHALL use
  the count of `GET /records` results, which is deduplicated to one (the
  latest) record per exercise (`profile_screen.dart:217`;
  `backend/app/services/progress.py:236-246`).
- WHEN the Profile tab's "Streak" row is computed, THE SYSTEM SHALL reuse
  the `streakDays` value already returned by the progress-summary endpoint
  (`compute_streak_days`) rather than recomputing it client-side
  (`profile_screen.dart:326-330`).
- WHEN a user taps "Level & XP" on the Profile tab, THE SYSTEM SHALL open a
  bottom sheet showing Level, XP-into-level/target, a progress bar, and
  total lifetime XP (`profile_screen.dart:396-425`).
- WHEN a user taps "Streak" on the Profile tab, THE SYSTEM SHALL open an
  info dialog stating the current streak or prompting the user to start one
  (`profile_screen.dart:356-369`).
- WHEN a user taps "Achievements" (badge row's "See all" or the nav row) on
  the Profile tab, THE SYSTEM SHALL navigate to the full Achievements list
  screen at `/profile/achievements` (`profile_screen.dart:271-277,342-347`).
- WHEN a user taps "Challenges" or "Settings" on the Profile tab, THE
  SYSTEM SHALL push to `/profile/challenges` or `/profile/settings`
  respectively, owned by the challenges and settings modules
  (`profile_screen.dart:371-389`).
- WHEN a user taps "Ask the Coach" on the Profile tab, THE SYSTEM SHALL
  switch to the Coach tab (`context.go(AppRoutes.coach)`), owned by the
  workout module (`profile_screen.dart:378-383`).
- IF the user's avatar URL is null/empty or fails to load, THE SYSTEM
  SHALL fall back to a generic person icon (`profile_screen.dart:100-131`).
- IF `user.isPro` is true, THE SYSTEM SHALL show a "PRO" pill next to the
  display name on the Profile card (`profile_screen.dart:169`).

## Out of Scope

- Settings, Challenges, Premium/subscription, and Ask-the-Coach screen
  internals — owned by their respective modules; this spec documents only
  the navigation entry points from Profile.
- Any server-side leveling/XP table, level-up notifications, or XP sources
  other than finishing a workout — none exist in the code.
- Push notifications or in-app toasts for newly-unlocked achievements —
  unlocks are only visible the next time the achievements/profile data is
  fetched and re-rendered.
- Editing/authoring achievement definitions from the app — achievements are
  a fixed, server-seeded catalog (see design.md).
- Any admin or content-authoring UI — `backend/app/db/ai_seed.py` is a
  manually-run offline script, not an in-app or runtime feature.

## Non-Functional Requirements

- Achievement/records endpoints require authentication
  (`Depends(get_current_user)`) — no anonymous access
  (`backend/app/api/v1/endpoints/achievements.py:18-20,36-38`).
- Achievement evaluation is idempotent per call (upsert by
  `(user_id, achievement_id)`) and safe to call repeatedly
  (`backend/app/services/achievements.py:100-121`).
- The Flutter providers backing this screen (`userAchievementsProvider`,
  `personalRecordsProvider`, the profile screen's `_workoutStatsProvider`)
  are all `FutureProvider.autoDispose`, so data is re-fetched each time a
  screen depending on them is (re)entered rather than cached indefinitely
  (`app/lib/features/achievements/data/achievements_providers.dart:17-25`).

## Open Questions

- The Profile tab's own on-screen header literally reads "Achievements"
  (`profile_screen.dart:93`, `_Header` widget) even though this is the
  Profile tab's landing screen, not the achievements list screen. Not
  verifiable from code alone whether this is intentional design copy
  (leading with the badges/achievements angle) or a leftover/mislabeled
  string — flagged here rather than assumed either way.
- No leveling design/formula exists on the backend; `domain/leveling.dart`
  is an explicitly client-invented placeholder (see design.md). Whether a
  real leveling system is planned is not answerable from the code.
- "Member since" copy implied by the design comp has no backing field
  (`User` model / `/users/me` expose no `created_at`) and is therefore
  omitted — whether this is a planned backend addition is unknown.
