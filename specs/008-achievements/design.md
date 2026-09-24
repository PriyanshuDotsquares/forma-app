Status: Approved (Retroactive Baseline — documents behavior as implemented, dated 2026-09-10)
Owner: Engineering team (retroactive)
Related: n/a

## Approach

Achievements are a **fixed, server-seeded catalog** (16 rows, inserted by the
fitness-domain migration `backend/alembic/versions/561d62621de3_fitness_domain_rewrite_drop_keepsakes_.py`
from `backend/app/db/seed_data.py::ACHIEVEMENTS`). Per-user progress is a
separate table (`user_achievements`) that is recomputed by a single
service function, `evaluate_achievements`, which re-derives every stat from
first principles (workout sessions/sets, personal records) each time it
runs — there is no incremental/event-sourced tracking. This keeps the
unlock logic simple and self-healing but means it only runs at two explicit
trigger points (see Data Flow) rather than continuously.

The Profile tab is a thin aggregation screen: it does not own any new
backend state of its own beyond what Achievements/Records/Progress/
Challenges already expose. It composes read-only providers from four
feature folders (achievements, workout, progress, challenges) into one
scrollable hub, plus a client-only "Level" derived value.

## Architecture / Data Flow

**Achievement unlock computation (server-side, on-demand at two triggers
— NOT computed on every list fetch for existing users):**

1. `POST /sessions/{id}/finish` (`backend/app/api/v1/endpoints/workouts.py:128-154`)
   finalizes the session, adds XP to `User.xp`
   (`50 + 5*set_count + 20*pr_count`), commits, then calls
   `evaluate_achievements(db, user_id)` — this is the primary trigger.
2. `GET /achievements` (`backend/app/api/v1/endpoints/achievements.py:17-32`)
   first queries existing `UserAchievement` rows for the user. **Only if
   there are zero rows** (brand-new user) does it call
   `evaluate_achievements` itself, to seed the initial 16 progress rows,
   then re-queries. For a returning user with existing rows, this endpoint
   is a **plain read** — it does not recompute progress. Because every
   stat type is driven purely by workout/PR activity, and `finish_session`
   already re-evaluates after every such activity, the persisted rows stay
   consistent in practice — but architecturally, `GET /achievements` alone
   will not surface progress for stats that could change outside a
   workout-finish event (none exist today).
3. Inside `evaluate_achievements` (`backend/app/services/achievements.py:93-124`):
   a. `_compute_stats` (lines 35-90) computes 9 named stats from scratch via
      SQL aggregates over `WorkoutSession`/`WorkoutSet`/`PersonalRecord`:
      `session_count`, `volume_kg_total`, `pr_count`, `high_form_sets`
      (sets with `form_score >= 85`), `streak_days` (via
      `compute_streak_days`), `sessions_in_best_week` (max sessions in any
      ISO week), `early_sessions` (sessions with `started_at.hour < 7`),
      `max_est_1rm_kg`, `max_bodyweight_ratio` (`max_est_1rm_kg / User.weight_kg`,
      `0.0` if `weight_kg` is unset).
   b. For every `Achievement` definition, it reads `criteria.type` and
      `criteria.target`, looks up `stats.get(criteria_type, 0.0)` (an
      unrecognized `criteria.type` silently yields `0.0` forever — see
      Risks), upserts a `UserAchievement` row, clamps
      `progress_value = min(progress, target)`, and sets `unlocked_at` to
      "now" the first time `progress >= target` **and only if
      `unlocked_at` is still null** — unlocks are never revoked even if the
      live stat later regresses (e.g. a broken streak).
4. `GET /records` (`backend/app/api/v1/endpoints/achievements.py:35-40`)
   calls `current_records` (`backend/app/services/progress.py:236-246`),
   which returns one row per exercise — the most recent `PersonalRecord`
   per `exercise_id` — not the full history of every PR event.

**Client fetch/render (Achievements list + Profile):**

