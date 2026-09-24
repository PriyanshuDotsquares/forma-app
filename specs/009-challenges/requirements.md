Status: Approved (Retroactive Baseline — documents behavior as implemented, dated 2026-09-10)
Owner: Engineering team (retroactive)
Related: n/a

## Summary

The challenges module lets a user browse a fixed set of global weekly, monthly, and
ongoing (streak) challenges, opt in ("join") or opt out ("leave") of each one
individually, see live progress toward each joined challenge's target, and — for
group challenges — view a leaderboard ranking every participant by progress. It is
surfaced as its own screen (`ChallengesListScreen`) reached from a "Challenges" row
on the Profile tab, which is owned by the achievements module (008) and shows a
live "N ACTIVE" count sourced from the same data provider
(`app/lib/features/achievements/presentation/profile_screen.dart:331,373-375`).

## Background / Problem

Verified in code: the `Challenge` model's own docstring states it is
"Global challenge definitions, seeded via migration — same shape as `Achievement`,
but time-boxed (weekly/monthly) rather than lifetime" (`backend/app/models/challenge.py:16-17`),
and the service directly imports and reuses
`compute_streak_days` from the achievements service
(`backend/app/services/challenges.py:10,45`, defined at
`backend/app/services/achievements.py:14-32`) so that a challenge's streak number
agrees with the Profile tab's streak. This confirms the module was modeled on the
achievements (008) global-definition + per-user-progress-row pattern, while adding
two concepts achievements does not have: an explicit opt-in `join`/`leave` step
(achievements auto-track progress for every user, no join required — see
`backend/app/api/v1/endpoints/achievements.py:16-31`) and a time-boxed `period`
(weekly/monthly/ongoing) that achievements lacks entirely.

The Alembic migration that creates the `challenges`/`user_challenges` tables
(`backend/alembic/versions/ad6d3bbe2fa0_add_password_reset_notifications_.py`) is
titled "add password reset, notification prefs, locale, and challenges" and dated
2026-09-01 — i.e. challenges landed in the same later batch of work as password
reset and locale/i18n, consistent with it having been added after most of the app's
core features as a "coming soon" stub that was subsequently implemented.

## User Stories

- As a user, I want to see all active challenges (joined and available) with my
  progress on each, so I know what I'm working toward.
- As a user, I want to join a challenge so my workout activity starts counting
  toward it.
- As a user, I want to leave a challenge I'm no longer interested in.
- As a user, I want to see a progress bar and numeric progress
  (e.g. "2/5 sessions") for each challenge I've joined.
- As a user, I want to view a leaderboard for group challenges to see how my
  progress compares to other participants.
- As a user, I want to see, at a glance from my Profile tab, how many challenges
  I currently have active.

## Acceptance Criteria (EARS format: "WHEN/IF ... THE SYSTEM SHALL ...")

- WHEN a user opens the Challenges screen, THE SYSTEM SHALL fetch every active
  challenge (`Challenge.is_active == true`) via `GET /challenges` together with the
  user's join/progress status on each (`backend/app/api/v1/endpoints/challenges.py:23-38`,
  `backend/app/services/challenges.py:57-73`).
- WHEN a challenge is not joined, THE SYSTEM SHALL list it under "Available" with a
  JOIN button and no progress bar (`app/lib/features/challenges/presentation/challenges_list_screen.dart:74-90,183,216-226`).
- WHEN a challenge is joined, THE SYSTEM SHALL list it under "Your challenges" with
  a progress bar (`progress_value`/`target_value`) and a LEAVE button
  (`challenges_list_screen.dart:80-84,183-205,216-221`).
- WHEN a user taps JOIN, THE SYSTEM SHALL call `POST /challenges/{id}/join`, and if
  no `UserChallenge` row exists yet for that user+challenge, create one with
  `period_start` set from the current period bounds and `progress_value` refreshed
  before returning (`backend/app/services/challenges.py:76-92`).
- IF a user is already joined and JOIN is called again, THE SYSTEM SHALL refresh and
  return the existing `UserChallenge` row rather than creating a new one, in the
  normal (non-concurrent) request path (`challenges.py:80-83`).
- WHEN a user taps LEAVE on a joined challenge, THE SYSTEM SHALL call
  `POST /challenges/{id}/leave` and delete the `UserChallenge` row entirely,
  discarding all recorded progress (`challenges.py:95-101`).
- WHEN a challenge's `metric` is `volume_kg`, THE SYSTEM SHALL compute progress as
  the sum of `actual_weight_kg * actual_reps` across the user's `WorkoutSet` rows
  whose session `started_at` falls within the current period window
  (`challenges.py:27-34`).
