Status: Approved (Retroactive Baseline — documents behavior as implemented, dated 2026-09-10)
Owner: Engineering team (retroactive)
Related: n/a

## Summary

A 9-step quiz that runs immediately after account creation and before a new
user reaches the main app. It collects training goal, experience level,
basic stats (DOB/gender/height/weight), training location, available
equipment, weekly frequency/session length, split preference, and injuries,
then generates the user's first workout program and shows a preview before
handing off to the main dashboard. Implemented in
`app/lib/features/onboarding/` (Flutter) and
`backend/app/api/v1/endpoints/onboarding.py` (FastAPI `PATCH /onboarding`).

## Background / Problem

A new account has no training profile and no program. The app cannot show a
useful "Today" dashboard (module 004) until a program exists (module 003),
and program generation needs goal/experience/equipment/frequency/injury
inputs. Onboarding is the single collection point for those inputs and the
gate that keeps an unonboarded, logged-in user off the rest of the app
(enforced by the router redirect in `app/lib/core/router/app_router.dart`,
not by this module directly).

## User Stories

- As a new user, I answer a short multi-step quiz about my goal, experience,
  body stats, training location/equipment, weekly availability, split
  preference, and injuries, so the app can build a program suited to me.
- As a new user, I can go back and change any earlier answer, either with
  the in-flow back arrow or by tapping a row on the final review screen
  (`Step8Review`), before I commit to building a plan.
- As a new user, I can skip the body-stats step (`Step3Numbers`) or declare
  "nothing to report" on the injuries step (`Step7Injuries`) without being
  blocked from continuing.
- As a new user, after tapping "Build my plan" I see a short animated
  checklist while my plan is generated, then a preview of my first week
  (`PlanPreviewScreen`) before landing on the main dashboard.
- As a new user, from the plan preview I can regenerate the plan with the
  same answers, or continue to a closing "Save your plan" screen
  (`SaveYourPlanScreen`) before entering the app.

## Acceptance Criteria (EARS format: "WHEN/IF ... THE SYSTEM SHALL ...")

- WHEN a logged-in user has `onboardingCompleted == false`, THE SYSTEM SHALL
  redirect them to `/onboarding` regardless of what route they requested
  (`app_router.dart` line 139).
- WHEN the user is on step 1 (`Step1Goal`), THE SYSTEM SHALL disable
  Continue until a goal is selected (`step1_goal.dart` line 60).
- WHEN the user is on step 2 (`Step2Experience`), THE SYSTEM SHALL disable
  Continue until an experience level is selected (`step2_experience.dart`
  line 57).
- WHEN the user selects a gym location on step 4a (`Step4Location`), THE
  SYSTEM SHALL pre-check a matching equipment preset for step 4b
  (`onboarding_controller.dart` `setGymLocation`, lines 218-220; presets in
  `equipment_catalog.dart` `presetFor`, lines 74-88).
- WHEN the user changes days-per-week on step 5 (`Step5Frequency`) to a
  value incompatible with the currently selected split, THE SYSTEM SHALL
  reset the split preference to `'auto'` (`onboarding_controller.dart`
  `setDaysPerWeek`, lines 242-248, using `_splitFitsDays`, lines 274-282).
- IF the split preference is `push_pull_legs`, THE SYSTEM SHALL require
  `daysPerWeek` to be 3 or 6, and IF it is `body_part`, THE SYSTEM SHALL
  require `daysPerWeek >= 5`; THE SYSTEM SHALL visually disable
  non-fitting options on step 6 (`Step6Split`, `_fitsDays`,
  `step6_split.dart` lines 25-35, disabled via `OnboardingOptionCard.enabled`).
- WHEN the user selects "Nothing to report" on step 7 (`Step7Injuries`), THE
  SYSTEM SHALL clear any previously flagged injuries and advance
  (`step7_injuries.dart` lines 212-218).
