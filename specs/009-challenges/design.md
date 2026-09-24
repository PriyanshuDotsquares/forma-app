Status: Approved (Retroactive Baseline — documents behavior as implemented, dated 2026-09-10)
Owner: Engineering team (retroactive)
Related: n/a

## Approach

Backend mirrors the achievements (008) module's split between a global,
migration-seeded definition table and a per-user progress row
(`Challenge`/`UserChallenge` parallels `Achievement`/`UserAchievement`,
`backend/app/models/challenge.py` vs. `backend/app/models/achievement.py`), and
directly reuses achievements' `compute_streak_days()` for the `streak_days` metric
(`backend/app/services/challenges.py:10,45` importing from
`backend/app/services/achievements.py:14-32`) so the number shown in a streak
challenge always agrees with the Profile tab's streak.

It diverges from achievements in two ways demonstrated by the code:

1. **Opt-in membership.** Achievements auto-track progress for every user the
   first time `GET /achievements` is called for them
   (`backend/app/api/v1/endpoints/achievements.py:24-30`, calling
   `evaluate_achievements`). Challenges require an explicit `join` before a
   `UserChallenge` row exists at all (`challenges.py:76-92`), and `leave` deletes
   the row outright rather than marking it inactive (`challenges.py:95-101`).
2. **Refresh trigger.** Achievement progress is recomputed by
   `evaluate_achievements()`, called from `workouts.py:152` right after a workout
   session finishes (event-driven), plus once lazily for a brand-new user's first
   `GET /achievements`. Challenge progress has no event trigger at all — it is
   recomputed from scratch on *every* `GET /challenges`, `join`, and `leaderboard`
   call (`challenges.py:68`, `challenges.py:81/89`, `challenges.py:112-113`), each
   of which also commits the refreshed values.

The Flutter side follows the same Riverpod `FutureProvider.autoDispose` +
repository pattern used elsewhere in the app
(`app/lib/features/challenges/data/challenges_providers.dart` mirrors the shape of
`app/lib/features/achievements/data/achievements_providers.dart`), with a single
shared provider (`challengesProvider`) feeding both the Challenges list screen and
the Profile tab's "N ACTIVE" badge.

## Architecture / Data Flow

**Trace 1 — Join / Leave**

1. User taps JOIN on a card. `_ChallengeCardState._toggleJoin()`
   (`app/lib/features/challenges/presentation/challenges_list_screen.dart:107-125`)
   sets `_busy = true` and calls `ChallengesRepository.join(challenge.id)`.
2. `ChallengesRepository.join()`
   (`app/lib/features/challenges/data/challenges_repository.dart:21-28`) issues
   `POST /challenges/{id}/join` through `ApiClient.dio`
   (`app/lib/core/network/api_client.dart`), whose request interceptor attaches the
   bearer token from secure storage.
3. `join_challenge` (`backend/app/api/v1/endpoints/challenges.py:41-55`) resolves
   the challenge via `_get_challenge()` (404 if missing/inactive,
   `challenges.py:16-20`), then calls `challenges_service.join(db, current_user,
   challenge)`.
4. `challenges_service.join()` (`challenges.py:76-92`) looks up an existing
   `UserChallenge` for (user, challenge); if present, refreshes and returns it. If
   absent, it computes the current period bounds via `_period_bounds()`, inserts a
   new `UserChallenge(period_start=start, progress_value=0)`, flushes, refreshes
   progress via `_refresh()`, and commits.
5. The endpoint returns the row as `UserChallengeRead`
   (`backend/app/schemas/challenge.py:21-26`).
6. `ChallengesRepository.join()` parses the response into a domain `UserChallenge`
   (`app/lib/features/challenges/domain/challenge.dart:37-61`); `_toggleJoin()`
   then calls `ref.invalidate(challengesProvider)`
   (`challenges_list_screen.dart:116`), which re-runs
   `ChallengesRepository.listChallenges()`
   (`app/lib/features/challenges/data/challenges_providers.dart:13-15`) against
   `GET /challenges`, rebuilding both this screen and — via the same shared
   provider — the Profile tab's "N ACTIVE" badge
   (`app/lib/features/achievements/presentation/profile_screen.dart:331,373-375`).