- WHEN a challenge's `metric` is `session_count`, THE SYSTEM SHALL compute progress
  as the count of the user's `WorkoutSession` rows started within the current
  period window (`challenges.py:35-41`).
- WHEN a challenge's `metric` is `streak_days`, THE SYSTEM SHALL compute progress
  using the same unwindowed `compute_streak_days()` helper used by the achievements
  module, ignoring the period window (`challenges.py:42-45`;
  `backend/app/services/achievements.py:14-32`).
- WHEN a challenge's `period` is `weekly`, THE SYSTEM SHALL bound the current window
  to Monday 00:00 UTC through the following Monday 00:00 UTC, computed against the
  current time on every read (`challenges.py:15-17`).
- WHEN a challenge's `period` is `monthly`, THE SYSTEM SHALL bound the current
  window to the 1st of the current calendar month 00:00 UTC through the 1st of the
  next month, computed against the current time on every read (`challenges.py:18-21`).
- WHEN a challenge's `period` is `ongoing`, THE SYSTEM SHALL apply no time window
  (`datetime.min`–`datetime.max`) (`challenges.py:22-23`).
- WHEN a joined challenge's `progress_value` first reaches or exceeds its
  `target_value`, THE SYSTEM SHALL set `completed_at` to the current time, once
  (`challenges.py:52-53`).
- IF `completed_at` has already been set, THE SYSTEM SHALL NOT clear or re-evaluate
  it on later refreshes, even if `progress_value` subsequently drops back below
  `target_value` (e.g. after a weekly/monthly window rolls over) — no code path in
  `_refresh()` clears `completed_at` (`challenges.py:52-54`).
- WHEN a user requests `GET /challenges/{id}/leaderboard`, THE SYSTEM SHALL refresh
  every participant's progress, then return all `UserChallenge` rows for that
  challenge ranked by `progress_value` descending, with the requester's own row
  flagged `is_me` (`challenges.py:110-130`).
- WHEN a challenge has `is_group == true`, THE SYSTEM SHALL show a LEADERBOARD
  button on its card; WHEN `is_group == false`, THE SYSTEM SHALL NOT show it. The
  backend leaderboard endpoint itself does not check `is_group`
  (`challenges_list_screen.dart:209-213`; `challenges.py:68-76`).
- IF a requested challenge does not exist or `is_active` is false, THE SYSTEM SHALL
  return HTTP 404 (`challenges.py:16-20`).
- WHEN the Profile tab is displayed, THE SYSTEM SHALL show a "Challenges" row with
  an "N ACTIVE" badge counting the user's joined challenges, sourced from the same
  `challengesProvider` used by this screen (cross-reference only — owned by module
  008: `app/lib/features/achievements/presentation/profile_screen.dart:331,373-375`).

## Out of Scope

- Push/email notifications for challenge progress or completion. A
  `challenge_updates` notification preference exists on the user record
  (`backend/app/models/user.py:58,60`), but no notification-sending service exists
  anywhere in the backend to act on any notification preference.
- Server-side enforcement of `is_group` on the leaderboard endpoint (currently
  UI-only gating).
- Pagination or a result limit on leaderboard entries.
- Any admin/authoring UI or API for creating, editing, or deactivating challenges —
  the 6 seeded challenges are fixed at the migration that created the tables; there
  are no CRUD endpoints for `Challenge`.
- Automated tests — none exist for this module (see design.md Testing Strategy).

## Non-Functional Requirements

- All four endpoints require an authenticated user via `get_current_user`
  (`challenges.py:23-27,41-46,58-63,69-73`) — no anonymous access.
- Progress is computed live from `WorkoutSession`/`WorkoutSet` on every request;
  there is no caching layer. `GET /challenges`, `join`, and `leaderboard` all
  perform a DB write (progress refresh + commit) even on a "read" request
  (`challenges.py:68-73,113-114`).
- No challenges-specific rate limiting beyond whatever applies globally.

## Open Questions

- Is the "`completed_at` never resets" behavior for weekly/monthly challenges
  intentional (first time hitting the target marks that challenge permanently
  complete) or an oversight against the apparent intent of a recurring per-period
  challenge? No comment or code path in `challenges.py` addresses this either way.
- Is a DB-level uniqueness safeguard planned for `user_challenges(user_id,
  challenge_id)`? None exists today (see design.md Risks).
- Should `is_group` also gate the backend leaderboard endpoint, or is a
  single-entry leaderboard for solo (`is_group=false`) streak challenges acceptable
  as-is since nothing in the UI currently reaches it?