- WHEN the user taps a row on step 8 (`Step8Review`), THE SYSTEM SHALL jump
  the flow directly to the corresponding earlier step for editing
  (`step8_review.dart` `_ReviewRow.targetPage`; `onboarding_flow_screen.dart`
  line 69, `onEditStep: _goTo`).
- WHEN the user taps "Build my plan" (`Step8Review` → `Step9Building`), THE
  SYSTEM SHALL first call program generation (`POST /programs/generate` via
  `ProgramsRepository.generateProgram`), and only after that call completes
  SHALL it set `onboardingPostFlowActiveProvider` to `true` and then call
  `PATCH /onboarding` (`AuthController.submitOnboarding`) to persist the
  quiz answers and flip `onboarding_completed` to `true`
  (`step9_building.dart` lines 90-116). This order is required so a program
  already exists by the time `onboarding_completed` becomes true.
- WHEN `onboarding_completed` becomes `true` while `onboardingPostFlowActiveProvider`
  is `true` and the app is still on `/onboarding`, THE SYSTEM SHALL NOT
  redirect to `/today` (`app_router.dart` line 141); it SHALL wait for
  `Step9Building` to explicitly navigate to `/onboarding/plan-preview`.
- WHEN plan generation or the onboarding submit call fails, THE SYSTEM SHALL
  show an error state with "Try again" (retries `_start()`) and "Back to
  review" actions, and SHALL NOT navigate forward (`step9_building.dart`
  lines 117-120, 133-154).
- WHEN the user cancels on the building step, THE SYSTEM SHALL abandon the
  in-flight submission's UI effects and return to `Step8Review`
  (`step9_building.dart` `_cancel`, lines 123-126).
- WHEN `PlanPreviewScreen` loads and no active program is found, THE SYSTEM
  SHALL show an empty state with a "BUILD MY PLAN" action that re-triggers
  generation (`plan_preview_screen.dart` lines 68-79).
- WHEN the user taps "Looks good" on the plan preview, THE SYSTEM SHALL
  navigate to `/onboarding/save-plan` (`plan_preview_screen.dart` line 459).
- WHEN the user taps "Continue with email" or "NOT NOW — keep it on this
  device only" on `SaveYourPlanScreen`, THE SYSTEM SHALL set
  `onboardingPostFlowActiveProvider` to `false` and navigate to `/today`
  (`save_your_plan_screen.dart` lines 43-52). Apple and Google buttons on
  this screen show a "coming soon" snackbar and take no other action
  (lines 26-28, 101-111).

## Out of Scope

- The plan-generation algorithm itself (deterministic vs. AI/Groq path,
  exercise selection, set/rep scheme) — owned by module
  003-programs-plan-exercises.
- The router's full redirect matrix for all app states — owned by module
  013-engineering-infrastructure; this doc covers only the onboarding-
  relevant branches.
- Real Apple/Google sign-in — both are "coming soon" stubs on
  `SaveYourPlanScreen`; account creation itself happens before onboarding
  starts (module 001-auth-identity).
- Editing training profile/equipment/injuries after onboarding — that is
  Settings functionality (module 010-settings-profile-premium), not this
  flow.

## Non-Functional Requirements

- No in-progress quiz state is persisted locally or remotely — it lives
  only in the in-memory `OnboardingController` (Riverpod `Notifier`) until
  the final submit on step 9 (`onboarding_controller.dart` lines 189-191).
  An app restart or process kill mid-quiz loses all progress.
- All 9 steps share one scaffold (`OnboardingStepScaffold`) for consistent
  "STEP N OF 9" progress chrome, back navigation, and footer placement.
- Step 9's checklist animation (`_animateChecklist`) runs concurrently with
  the real network calls (`Future.wait`), so perceived progress reflects
  genuine work in flight rather than a fixed fake timer.

## Open Questions

- None recorded in code — this is a retroactive baseline; no open TODOs or
  FIXMEs were found in the onboarding source files.
