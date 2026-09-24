Status: Approved (Retroactive Baseline — documents behavior as implemented, dated 2026-09-10)
Owner: Engineering team (retroactive)
Related: n/a

## Summary

The Progress tab is a read-only analytics surface over a user's logged workouts. A hub screen (`ProgressHubScreen`) shows period-scoped summary stats plus glanceable row-links into five areas — volume by muscle, recovery per muscle group, a "strength" fold (recent PR trend), a "records" fold (recent PRs), and consistency — with a dedicated detail screen for volume, recovery, form quality, and consistency. All data is computed server-side, on read, from `WorkoutSession`/`WorkoutSet` rows and the `PersonalRecord` table; nothing here is pre-aggregated or cached in the database. A separate `BodyMetric` model/table exists in the schema (`backend/app/models/body_metric.py`) but has no service, schema, endpoint, or Flutter UI wired to it anywhere in the codebase — despite the model's presence, body-weight-history tracking is not an implemented feature.

## Background / Problem

Users training with FORMA need a way to see whether their training is working: how much volume they're moving, whether they're neglecting a muscle group, whether a muscle is fatigued, whether their squat form is trending up or down, and whether they're showing up consistently. Rather than one dense screen, this is split into a scannable hub (`progress_hub_screen.dart`) with tap-through detail screens per topic, backed by seven read endpoints under `/progress/*` (`backend/app/api/v1/endpoints/progress.py`) plus the shared `/achievements/records` endpoint for personal records (`backend/app/services/progress.py:current_records`, consumed via `achievements_providers.dart`'s `personalRecordsProvider`).

## User Stories

- As a lifter, I want a single screen summarizing my workouts/volume/time-in-gym/avg-form for a chosen period (week/month/3-month/year/all) so I can gauge recent training at a glance.
- As a lifter, I want to see which muscles I'm training most/least (by set count and volume) so I can spot neglected muscle groups and check my push/pull and upper/lower balance.
- As a lifter, I want an estimate of how recovered each muscle group is since I last trained it, with a plain-language suggestion, so I can decide what to train today.
- As a lifter, I want to see my personal records (weight × reps, estimated 1RM) and a recent-PR strength trend so I know I'm getting stronger.
- As a FORMA Pro subscriber, I want to see my camera-coached form-quality score trending over time, overall or filtered to one exercise, so I know whether my technique is improving.
- As a lifter, I want a monthly calendar of training days (with volume-based shading and PR markers) so I can see my consistency at a glance and drill into any month.

## Acceptance Criteria (EARS format: "WHEN/IF ... THE SYSTEM SHALL ...")

**Hub / Summary**
- WHEN the Progress hub loads, THE SYSTEM SHALL fetch and display workout count, total volume (kg), time in gym, and average form score for the selected period (default `month`) via `GET /progress/summary`.
- WHEN the user changes the period chip (week/month/3month/year/all), THE SYSTEM SHALL refetch the summary and the volume-by-muscle row for that period.
- IF the summary or volume request errors, THE SYSTEM SHALL show an inline error state with a friendly message rather than crashing the screen.

