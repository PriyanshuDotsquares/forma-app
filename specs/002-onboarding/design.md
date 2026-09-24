Status: Approved (Retroactive Baseline — documents behavior as implemented, dated 2026-09-10)
Owner: Engineering team (retroactive)
Related: n/a

## Approach

A `PageView` of 10 widgets (9 numbered steps + the "Building" step) driven
by button taps, not swipes (`physics: NeverScrollableScrollPhysics`), backed
by one in-memory Riverpod `Notifier<OnboardingAnswers>`
(`onboardingControllerProvider`). Nothing is sent to the backend until the
very last step: `Step9Building` fires the plan-generation call, then the
`PATCH /onboarding` submit, in that specific order, then hands off to a
plan-preview detour before the router is allowed to send the user to
`/today`.

## Architecture / Data Flow

Call-chain trace, file/class/line-cited, for the full quiz-to-plan-preview
flow:

1. **Gate-in.** `app/lib/core/router/app_router.dart` line 139: once a user
   is logged in but `authState.valueOrNull?.onboardingCompleted == false`,
   every route redirects to `AppRoutes.onboarding` (`/onboarding`), which
   renders `OnboardingFlowScreen`
   (`app/lib/features/onboarding/presentation/onboarding_flow_screen.dart`).

2. **State seed.** `OnboardingController.build()`
   (`onboarding_controller.dart` lines 193-201) seeds
   `OnboardingAnswers(equipmentItems: EquipmentCatalog.presetFor('commercial_gym'))`
   so the default gym-location preset and the equipment picker start in
   sync.

3. **Steps 1-8**, each a `ConsumerWidget`/`ConsumerState` under
   `presentation/steps/`, read/write `onboardingControllerProvider` and call
   `onContinue`/`onBack` (wired in `OnboardingFlowScreen.build()`,
   `onboarding_flow_screen.dart` lines 61-70) to animate the shared
   `PageController` via `_goTo(int page)` (lines 41-47):
   - `Step1Goal` (`step1_goal.dart`) → sets `goal`.
   - `Step2Experience` (`step2_experience.dart`) → sets `experienceLevel`.
   - `Step3Numbers` (`step3_numbers.dart`) → sets `units`, `dob`, `gender`,
     `heightCm`, `weightKg` (or nulls all four via the Skip button, lines
     92-107).
   - `Step4Location` (`step4_location.dart`) → sets `gymLocation`, which
     side-effects the equipment preset via
     `OnboardingController.setGymLocation` (`onboarding_controller.dart`
     lines 218-220).
   - `Step4Equipment` (`step4_equipment.dart`) → toggles
     `equipmentItems` (granular picker ids) via `toggleEquipmentItem` /
     `setSectionSelected` / `deselectAllEquipment`.
   - `Step5Frequency` (`step5_frequency.dart`) → sets `daysPerWeek`,
     `sessionMinutes`; changing `daysPerWeek` can reset `splitPreference`
     to `'auto'` if incompatible (`setDaysPerWeek`, lines 242-248).
   - `Step6Split` (`step6_split.dart`) → sets `splitPreference`
     (`auto | upper_lower | push_pull_legs | full_body | body_part`).
   - `Step7Injuries` (`step7_injuries.dart`) → adds/removes `Injury` entries
     (`part`, `side`, `severity`, optional `note`) via `setInjury` /
     `removeInjury` / `clearInjuries`.
   - `Step8Review` (`step8_review.dart`) → read-only summary of all
     answers; tapping a row calls `onEditStep(targetPage)` to jump back to
     that step's page index; "Build my plan" calls `onBuildPlan` →
     `_goTo(9)`.

