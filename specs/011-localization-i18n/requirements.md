Status: Approved (Retroactive Baseline — documents behavior as implemented, dated 2026-09-10)
Owner: Engineering team (retroactive)
Related: n/a

## Summary

FORMA ships a two-locale UI (English `en`, Hindi `hi`) via Flutter's standard `flutter_localizations` + ARB pipeline. `app/lib/l10n/app_en.arb` (template) and `app/lib/l10n/app_hi.arb` each define 63 string keys, compiled by `flutter gen-l10n` (configured in `app/l10n.yaml`, triggered by `generate: true` in `app/pubspec.yaml:72`) into `app/lib/l10n/generated/app_localizations{,_en,_hi}.dart`. A Riverpod `Notifier<Locale>` (`app/lib/core/localization/locale_controller.dart`) holds the active locale, restored from `SharedPreferences` on launch and persisted on change; `MaterialApp.router` in `app/lib/main.dart` watches it to drive `AppLocalizations.of(context)` app-wide. The user-facing switch is `LanguageScreen` (`app/lib/features/settings/presentation/language_screen.dart`, owned by module 010), which also PATCHes the choice to the backend's `User.locale` column (module 010's `PATCH /users/me`) for storage — though, per the empirical trace in this spec, that stored value is not currently read back to restore locale on another device or a fresh login.

This is a **deliberately bounded** first pass: only 63 keys exist, and — verified by grepping `app/lib` for `AppLocalizations.of(context)` — only the intro screen, auth screen, all ten onboarding-quiz step screens, the bottom tab bar, and the Settings screen's section/row labels actually consult it. Every other feature (dashboard, workout tracking, camera coaching, programs, progress, achievements, challenges) renders English text unconditionally regardless of the selected locale.

## Background / Problem

FORMA needed a language switch to reach Hindi-speaking users for the "front door" of the app — the parts a new or returning user sees before they're deep into a workout: the pitch (intro carousel), account creation, the onboarding quiz that builds their plan, the persistent tab bar, and the settings screen that houses the language toggle itself. Translating the entire app (workout logging, live camera-coaching overlays, progress charts, achievements, challenges) was out of scope for this pass; the module exists to prove the mechanism (ARB → codegen → Riverpod-driven `MaterialApp` locale → account-level persistence) end-to-end on a bounded slice rather than to achieve full app coverage.

## User Stories

- As a new user, I can read the intro carousel, create an account, and sign in in Hindi if I select it, so the very first impression of the app is in my language.
- As a user running the onboarding quiz, I can see every step's title and the "Continue" / "Build my plan" controls in Hindi.
- As a user, I can read the bottom tab bar (Today, Programs, Coaching, Progress, Profile) in Hindi.
- As a user, I can open Settings and read its section headers and row labels in Hindi, and switch the language from there via a two-option radio list (English / हिन्दी).
- As a user, my language choice is remembered on this device across app restarts without needing a network call.
- As a signed-in user, my language choice is also saved to my account on the backend when I change it, so the server has a record of my preference (see Out of Scope for the read-back gap).
- As a user on a screen that isn't part of this pass (e.g. workout tracking, camera coaching, progress detail), I still see a fully functional English UI rather than missing strings or crashes — the app never shows a raw ARB key or blank label for an unlocalized screen, because those screens simply don't call `AppLocalizations` at all.

## Acceptance Criteria (EARS format: "WHEN/IF ... THE SYSTEM SHALL ...")

**Locale selection & persistence**
- WHEN the app launches, THE SYSTEM SHALL default `LocaleController`'s state to `Locale('en')` synchronously, then asynchronously read the `forma_locale` key from `SharedPreferences` and update state to the stored locale if it is one of `supportedLocales` (`en`, `hi`) (`app/lib/core/localization/locale_controller.dart:16-25`).
- WHEN the user selects a language on `LanguageScreen` that differs from the current locale, THE SYSTEM SHALL call `LocaleController.setLocale`, which SHALL update the in-memory `Locale` state immediately (driving an app-wide rebuild) and persist the language code to `SharedPreferences` under key `forma_locale` (`locale_controller.dart:27-31`).
- WHEN `setLocale` completes, THE SYSTEM SHALL attempt `AuthController.updateProfile(locale: code)`, which SHALL PATCH `/users/me` with the new `locale` value (`language_screen.dart:31-32`; backend `backend/app/api/v1/endpoints/users.py:19-29`; `backend/app/schemas/user.py` `UserUpdate.locale`).
- IF the backend PATCH fails, THEN THE SYSTEM SHALL swallow the error and leave the already-switched local UI language in place — a failed account sync SHALL NOT revert or block the UI (`language_screen.dart:33-36`).
- WHEN the same user is already signed in with the language selector open, THE SYSTEM SHALL do nothing if the tapped option equals the current locale (`language_screen.dart:28-29`).

**Locale-aware rendering (in-scope screens only)**
- WHEN `MaterialApp.router` builds, THE SYSTEM SHALL pass the current `LocaleController` value as `locale:` and register `AppLocalizations.delegate` alongside the three global Flutter delegates, so `AppLocalizations.of(context)` resolves to the matching generated class (`app/lib/main.dart:22-34`).
- WHEN any of the following screens build, THE SYSTEM SHALL source their static labels from `AppLocalizations.of(context)!`: the intro carousel (`onboarding/presentation/intro_screen.dart`), the auth screen (`auth/presentation/auth_screen.dart`), all ten onboarding step screens (`onboarding/presentation/steps/step1_goal.dart` through `step9_building.dart`, including both `step4_location.dart` and `step4_equipment.dart`), the bottom tab bar (`core/router/app_shell.dart`), and the Settings screen's title, section headers, and row labels (`settings/presentation/settings_screen.dart`).
- WHEN any other feature screen builds (dashboard, workout tracking, camera coaching, programs, progress, achievements, challenges, and Settings' own dialogs/snackbars/error text), THE SYSTEM SHALL render fixed English text regardless of the selected locale, because these call sites do not reference `AppLocalizations`.

## Out of Scope

Verified empirically via `grep -rl "AppLocalizations.of(context)" app/lib` (excluding the generated `l10n/generated/` files) — exactly 14 source files reference it, all falling into the categories below:

**Localized (uses `AppLocalizations.of(context)`):**
- `core/router/app_shell.dart` — bottom tab bar labels only.
- `features/onboarding/presentation/intro_screen.dart` — carousel titles/bodies, Skip/Get Started/"I already have an account".
- `features/onboarding/presentation/steps/` — all 10 step files (step1_goal, step2_experience, step3_numbers, step4_location, step4_equipment, step5_frequency, step6_split, step7_injuries, step8_review, step9_building) — step titles and the shared Continue/Skip-this-step controls.
- `features/auth/presentation/auth_screen.dart` — tab labels, field labels, password-strength/requirement copy, buttons, verification notice, "Forgot password?".
- `features/settings/presentation/settings_screen.dart` — screen title, 4 section headers, 15 row labels.

**Explicitly NOT localized — hardcoded English regardless of locale (confirmed absent from the grep above):**
- `features/dashboard/` (Today tab / home dashboard) — entirely hardcoded; only uses `intl` for date/number *formatting*, not string translation.
- `features/workout/` (workout tracking, logging, history, session summary) — entirely hardcoded.
- `features/camera_coach/` (live camera coaching UI and overlays) — entirely hardcoded; zero `intl` or `AppLocalizations` references at all.
- `features/programs/` (program browser, exercise detail/library) — entirely hardcoded; `intl` used only for formatting in `exercise_detail_screen.dart`.
- `features/progress/` (progress analytics, consistency detail, charts) — entirely hardcoded; `intl` used only for formatting.
- `features/achievements/` — entirely hardcoded; `intl` used only for formatting in `achievements_list_screen.dart`.
- `features/challenges/` — entirely hardcoded; zero `intl` or `AppLocalizations` references.
- Within the otherwise-localized `settings_screen.dart`: confirmation dialog buttons ("Cancel", "OK") and save-failure snackbars ("Could not save. Try again.") are hardcoded English literals, not ARB keys (e.g. `settings_screen.dart:247-270`).
- Within `auth_screen.dart`: the inline error banner (`Text(_error!, ...)`) renders whatever raw exception/error string the backend or client produced — not a translated message.
- Within `intro_screen.dart`: the small decorative badge overlays on each carousel card (`'7'`, `'REPS'`, `'●'`, `'LIVE'`, `'+12%'`, `'THIS WEEK'`) are hardcoded literals, not ARB keys — these read as short numeric/marketing glyphs rather than sentence copy.
- Cross-device / cross-session restore of the backend-stored `locale` value: the client's `User` domain model does carry a `locale` field populated from `GET /users/me` (`features/auth/domain/user.dart:142`), but nothing in `AuthController.build()`/`fetchMe()` applies it back to `LocaleController` — so a fresh login or reinstall on a new device does **not** pick up a previously-saved server-side language preference; only the local `SharedPreferences` value (if present on that device) does.
- No locale beyond English/Hindi is supported (`supportedLocales` is a fixed 2-element list; `locale_controller.dart:5`) — no locale picker for other languages, no RTL handling (moot given `en`/`hi` are both LTR).
- No pluralization, date/number/currency localization is wired through `AppLocalizations` — where formatting occurs at all (e.g. dashboard, workout, progress, achievements screens listed above), it uses `intl`'s `DateFormat`/`NumberFormat` directly and independently of the selected UI locale.

## Non-Functional Requirements

- Locale restore on cold start must not block first paint — `LocaleController.build()` returns the default `en` state synchronously and only updates asynchronously once `SharedPreferences` responds (`locale_controller.dart:17-19`), at the cost of a possible one-frame flash of the wrong locale (see design.md Risks).
- Switching locale must not require a network round trip to take effect locally — `setLocale` mutates in-memory Riverpod state and local storage before any backend call is attempted (`locale_controller.dart:27-31`).
- A failed backend sync of the locale preference must never degrade or block the local UI language switch (`language_screen.dart:33-36`).
- All ARB keys must exist in both `app_en.arb` and `app_hi.arb` with matching key sets (verified: both files have exactly 63 keys) so `flutter gen-l10n` produces complete, non-fallback-dependent generated classes for both locales.

## Open Questions

- Is the write-only backend `locale` sync (saved on change, never read back on login) intentional, or an oversight where the read-back wiring was simply never added? No code comment or TODO addresses this either way.
- Is there a plan to extend `AppLocalizations` coverage to the seven fully-English feature areas (dashboard, workout, camera_coach, programs, progress, achievements, challenges), or is the current scope considered a permanent/shippable boundary for this app?
- Should the hardcoded dialog/snackbar/error strings inside otherwise-localized screens (`settings_screen.dart`, `auth_screen.dart`) be pulled into ARB keys as a smaller follow-up, independent of the larger full-app-coverage question?
