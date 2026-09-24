Status: Approved (Retroactive Baseline — documents behavior as implemented, dated 2026-09-10)
Owner: Engineering team (retroactive)
Related: n/a

## Summary

FORMA's settings-profile-premium module covers the Settings screen (`app/lib/features/settings/presentation/settings_screen.dart`) — training-profile editors, voice-coach entry, camera/privacy, rest timer, units, notification preferences, language, and account actions — plus two dedicated sub-screens reached from it: Voice Coach settings (`voice_coach_settings_screen.dart`) and the Premium/upgrade paywall (`premium_screen.dart`). All edits persist through a single shared endpoint, `PATCH /users/me` (`backend/app/api/v1/endpoints/users.py:19-30`), backed by the `User` model (`backend/app/models/user.py`) and the `UserUpdate` / `UserRead` schemas (`backend/app/schemas/user.py`). Notification preferences are stored and round-tripped faithfully but do not drive any push delivery — there is no FCM/APNs/push-messaging integration anywhere in the app or backend. The Premium screen has a real `in_app_purchase: ^3.2.4` dependency wired into its availability check and restore-purchases call, but ships with no configured product IDs, so purchases cannot complete on this build — an honestly-labeled stub, not a fake purchase flow.

## Background / Problem

Once a user has an account and a generated plan, they need a single place to adjust ongoing preferences (training profile fields, coaching voice/verbosity, notification toggles, units, language, rest-timer default) without re-running onboarding, plus a way to see and act on FORMA's paid tier. This module exists to house both: a settings hub that reuses the onboarding partial-update endpoint for profile-shaped fields, and a paywall screen that is honest about not yet being connected to a real store product.

## User Stories

- As a signed-in user, I can open Settings from my profile hub and see my current goal, schedule, equipment, injuries, voice-coach verbosity, rest-timer default, units, notification setup, and language at a glance.
- As a user, I can edit my goal, experience level, weekly schedule, equipment, and injuries from Settings without repeating the full onboarding quiz.
- As a user, I can toggle which notification categories I'd want (workout reminders, achievement alerts, weekly summary, challenge updates) and have that choice saved to my account.
- As a user, I can tune voice-coach behavior (on/off, verbosity, voice, rep counting, encouragement, volume, music ducking) and hear a sample of what the coach would say.
- As a user, I can switch between metric and imperial units, and set my default rest-timer duration.
- As a user, I can check my camera permission status and jump to system settings to change it.
- As a user, I can open the Premium screen to see FORMA Pro's feature list and pricing, and attempt to start a free trial or restore a prior purchase.
- As a user on a build with no in-app-purchase product configured, I am told plainly that purchases aren't available yet rather than seeing a flow that silently fails or fakes success.

## Acceptance Criteria (EARS format: "WHEN/IF ... THE SYSTEM SHALL ...")

**Settings screen — display**
- WHEN the Settings screen builds and the current user is not yet loaded, THE SYSTEM SHALL show a centered `CircularProgressIndicator` instead of the form (`settings_screen.dart:93-94`).
- WHEN the user is loaded, THE SYSTEM SHALL render four grouped sections — Training, Coach & Camera, App, Account — each a `SettingsSection` of `SettingsRow`s (`settings_screen.dart:99-232`, `widgets/settings_row.dart:85-117`).
- THE SYSTEM SHALL display the Goals & Experience row's value as the humanized current goal (or "Not set"), the Schedule row as "`{days}` days · `{minutes}` min" (or "Not set" if either is null), the Equipment row as an item count, and the Injuries row as "None" or an "`{n}` active" badge with a red dot (`settings_screen.dart:104-146`).
- THE SYSTEM SHALL display the Appearance row as a disabled, non-interactive "Dark" value (`showChevron: false, enabled: false`) — dark mode is not user-configurable (`settings_screen.dart:176-182`).

**Editing training-profile fields (Goals/Experience, Schedule, Equipment, Injuries)**
- WHEN the user taps Goals & Experience, Schedule, or Equipment, THE SYSTEM SHALL open a modal bottom sheet pre-filled with the current values and, on Save, SHALL call `AuthController.submitOnboarding` with only the changed keys present (`goal`/`experience_level`, `days_per_week`/`session_minutes`, or `equipment`), which the backend applies via `OnboardingUpdate` with `exclude_unset=True` so unrelated fields are left untouched (`settings_screen.dart:297-315, 389-400, 480-491`; comment at `settings_screen.dart:300-303` documents the partial-update reuse).
- WHEN the user taps Injuries and saves, THE SYSTEM SHALL submit every checked body part as a single `Injury(part, side: 'both', severity: 'moderate')` regardless of the onboarding quiz's finer-grained side/severity capture — settings editing is coarser by design (`settings_screen.dart:560-565`).
- IF any of these saves throws, THE SYSTEM SHALL re-enable the Save button and show a `SnackBar` reading "Could not save. Try again." (`settings_screen.dart:309-314`, and equivalently for each sheet).