4. **Step 9 — `Step9Building`** (`step9_building.dart`):
   - `initState` → `_start()` (lines 55-73) runs
     `Future.wait([_animateChecklist(...), _submit(...)])` — the checklist
     animation and the real network work run concurrently.
   - `_submit()` (lines 87-121), in order:
     a. Reads `answers = ref.read(onboardingControllerProvider)`.
     b. Calls `ProgramsRepository.generateProgram(...)`
        (`app/lib/features/programs/data/programs_repository.dart` lines
        39-64), which `POST`s to `/programs/generate`
        (`backend/app/api/v1/endpoints/programs.py` line 54-67, handled by
        `generate_program_smart` — owned by module
        003-programs-plan-exercises, not detailed here), passing goal,
        experience level, days/week, session minutes, split preference,
        canonical equipment, and injuries **as explicit request-body
        overrides**, not read from the (not-yet-saved) profile.
     c. Only after that call resolves: builds
        `payload = answers.toOnboardingPayload()`
        (`onboarding_controller.dart` lines 99-115 — snake_case map
        matching backend `OnboardingUpdate`, always including
        `'onboarding_completed': true`).
     d. Sets `ref.read(onboardingPostFlowActiveProvider.notifier).state = true`
        (`step9_building.dart` line 115) — arms the router-redirect guard
        described in step 6 below, before the flag that will flip
        `onboarding_completed` is sent.
     e. Calls `AuthController.submitOnboarding(payload)`
        (`app/lib/features/auth/presentation/auth_controller.dart` lines
        83-87) → `AuthRepository.submitOnboarding`
        (`app/lib/features/auth/data/...` lines 123-130) → `PATCH
        /onboarding` with the payload →
        `backend/app/api/v1/endpoints/onboarding.py` lines 12-23:
        `setattr` every field from `payload.model_dump(exclude_unset=True)`
        onto `current_user`, `db.commit()`, `db.refresh()`, returns the
        updated `UserRead`. This is what flips `onboarding_completed` to
        `true` server-side, which `AuthController.state = AsyncData(updated)`
        then reflects client-side.
   - **Ordering rationale, verified in code** (`step9_building.dart` lines
     90-98, comment): plan generation happens *first*, and
     `onboarding_completed` is flipped *last*, specifically so a program
     already exists in the DB by the time the router could possibly see
     "onboarded" and consider redirecting — this is the mechanism that
     prevents a user from landing on an empty `/today` dashboard.
   - On success (`_start()` lines 66-73): `context.push(AppRoutes.onboardingPlanPreview)`
     — a `push`, not `go`, deliberately, per the inline comment, to avoid a
     prior bug where a plain push lost a race against the router's
     redirect-on-onboarded logic.
   - On failure: `_error` is set and an error `Scaffold` with "Try again"
     (`_start`) / "Back to review" (`widget.onCancel` → `_goTo(8)`) is shown
     (lines 117-120, 133-154); nothing has navigated forward.

5. **Router guard while mid-handoff.**
   `app_router.dart` line 141:
   `if (loggedIn && onboarded && isOnboarding && !postFlowActive) return AppRoutes.today;`
   — this is the one line in the router that is specific to this module:
   while `onboardingPostFlowActiveProvider` is `true` and the matched
   location is still `/onboarding`, the router will NOT force a redirect to
   `/today` even though `onboarded` just became `true`. Once the pushed
   routes (`/onboarding/plan-preview`, `/onboarding/save-plan`) are the
   matched location, this branch doesn't apply to them at all (they aren't
   `isOnboarding`), so they render freely regardless of the flag.