Leave follows the same shape: `POST /challenges/{id}/leave` →
`challenges_service.leave()` (`challenges.py:95-101`) deletes the `UserChallenge`
row outright (no soft-leave) → `204 No Content` → Flutter invalidates
`challengesProvider`.

**Trace 2 — Progress tracking / Leaderboard**

1. Progress is pull-based, not push-based: it is recomputed on every read, not on
   workout completion. `GET /challenges` (`challenges.py:23-38`) calls
   `challenges_service.list_for_user()` (`challenges.py:57-73`), which loads all
   active `Challenge` rows plus the user's `UserChallenge` rows and, for each
   joined challenge, calls `_refresh()` before committing.
2. `_refresh()` (`challenges.py:49-54`) recomputes `progress_value` via
   `_compute_progress(db, user_id, challenge.metric, start, end)`, where
   `start`/`end` come from `_period_bounds(challenge.period)` computed against
   **current** wall-clock time — not against the `period_start` stored on the row
   at join time (`challenges.py:50`).
3. `_compute_progress()` (`challenges.py:26-46`) branches on `metric`: `volume_kg`
   sums `WorkoutSet.actual_weight_kg * actual_reps` joined to `WorkoutSession`
   filtered by `started_at` in `[start, end)`; `session_count` counts
   `WorkoutSession` rows in that window; `streak_days` calls
   `achievements.compute_streak_days(db, user_id)`
   (`backend/app/services/achievements.py:14-32`), which ignores the window
   entirely.
4. If `progress_value` crosses `target_value` and `completed_at` is still null, it
   is set once (`challenges.py:52-53`) and never cleared afterward.
5. `ChallengesListScreen._buildBody`
   (`app/lib/features/challenges/presentation/challenges_list_screen.dart:62-93`)
   partitions the response into "Your challenges" (joined) and "Available" and
   renders each `_ChallengeCard` with a `LinearProgressIndicator` bound to
   `UserChallenge.progressFraction` (`app/lib/features/challenges/domain/challenge.dart:53`).
6. Tapping LEADERBOARD — rendered only when `challenge.isGroup`
   (`challenges_list_screen.dart:209-213`) — opens `_LeaderboardSheet`, which calls
   `ChallengesRepository.leaderboard(id)` (`challenges_repository.dart:38-45`) →
   `GET /challenges/{id}/leaderboard` → `get_leaderboard`
   (`challenges.py:68-76`) → `challenges_service.leaderboard()`
   (`challenges.py:110-130`), which refreshes every participant's progress, sorts
   all `UserChallenge` rows for the challenge by `progress_value` descending, and
   returns ranked `LeaderboardEntryRead` rows with the requester flagged `is_me`.

## Data / Schema

`backend/app/models/challenge.py`, tables created (with the initial seed rows
bulk-inserted in the same migration) by
`backend/alembic/versions/ad6d3bbe2fa0_add_password_reset_notifications_.py:37-82`
("add password reset, notification prefs, locale, and challenges", dated
2026-09-01):

- **`challenges`** (global definitions): `id` (uuid pk), `key` (unique, indexed),
  `title`, `description`, `metric` (`volume_kg` | `session_count` |
  `streak_days`), `period` (`weekly` | `monthly` | `ongoing`), `target_value`
  (float), `icon`, `is_group` (bool, default true), `is_active` (bool, default
  true).
- **`user_challenges`** (per-user join/progress): `id` (uuid pk), `user_id` (fk →
  `users.id`, indexed), `challenge_id` (fk → `challenges.id`, indexed),
  `joined_at` (server default `now()`), `period_start` (not null, set at join
  time), `progress_value` (float, default 0), `completed_at` (nullable). No unique
  constraint across `(user_id, challenge_id)` — see Risks.

Seed data (`backend/app/db/seed_data.py:265-272`, `CHALLENGES` list, 6 entries):