**Editing rest timer and units**
- WHEN the user adjusts the rest-timer stepper (±15s, clamped to 15–600s) and taps Save, THE SYSTEM SHALL call `AuthController.updateProfile(restTimerDefaultS: seconds)`, which sends `PATCH /users/me` with `rest_timer_default_s` (`settings_screen.dart:640-651`, `users.py:19-30`).
- WHEN the user selects a units option that differs from the current value, THE SYSTEM SHALL immediately call `updateProfile(units: ...)` and close the sheet on success; selecting the already-active option SHALL just close the sheet without a network call (`settings_screen.dart:713-728`).

**Editing notification preferences**
- WHEN the user taps Notifications, THE SYSTEM SHALL open a sheet seeded from `user.notificationPrefs` showing four independent switches: Workout reminders, Achievement alerts, Weekly summary, Challenge updates (`settings_screen.dart:793-867`).
- THE SYSTEM SHALL display explanatory copy stating these preferences "are saved now and will govern what gets pushed to your device once FORMA's push notification service is wired up — no notifications send yet" (`settings_screen.dart:838-842`) — a truthful, deliberate scope statement, not a bug.
- WHEN the user taps Save, THE SYSTEM SHALL call `updateProfile(notificationPrefs: prefs.toJson())`, sending `PATCH /users/me` with a `notification_prefs` object of four booleans; the backend stores it verbatim into the `notification_prefs` JSONB column and returns it unchanged on the next `GET /users/me` (`settings_screen.dart:813-824`, `user.py:51-61`, `schemas/user.py:25`).
- THE SYSTEM SHALL NOT trigger, schedule, or send any push/local notification as a result of this save — no FCM, APNs, or equivalent client or server package exists in this codebase (`app/pubspec.yaml`, `backend/app/api/v1/endpoints/*.py` — verified absent).

**Voice-coach settings**
- WHEN the Settings screen's Voice Coach row is tapped, THE SYSTEM SHALL navigate to `AppRoutes.voiceCoachSettings` (`/profile/settings/voice-coach`) (`settings_screen.dart:153-157`, `app_router.dart:80`).
- THE SYSTEM SHALL seed the screen's local state from `authControllerProvider`'s current `voiceCoach` (or `VoiceCoachSettings()` defaults if unset) and SHALL update local state immediately on every control change for a responsive feel (`voice_coach_settings_screen.dart:75-76`).
- WHEN the Voice Coaching toggle, a verbosity option (off/minimal/standard/detailed), the voice picker, "Count reps out loud", or "Encouragement" changes, THE SYSTEM SHALL immediately persist via `updateProfile(voiceCoach: settings.toJson())` (`voice_coach_settings_screen.dart:85-94, 145-194`).
- WHEN the Coach Volume slider is dragged, THE SYSTEM SHALL update local state on every change but SHALL persist only once, on `onChangeEnd`, to avoid firing a request per pixel of drag (`voice_coach_settings_screen.dart:219-223`, doc comment `voice_coach_settings_screen.dart:65-66`).
- WHEN the user taps "Hear an example", THE SYSTEM SHALL speak a verbosity-appropriate sample phrase via `flutter_tts` (`^4.2.3`) at the current volume, using the device's installed TTS engine; the three selectable "voice" options (Alex/Sam/Priya) are cosmetic labels persisted as a preference string and SHALL NOT change which TTS engine voice actually speaks, since `flutter_tts` only exposes whatever voices are installed on-device (`voice_coach_settings_screen.dart:96-107`, doc comment `:30-34`).
- IF a persist call throws, THE SYSTEM SHALL show a `SnackBar` reading "Could not save. Try again." (`voice_coach_settings_screen.dart:89-93`). IF TTS playback throws (e.g., unsupported device), THE SYSTEM SHALL show "Could not play a preview on this device." (`voice_coach_settings_screen.dart:100-106`).

**Camera & privacy**
- WHEN the user taps Camera & Privacy, THE SYSTEM SHALL read the current `Permission.camera` status via `permission_handler` (`^12.0.1`) and show it in an `InfoBanner` (green accent if granted, amber otherwise), plus an "Open system settings" button that calls `openAppSettings()` (`settings_screen.dart:761-791`).