6. **`PlanPreviewScreen`** (`plan_preview_screen.dart`), pushed via a plain
   `MaterialPageRoute`-style `context.push` (not a `GoRoute` — it's a
   one-off detour, per the file's docstring lines 13-16): reads
   `activeProgramControllerProvider` (module 003) and
   `onboardingControllerProvider` (for goal-based copy) to render the first
   week, a weekly-volume bar chart, and "Regenerate" (re-calls
   `ActiveProgramController.regenerate` with the same stored quiz answers)
   / "Tweak it" (snackbar only) / "Looks good" (→
   `AppRoutes.onboardingSavePlan`) actions.

7. **`SaveYourPlanScreen`** (`save_your_plan_screen.dart`): closing screen.
   "Continue with email" and "NOT NOW" both call the same
   `continueWithEmail()` (lines 43-52): show a confirmation snackbar, set
   `onboardingPostFlowActiveProvider` back to `false` (disarming the guard
   from step 5, since the post-onboarding detour is now finished), and
   `context.go(AppRoutes.today)`. Apple/Google are "coming soon" stub
   buttons (lines 26-28, 101-111) — per the file's own docstring, a real
   account already exists before onboarding starts, so there is no honest
   "create account" step left to gate here.

8. **Pre-onboarding screens**, not part of the numbered quiz but part of
   this module's file set: `SplashScreen` (`splash_screen.dart`) is a bare
   wordmark shown while auth state resolves; `IntroScreen`
   (`intro_screen.dart`) is a 3-page marketing carousel shown to logged-out
   users before `/auth`, with "Skip"/"Get started"/"I already have an
   account" all routing to `AppRoutes.auth` (lines 65, 119, 126) — it does
   not touch `OnboardingAnswers` and runs before an account exists.

## Data / Schema

- **Client-side draft**: `OnboardingAnswers` (`onboarding_controller.dart`
  lines 16-116) — immutable value type with a `copyWith` using an `_unset`
  sentinel (line 9) so optional fields (`dob`, `gender`, `heightCm`,
  `weightKg`) can be explicitly cleared (e.g., the Skip button) rather than
  merely left unspecified. `canonicalEquipment` (lines 50-55) collapses the
  granular picker ids (e.g. `leg_press`, `smith_machine`) down to the fixed
  vocabulary the exercise library understands
  (`barbell | dumbbell | cable | machine | kettlebell | bodyweight`),
  falling back to `bodyweight` if nothing is checked.
- **Equipment catalog**: `EquipmentCatalog` (`equipment_catalog.dart`) is a
  static, hardcoded list of `EquipmentSection`s (Barbell & Plates,
  Dumbbells & Kettlebells, Machines & Cables, Bars & Benches) each holding
  `EquipmentItem { id, label, subtitle?, canonicalToken, icon }`, plus
  `presetFor(gymLocation)` (lines 74-88) returning a starting `Set<String>`
  of item ids per location (`commercial_gym`, `home_gym`, `bodyweight`,
  `mixed`).
- **Outbound payload**: `OnboardingAnswers.toOnboardingPayload()`
  (lines 99-115) → snake_case `Map<String, dynamic>` matching the backend
  `OnboardingUpdate` Pydantic model exactly: `dob, gender, height_cm,
  weight_kg, goal, experience_level, days_per_week, session_minutes,
  split_preference, gym_location, equipment, injuries,
  onboarding_completed`. Note `units` (metric/imperial) is **not** included
  — it is a client-only display preference used to convert `TextField`
  input to/from `cm`/`kg` before storage (`step3_numbers.dart`
  `_parsedHeightCm`/`_parsedWeightKg`); the backend always stores metric.
- **Backend schema**: `OnboardingUpdate`
  (`backend/app/schemas/user.py` lines 29-44) — all fields optional except
  `onboarding_completed: bool = True`. `submit_onboarding`
  (`backend/app/api/v1/endpoints/onboarding.py` lines 12-23) does a blanket
  `setattr` over `payload.model_dump(exclude_unset=True)` onto the
  authenticated `User` row, then commits. Because the Flutter payload
  always includes every key (nulls included) in one shot at final submit,
  this in practice behaves as a full replace of the onboarding-related
  columns, not a sparse patch.
- **User model default**: `User.onboarding_completed`
  (`backend/app/models/user.py` line 44) defaults to `False` — a freshly
  registered account starts un-onboarded, which is what the router redirect
  keys off of.
- **Program-generation request**: `GenerateProgramRequest`
  (`backend/app/schemas/program.py` lines 9-27) — its own docstring
  explicitly states `injuries` is duplicated here (separately from
  `User.injuries`) precisely because, during first-time onboarding,
  `/programs/generate` is called *before* the onboarding profile is saved,
  so `current_user.injuries` would otherwise be empty at generation time.
  This corroborates the generate-before-submit ordering found in
  `step9_building.dart`.

## Alternatives Considered

N/A — retroactive baseline.

## Testing Strategy

- **Flutter**: `app/test/` contains only the default, unmodified
  `widget_test.dart` counter-app smoke test — no onboarding-specific
  widget, controller, or golden tests exist. No automated tests — gap.
- **Backend**: no `tests/` directory exists under `backend/` (only
  third-party test suites vendored inside `backend/.venv/lib/python3.10/site-packages/`,
  which are dependency-internal and not project tests). `submit_onboarding`
  has no automated coverage. No automated tests — gap.

## Risks / Edge Cases

- **No local persistence of in-progress answers.** `OnboardingController`
  is a plain in-memory Riverpod `Notifier` (confirmed by its own docstring,
  `onboarding_controller.dart` lines 189-191: "Nothing here is persisted
  remotely until the final submit on step 9") with no `SharedPreferences`/
  `Hive`/other local store found anywhere under
  `app/lib/features/onboarding/`. An app kill, crash, or OS-initiated
  process termination at any point in steps 1-8 discards all quiz progress;
  the user restarts the 9-step flow from scratch. This is a real,
  by-design data-loss surface for a 9-step form, not a bug per se, but
  worth flagging.
- **Empty-dashboard race — mitigated, not eliminated by construction.** The
  ordering (generate program → set `onboardingPostFlowActiveProvider` →
  submit onboarding) plus the router's `!postFlowActive` guard together
  prevent the previously-described race (per inline comments in both
  `step9_building.dart` and `app_router.dart`, this was an actual prior bug
  the current code is structured to avoid). If `generateProgram` itself
  fails, `_submit`'s `catch` sets `_error` and `submitOnboarding` is never
  called, so `onboarding_completed` stays `false` and the router keeps the
  user on `/onboarding` — consistent with the ordering's intent.
  `onboardingPostFlowActiveProvider` is a plain in-memory
  `StateProvider<bool>` (default `false`), so it also resets to `false` on
  a full app restart; if a process restart happened in the narrow window
  after `onboarding_completed` flips server-side but before
  `SaveYourPlanScreen` resets the flag, the freshly-booted app would read
  `postFlowActive == false` and `onboarded == true` and redirect straight
  to `/today` (skipping plan-preview/save-plan) rather than losing the
  plan — no dashboard-empty risk in that case since the program was
  already generated first, only a skipped closing screen.
- **Illustrative, not authoritative, exercise count.** The step 9 checklist
  line "Found N exercises you can actually do" uses a fabricated formula
  `48 + canonicalEquipment.length * 27` (`step9_building.dart` line 45),
  not a real query against the exercise library — purely copy/flavor text,
  not a data source other code depends on.
- **Split/day-compatibility logic is duplicated.** The
  `push_pull_legs`/`body_part` day-count compatibility rules are
  implemented twice with matching logic: once in
  `onboarding_controller.dart` `_splitFitsDays` (lines 274-282) and once in
  `step6_split.dart` `_fitsDays` (lines 25-35). They agree today, but nothing
  enforces they stay in sync if one changes.

## Backlog / Known Gaps

- No automated tests for any onboarding screen, controller, or the backend
  `PATCH /onboarding` endpoint (see Testing Strategy).
- No local draft persistence for in-progress quiz answers (see Risks).
- Apple/Google sign-in on `SaveYourPlanScreen` are explicit "coming soon"
  stubs (`save_your_plan_screen.dart` lines 26-28, 101-111) — consistent
  with the same convention used elsewhere in the app (Settings
  Notifications/Language), not a defect specific to this module.
- No other TODO/FIXME comments or dead code were found in the files read
  for this module.
