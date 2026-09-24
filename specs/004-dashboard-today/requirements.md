Status: Approved (Retroactive Baseline — documents behavior as implemented, dated 2026-09-10)
Owner: Engineering team (retroactive)
Related: n/a

## Summary
The "Today" tab (`app/lib/features/dashboard/presentation/today_screen.dart`, `today_controller.dart`) is the app's home screen. On load it shows a greeting, the user's workout for today (or a rest-day card), a weekly progress strip with streak/volume/form stats, an optional AI-coach promo banner, and a list of recently finished sessions. It is a read/aggregate surface — it does not own any data of its own, only assembles and displays state owned by the Programs, Workout, and Progress features.

## Background / Problem
Users need a single landing view that answers "what do I do today?" without navigating to the Plan tab, and that surfaces recent progress (streak, volume, form) and recovery status at a glance. This module composes that view from existing per-feature providers/repositories rather than introducing a new backend endpoint.

## User Stories
- As a user, when I open the app, I see today's scheduled workout (or a rest-day summary) so I know what to do without visiting the Plan tab.
- As a user, I see this week's training days, my current streak, weekly volume, and average form score at a glance.
- As a user with no active program, I'm prompted to build a plan (if onboarding isn't done) or to retry plan generation (if it is).
- As a user, I can start today's workout, preview it, swap it, or train a freestyle session on a rest day directly from this screen.
- As a user, I see my most recently finished sessions and can tap into a session's summary.
- As a user, I can pull to refresh the screen to get the latest program/session/recovery data.

## Acceptance Criteria (EARS format: "WHEN/IF ... THE SYSTEM SHALL ...")
- WHEN the Today tab is opened, THE SYSTEM SHALL load the active program (via `activeProgramControllerProvider`), the most recent 30 workout sessions (via `WorkoutRepository.listSessions(limit: 30)`), and recovery data (via `recoveryProvider`) before rendering content.
- IF the recovery fetch fails, THE SYSTEM SHALL still render the rest of the screen with an empty recovery list rather than failing the whole load.
- WHEN the active program is null, THE SYSTEM SHALL show a "No plan yet" empty state, offering "BUILD MY PLAN" (navigates to onboarding) if the user has not completed onboarding, or "GENERATE MY PLAN" (triggers `regenerateProgram()`) if they have.
- WHEN the active program has a day matching today's weekday that is not a rest day, THE SYSTEM SHALL show the workout-day card with the day's label, muscle tags, exercise/set counts, estimated duration, a load-progress strip, and a "START WORKOUT" action.
- IF the user has an unfinished session started today for that program day, THE SYSTEM SHALL reflect its logged set count in the load-progress strip.
- WHEN today has no scheduled workout day (rest day or no matching day), THE SYSTEM SHALL show the rest-day card with a recovery headline, per-muscle recovery bars, a "10-MIN MOBILITY" placeholder action, and a "TRAIN ANYWAY" freestyle-session action.
- IF recovery data is non-empty, THE SYSTEM SHALL show a compact recovery card (chest/legs/back) beneath the workout-day or rest-day card.
- WHEN the screen renders, THE SYSTEM SHALL show a "THIS WEEK" section with a 7-day (Mon–Sun) trained/untrained strip, a "done of scheduled" count, and STREAK / VOLUME / FORM stat tiles computed from the loaded sessions.
- WHEN the AI-coach banner has not been dismissed in this session, THE SYSTEM SHALL show it above the "RECENT" section; dismissing it hides it until the screen is rebuilt (state is local, not persisted).
- WHEN there are finished sessions, THE SYSTEM SHALL show up to 3 most-recent ones in a "RECENT" section, each tappable to the session summary; a PR badge is shown if any set in that session isPr.
- WHEN the user pulls to refresh, THE SYSTEM SHALL invalidate and re-fetch the Today controller's state.
- IF loading fails, THE SYSTEM SHALL show an error empty state with a "RETRY" action that invalidates the controller.

## Out of Scope
- Editing the program, logging sets, or running a workout session (owned by Programs/Workout features).
- Notification bell action (icon present, `onPressed: () {}` — no behavior wired).
- "10-MIN MOBILITY" action (shows a "Coming soon." snackbar only).
- Persisting coach-banner dismissal across rebuilds/app restarts.

## Non-Functional Requirements
- Recovery fetch failure must not block the rest of the dashboard (isolated try/catch in the controller).
- Today watches the shared `activeProgramControllerProvider` (not an independent fetch) so a program regenerated from the Plan tab or onboarding is reflected here automatically without a manual refresh.

## Open Questions
None recorded — no open questions found in code comments or history for this module.