**Language entry point**
- WHEN the user taps Language, THE SYSTEM SHALL navigate to `AppRoutes.languageSettings` showing `localeDisplayName(user.locale)` as the current value; the actual locale-switching mechanism and translated-surface scope are owned by module 011-localization-i18n and are not re-specified here (`settings_screen.dart:194-199`, `language_screen.dart`).

**Account actions (cross-reference only)**
- Change email and change password are rendered as Account-section rows on this screen but their validation and endpoint behavior belong to module 001-auth-identity (`settings_screen.dart:885-1090`, `backend/app/api/v1/endpoints/users.py:33-67`) — not re-specified here.
- WHEN the user taps "Delete account", THE SYSTEM SHALL show a dialog stating account deletion "isn't available yet — there's no deletion endpoint on this build" and direct the user to contact support; no deletion endpoint exists in `users.py` (`settings_screen.dart:262-273`).
- WHEN the user confirms Sign out, THE SYSTEM SHALL call `AuthController.logout()` and navigate to `AppRoutes.intro` (`settings_screen.dart:240-260`).

**Premium / IAP screen**
- WHEN the Premium screen opens, THE SYSTEM SHALL display the FORMA Pro feature list (unlimited AI coaching, form analytics, adaptive plan, full history), two selectable plan cards (Annual £59.99/yr shown as £5.00/month with a "SAVE 50%" badge; Monthly £9.99/month), and a "Start 7-day free trial" button — all prices are hardcoded UI strings, not fetched from a store (`premium_screen.dart:15-20, 117-181`).
- WHEN "Start 7-day free trial" is tapped, THE SYSTEM SHALL call `InAppPurchase.instance.isAvailable()`; IF unavailable, THE SYSTEM SHALL show a dialog stating "In-app purchases aren't configured for this build yet — there's no live product to buy. This won't unlock Pro or change your subscription." and take no further action (`premium_screen.dart:55-71`).
- IF `isAvailable()` returns true, THE SYSTEM SHALL proceed past the availability gate, but no `queryProductDetails` or `buyNonConsumable`/`buyConsumable` call exists beyond that point — the purchase flow is left unimplemented ("plumbing left ready rather than faked", `premium_screen.dart:72-77`).
- WHEN "Restore" is tapped, THE SYSTEM SHALL call `InAppPurchase.instance.restorePurchases()` and then, regardless of success or failure, show a `SnackBar` reading "Nothing to restore." (`premium_screen.dart:44-53`).
- THE SYSTEM SHALL NOT set `User.subscription_tier` to `"pro"` anywhere in this flow — no client or backend code path updates `subscription_tier` outside its model default of `"free"` (`user.py:82`; verified no writer exists).
- WHEN closed (X button), THE SYSTEM SHALL pop the route if possible, else navigate to `AppRoutes.profile` (`premium_screen.dart:36-42`).

## Out of Scope

- The real product-ID configuration, store-side purchase completion, receipt validation, and server-side entitlement grant for `subscription_tier` — intentionally unimplemented; see Backlog in design.md.
- Push notification delivery (FCM/APNs/etc.) — no such service exists; notification preferences are storage-only by design in this build.
- The ARB-based translation mechanism, supported-locale list, and per-screen translation coverage — owned by module 011-localization-i18n; this document only covers the Language row as a Settings entry point.
- Change-password and change-email validation/endpoint behavior — owned by module 001-auth-identity.
- Account deletion — no endpoint exists; the UI only shows an explanatory dialog.
- Dark/light theme switching — the Appearance row is display-only and disabled.

## Non-Functional Requirements

- All profile-shaped edits (goals, schedule, equipment, injuries, units, rest timer, voice coach, notification prefs) reuse the same two endpoints — `PATCH /users/me` (`UserUpdate`) and `PATCH /onboarding` (`OnboardingUpdate`, via `submitOnboarding`) — both applying `exclude_unset=True`/equivalent partial semantics so a save never clobbers unrelated fields (`users.py:19-30`, comment `settings_screen.dart:300-303`).
- Every persisting sheet/control in Settings and Voice Coach follows the same optimistic-local-update-then-PATCH pattern with a generic failure `SnackBar`; there is no field-level validation beyond what the input widgets (radio/choice/checkbox/slider) structurally allow.
- The voice-coach volume slider deliberately debounces persistence to `onChangeEnd` to avoid per-pixel network calls (`voice_coach_settings_screen.dart:65-66, 219-223`).

## Open Questions

- No open questions were found encoded in the code (no TODOs/FIXMEs in the read files) — this baseline documents current behavior only.