5. `achievementsRepositoryProvider` (`data/achievements_providers.dart:10-12`)
   builds one `AchievementsRepository` over the shared `apiClientProvider`.
6. `userAchievementsProvider` (`FutureProvider.autoDispose`) calls
   `AchievementsRepository.listAchievements()` → `GET /achievements`,
   deserializing into `UserAchievement` (wrapping `Achievement`)
   (`data/achievements_repository.dart:12-19`, `domain/achievement.dart`).
   This single provider is shared by both `AchievementsListScreen` and
   `ProfileScreen`'s badge row/nav counts, so both stay in sync off one
   fetch (per the provider's doc comment).
7. `personalRecordsProvider` calls `listRecords()` → `GET /records`
   (`data/achievements_repository.dart:21-28`) for the Profile "PRs" stat
   tile.
8. `AchievementsListScreen` (`presentation/achievements_list_screen.dart`)
   watches `userAchievementsProvider`, then client-side: derives category
   chips (`_deriveCategories`, excludes `secret`), splits the (optionally
   category-filtered) list into Recently-unlocked/top-3
   (`_RecentCard`), In-progress (`_InProgressRow`, sorted by descending
   `progressFraction`), and Locked (`_LockedCard`, 2-column grid); masks
   locked-secret titles to `'???'` (`_displayTitle`); maps each
   achievement's `icon` string to a `Material` `IconData` via
   `achievementIcon()` (`domain/achievement_icons.dart`) — every badge
   renders as a Material icon, never emoji, per the design system's
   no-emoji rule.
9. `ProfileScreen` (`presentation/profile_screen.dart`) assembles, top to
   bottom, from `authControllerProvider`'s current `User` plus four
   independent providers:
   - `_Header` + `_Avatar`: static title text + `CachedNetworkImage` avatar
     with a person-icon fallback.
   - `_ProfileCard`: avatar, display name (falls back to email local-part),
     a `PRO` pill if `user.isPro`, and `LevelProgress.fromXp(user.xp)`
     rendered as "LEVEL n" + "xpIntoLevel / xpForNextLevel XP" + a progress
     bar.
   - `_StatsGrid`: watches a private `_workoutStatsProvider`
     (constructs `WorkoutRepository` directly over `apiClientProvider`,
     fetches up to 100 recent sessions via `listSessions(limit: 100)`,
     sums finished sessions/volume/duration client-side — there is no
     `/workouts/summary` aggregate endpoint) for Workouts/Volume/Time, and
     `personalRecordsProvider.length` for PRs.
   - `_BadgesRow`: watches `userAchievementsProvider`, takes the 5 most
     recently unlocked (by `unlockedAt` desc), shows a "+N" overflow
     circle, and a "See all" link to `/profile/achievements`.
   - `_NavList`: watches `userAchievementsProvider` (unlocked/total
     count), `progressSummaryProvider('month')` (for `streakDays` — reused
     from the **progress** module rather than recomputed, per the code
     comment; period argument is irrelevant since the backend's streak
     isn't period-filtered), and `challengesProvider` (count of
     `c.joined` — from the **challenges** module) to render six
     `ProfileNavRow`s: Achievements (push `/profile/achievements`),
     Level & XP (opens an in-page bottom sheet, no navigation), Streak
     (opens an in-page info dialog, no navigation), Challenges (push
     `/profile/challenges`, owned by the **challenges** module), Ask the
     Coach (`context.go(AppRoutes.coach)`, switches shell branch to the
     workout module's Coach tab), Settings (push `/profile/settings`,
     owned by the **settings** module). Premium (`/profile/premium`,
     also owned by the **settings** module's route group) is **not**
     linked from this nav list in the current code — it's reached instead
     from a "pro teaser" widget inside the progress module
     (`app/lib/features/progress/presentation/widgets/pro_teaser.dart:63`).

## Data / Schema

Backend (`backend/app/models/achievement.py`):
- `achievements` (global catalog, seeded, not user-scoped): `id`, `key`
  (unique), `category` (`consistency | strength | volume | secret`),
  `title`, `description`, `icon` (a Material icon name string), `criteria`
  (JSONB — `{"type": <stat name>, "target": <number>}`), `is_secret`
  (bool, default false).
- `user_achievements` (one row per `(user, achievement)`, upserted by
  `evaluate_achievements`): `id`, `user_id` (FK), `achievement_id` (FK),
  `progress_value` (float, clamped to target), `target_value` (float,
  mirrors `criteria.target` at last evaluation), `unlocked_at`
  (nullable timestamp — null means locked, set-once means unlocked).

Seeded catalog (`backend/app/db/seed_data.py:228-245`), 16 definitions:
- **consistency** (7): `first_rep` (session_count≥1), `half_century`
  (session_count≥50), `century` (session_count≥100), `iron_week`
  (sessions_in_best_week≥4), `two_week_streak` (streak_days≥14),
  `thirty_day_streak` (streak_days≥30), `early_bird` (early_sessions≥1).
- **strength** (6): `deep_squatter` (high_form_sets≥20), `form_master`
  (high_form_sets≥50), `pr_hunter` (pr_count≥5), `pr_machine`
  (pr_count≥20), `century_club` (max_est_1rm_kg≥100),
  `double_bodyweight` (max_bodyweight_ratio≥2).
- **volume** (2): `volume_lord` (volume_kg_total≥100000),
  `quarter_million` (volume_kg_total≥250000).
- **secret** (1): `secret_1` (streak_days≥60, `is_secret=true`).

A companion offline script, `backend/app/db/ai_seed.py` (manually run, not
invoked at request time or app startup — per `backend/app/core/config.py:42`
comment), can use an LLM to generate *additional* achievements constrained
to the same fixed `CriteriaType` enum (`ai_seed.py:108-118`) and
`AchievementCategory` enum, for future catalog growth. It is a
content-authoring tool, not a runtime feature of this module.

API schemas (`backend/app/schemas/achievement.py`): `AchievementRead`,
`UserAchievementRead` (nests `AchievementRead`), `RecordRead` — all
`from_attributes` Pydantic models mirroring the ORM models 1:1, no
computed/derived fields added server-side (e.g. no `progress_fraction` —
the client computes that itself, see below).

Client domain (`app/lib/features/achievements/domain/achievement.dart`):
`Achievement`, `UserAchievement` (adds computed `isUnlocked` =
`unlockedAt != null` and `progressFraction` = `progressValue/targetValue`
clamped to `[0,1]`, guarding `targetValue <= 0`), `PersonalRecord`.

**Leveling (`domain/leveling.dart`) — verified, not assumed:** there is
**no backend leveling endpoint, table, or documented formula**. `User.xp`
(`backend/app/models/user.py:81`) is just a running integer incremented
only in `finish_session`. `LevelProgress` is an explicitly
**client-invented** display formula (per its own doc comment): flat curve,
100 XP per level, `level = xp/100 + 1` (integer division), `xpIntoLevel =
xp % 100`, `xpForNextLevel` always `100`. It exists purely to render the
Profile card's "LEVEL n" + XP bar and the "Level & XP" bottom sheet; no
other screen currently renders XP/level, and the code comment explicitly
instructs future screens to reuse this formula rather than invent a second
one.

## Alternatives Considered

N/A — retroactive baseline.

## Testing Strategy

No automated tests — gap. No test files reference `achievements`,
`profile_screen`, `leveling`, or related symbols anywhere under
`app/lib` or `backend/app`; `backend`'s only `test_*.py` files found are
vendored third-party package tests under `backend/.venv/`, not
project tests. There is no `backend/tests/` or Flutter `test/` coverage
for this module.

## Risks / Edge Cases

- **Secret achievement never reveals anything new on unlock.** The one
  seeded secret achievement (`secret_1`) has its `title` and `description`
  literally stored as `"???"` / `"Keep training to find out."` in
  `seed_data.py:244` — there is no hidden "real" title. The client's
  masking logic (`achievements_list_screen.dart:30`,
  `_displayTitle`) only swaps to `'???'` while locked and shows
  `achievement.title` once unlocked, implying an intent to reveal a real
  name — but for the only secret achievement that exists, unlocking it
  changes nothing visible. Grounded in code; whether this is intentional
  ("secret" just means hidden progress, not a hidden name) is unclear.
- **Unrecognized `criteria.type` silently stalls at 0 forever.**
  `evaluate_achievements` does `stats.get(criteria_type, 0.0)`
  (`backend/app/services/achievements.py:110`) — any achievement (e.g. one
  authored later via `ai_seed.py` or manually) whose `criteria.type` isn't
  one of the 9 keys `_compute_stats` produces can never unlock. Not an
  issue for the current 16 seeded achievements (all use recognized types),
  but a structural risk documented in `ai_seed.py`'s own prompt/comments.
- **"Early Bird" checks UTC hour, not local time.** `early_sessions` counts
  sessions where `started.hour < 7` (`backend/app/services/achievements.py:70`)
  against a timezone-aware `started_at` — `.hour` reads the stored (UTC)
  hour, not the user's local wall-clock hour. A user training at 8am in a
  UTC+2 timezone (6am UTC) would trigger it; a user training at 6am in a
  UTC-2 timezone (8am UTC) would not. Whether workouts are stored/created
  with true UTC timestamps end-to-end wasn't traced beyond this file, but
  the comparison itself is timezone-naive relative to the user.
- **`double_bodyweight` is unreachable for users without a set body
  weight.** `max_bodyweight_ratio` is `0.0` whenever `User.weight_kg` is
  falsy (`backend/app/services/achievements.py:78`), so that achievement
  can never progress until the user sets a body weight elsewhere in the
  app (outside this module).
- **PR-count asymmetry between the Profile stat tile and the `pr_hunter`/
  `pr_machine` achievements.** The Profile "PRs" tile uses
  `personalRecordsProvider.length`, which is `GET /records`' deduplicated
  count (one row per exercise, latest only). The `pr_count` stat backing
  the achievements counts every `PersonalRecord` row ever created
  (`backend/app/services/achievements.py:48`). A user who has broken a PR
  on the same lift multiple times will see a lower "PRs" tile number than
  their actual progress toward `pr_hunter`/`pr_machine`.
- **`_workoutStatsProvider` caps at 100 sessions.** Profile's
  Workouts/Volume/Time tiles only sum the most recent 100 finished
  sessions (server-side `limit` cap, per the code comment in
  `profile_screen.dart:33-39`); a user with more than 100 logged sessions
  will see understated lifetime totals on this screen specifically (the
  achievement stats, computed via SQL aggregates with no such limit, are
  unaffected).
- **No client-side notification of newly-unlocked achievements.** Because
  `userAchievementsProvider` is `autoDispose` and only re-fetched on
  screen (re)entry, a user who unlocks an achievement mid-session has no
  toast/animation — they discover it next time the Achievements list or
  Profile screen is opened.

## Backlog / Known Gaps

- `profile_screen.dart:93` — the Profile tab's own header text reads
  "Achievements", not "Profile"; see Open Questions in requirements.md.
- `profile_screen.dart:172-176` — a "Member since {month year}" line from
  the design comp is explicitly omitted with a code comment: `User` /
  `/users/me` expose no `created_at`, so the backend would need a
  `created_at` field on `UserRead` for this to be implemented.
- No automated tests exist for this module (see Testing Strategy) — gap.
- No push/toast notification on achievement unlock (see Risks) — gap,
  not a bug.
- Secret-achievement "reveal on unlock" appears functionally inert for the
  only seeded secret achievement (see Risks) — possibly a content gap
  (needs a real hidden title/description) rather than a code bug.