**Volume**
- WHEN the volume-by-muscle row-link loads with data, THE SYSTEM SHALL show the top muscle by set count as the subtitle and a mini bar preview of the top 6 muscles.
- IF no sets are logged for the period, THE SYSTEM SHALL show "No sets logged yet" instead of a chart.
- WHEN the Volume detail screen loads, THE SYSTEM SHALL show a period-bucketed volume bar chart, a full per-muscle set-count breakdown (with a 10–20-set "where most people grow" band shown only for `week`), push/pull and upper/lower balance ratios with a plain-language reasoning sentence, and a fixed 12-week (`3month`) trend line independent of the selected period.
- WHEN a volume bucket's total is less than half the immediately preceding bucket's total, THE SYSTEM SHALL flag that bucket `is_deload` and render it visually distinct (gray bar / shaded trend-line band) with a "Deload: ..." caption.
- Each set is attributed to exactly one muscle for volume purposes: `exercise.primary_muscles[0]` (the exercise's first listed primary muscle). Sets on exercises with no `primary_muscles` are excluded from the by-muscle breakdown entirely.

**Recovery**
- WHEN the recovery data loads, THE SYSTEM SHALL return exactly one `RecoveryItem` per one of 10 fixed muscle groups (chest, back, quads, hamstrings, glutes, shoulders, calves, biceps, triceps, core), regardless of training history.
- IF a muscle group has never been trained (or not within the last 3 months of fetched sessions), THE SYSTEM SHALL report it as 100% recovered with no last-trained date.
- WHEN a muscle group was trained, THE SYSTEM SHALL compute `recovered_pct` as `min(100, hours_since_last_trained / recovery_window_hours * 100)`, where the window is a fixed per-muscle constant (48h: chest/back/quads/hamstrings/glutes; 36h: shoulders/calves; 24h: biceps/triceps/core).
- WHEN the least-recovered muscle group is at 100%, THE SYSTEM SHALL show "Fully recovered" on the hub row-link instead of naming a muscle as needing the most time.
- WHEN today's scheduled program day has muscle tags, THE SYSTEM SHALL tailor the recovery detail screen's suggestion text to those tagged muscles' recovery state; otherwise it SHALL fall back to a general suggestion based on the single least-recovered muscle group.
- THE SYSTEM SHALL render a front/back body silhouette with each tracked zone tinted by that muscle's recovered percentage (red→amber→green), plus a legend and a per-muscle list sorted least- to most-recovered.

**Personal Records / Strength**
- WHEN a set's estimated 1RM (Epley formula) exceeds the user's prior best for that exercise, THE SYSTEM SHALL record a new `PersonalRecord` and flag the originating set `is_pr = true`.
- WHEN the hub loads with at least one PR, THE SYSTEM SHALL show a "Records" fold listing the 3 most recent PRs (exercise, weight × reps, relative date) and a "Strength" fold with a sparkline trend for whichever exercise most recently set a PR.
- IF the user has no PRs yet, THE SYSTEM SHALL hide the "Records" fold entirely and show a placeholder message in the "Strength" fold.
- There is no dedicated top-level route for strength trend or full PR history in this module — both are folded directly onto the hub.

**Form Quality (FORMA Pro only)**
- IF the requesting user's `subscription_tier` is not `pro`, THE SYSTEM SHALL reject `GET /progress/form-quality` with HTTP 402.
- WHEN a non-Pro user views the hub, THE SYSTEM SHALL show the form-quality row as locked ("Unlock with FORMA Pro" + PRO badge) without calling the endpoint.
- WHEN a non-Pro user opens the Form Quality detail screen, THE SYSTEM SHALL catch the resulting 402 and render `ProLockedTeaser` (see cross-reference below) instead of a generic error.
- WHEN a Pro user has form-scored sets, THE SYSTEM SHALL show a week-over-week average form-score trend (0–100), optionally filtered to one exercise, with a 12-week delta readout.

**Consistency**
- WHEN the hub loads, THE SYSTEM SHALL show the current month's session count and a 28-day-window dot grid of trained/untrained days.
- WHEN the Consistency detail screen loads for a given month, THE SYSTEM SHALL render a calendar grid shaded by that day's logged volume (relative to the month's max) with a distinct border on any day containing a PR, plus a scrollable list of training days with per-day session labels, set counts, duration, and average form badge.
- THE SYSTEM SHALL allow navigating to any past month but SHALL disable navigating forward past the current month.

## Out of Scope

- Body-weight / body-metric history tracking: the `BodyMetric` SQLAlchemy model and `body_metrics` table exist, but no endpoint, service function, Pydantic schema, or Flutter repository/provider/screen reads or writes it anywhere in the current codebase. The only weight value actually surfaced in the app is `User.weight_kg`, a single current value captured at onboarding — an unrelated field with no history.
- Actual premium/IAP purchase flow and entitlement management — owned by module 010-settings-profile-premium; this module only reads `subscription_tier`/`isPro` and renders `ProLockedTeaser` (`app/lib/features/progress/presentation/widgets/pro_teaser.dart`), which gates the Form Quality screen only and links out to `AppRoutes.premium`.
- Per-rep form breakdowns (which rep had flared elbows, per-rep depth) — explicitly noted in `form_quality_trend`'s docstring as not reconstructable server-side from stored set-level `form_score`/`depth_pct`.
- Writing/editing workout data from the Progress tab — this module is read-only.

## Non-Functional Requirements

- All seven `/progress/*` endpoints require authentication (`get_current_user` dependency) and are scoped to the requesting user's own data.
- Period parameters are validated server-side against a fixed set (`week|month|3month|year|all`); an invalid value returns HTTP 400.
- Client-side fetches use Riverpod `FutureProvider.autoDispose` (plain or `.family`) per query — no persistent client-side cache; each screen re-fetches on parameter change and disposes when no longer watched.
- The recovery detail screen's program-day lookup (for tailoring the suggestion text) is best-effort: a failed/slow program fetch must not block the rest of the screen from rendering.
- Aggregation is done in Python over a bounded, period-filtered fetch (not pushed into SQL) — an explicit, documented trade-off favoring clarity over query performance for what is expected to be one person's training log, not big data (`backend/app/services/progress.py` module docstring).

## Open Questions

- Whether body-metric (body-weight-history) tracking is intended to ship as part of this module or a different one — the model exists but nothing consumes it.
- Whether the two independent Pro-gating code paths for Form Quality (client-side `isPro` short-circuit on the hub vs. server 402 caught on the detail screen) are intended to stay separate or should be unified.