| key | period | metric | target | is_group |
|---|---|---|---|---|
| `weekly_3_sessions` | weekly | session_count | 3 | true |
| `weekly_5_sessions` | weekly | session_count | 5 | true |
| `monthly_volume_10k` | monthly | volume_kg | 10,000 | true |
| `monthly_volume_25k` | monthly | volume_kg | 25,000 | true |
| `streak_7` | ongoing | streak_days | 7 | false |
| `streak_30` | ongoing | streak_days | 30 | false |

No seeded challenge combines `ongoing` period with `volume_kg`/`session_count`, so
the unwindowed `datetime.min`–`datetime.max` branch of `_period_bounds()` is
exercised only for challenges whose metric (`streak_days`) ignores the window
anyway.

`backend/app/schemas/challenge.py` mirrors these as `ChallengeRead`,
`UserChallengeRead` (nests `ChallengeRead` + join/progress fields), and
`LeaderboardEntryRead`. Flutter domain types
(`app/lib/features/challenges/domain/challenge.dart`) — `Challenge`,
`UserChallenge`, `LeaderboardEntry` — map 1:1 to these via `fromJson`.

## Alternatives Considered

N/A — retroactive baseline.

## Testing Strategy

No automated tests exist for this module. Confirmed: the backend repository has no
`tests/` directory at all, and a repo-wide search of `app/test` (the Flutter test
directory) for any mention of "challenge" returns nothing. This is a gap, not a
deliberate choice documented anywhere in the code.

## Risks / Edge Cases

- **`completed_at` never resets across period rollovers.** `_refresh()` only ever
  sets `completed_at`, never clears it (`challenges.py:52-54`), while
  `progress_value` is recomputed against the *current* week/month on every refresh
  (`challenges.py:50`, ignoring the stored `period_start`). For a weekly/monthly
  challenge, once a user hits the target once, the card's "completed" styling
  (`app/lib/features/challenges/domain/challenge.dart:52`,
  `isCompleted => completedAt != null`) stays on indefinitely even after the
  window rolls over and live progress drops back to 0, while the progress bar
  itself does reflect the new period's live (possibly much lower) value — a
  visible inconsistency between the "completed" badge and the progress bar for
  any recurring challenge.
- **`period_start` is write-once and effectively unused for computation.** It is
  set when a `UserChallenge` row is created (`challenges.py:85-86`) but
  `_period_bounds()` is always called with the current time, never with the
  stored `period_start` — so progress always tracks the live current week/month
  regardless of when the user actually joined.
- **No uniqueness safeguard on `user_challenges(user_id, challenge_id)`** at either
  the DB level (migration `ad6d3bbe2fa0:53-67` defines no unique/composite
  constraint) or the service level (`join()` does a read-then-write with no
  locking, `challenges.py:76-92`) — two concurrent `join` calls for the same
  user+challenge could race past the "existing is None" check and insert two
  rows.
- **Leaderboard has no pagination/limit** and is not gated by `is_group`
  server-side (`challenges.py:110-130`) — a solo streak challenge's "leaderboard"
  of one participant is still fully queryable even though the UI never links to
  it for `is_group == false` challenges.
- **Every read is also a write.** `GET /challenges`, `join`, and `leaderboard` all
  recompute and commit progress for every relevant row on every call
  (`challenges.py:68-73,81/89,113-114`) — there is no caching, so listing
  challenges is not a side-effect-free read.

## Backlog / Known Gaps

- No automated tests (backend or Flutter) for this module — gap.
- `User.notification_prefs.challenge_updates`
  (`backend/app/models/user.py:58,60`) is stored and exposed via the user schema
  but nothing in the backend ever reads it — there is no notification-sending
  service in the repository at all (not specific to challenges; the same is true
  of the other `notification_prefs` keys).
- The `completed_at`-never-clears behavior for weekly/monthly challenges (see
  Risks) is not flagged anywhere in the code as intentional vs. a bug — no comment
  addresses the rollover case.
- No admin/authoring surface for `Challenge` rows — the 6 challenges are fixed at
  the migration that created the tables (`ad6d3bbe2fa0`); there are no create/
  update/deactivate endpoints, so changing the challenge roster requires a new
  migration.
