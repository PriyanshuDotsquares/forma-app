Status: Approved (Retroactive Baseline — documents behavior as implemented, dated 2026-09-10)
Owner: Engineering team (retroactive)
Related: n/a

## Approach

The Settings screen is a single `ConsumerWidget` (`SettingsScreen`) that reads the current `User` from `authControllerProvider` and renders four static `SettingsSection`/`SettingsRow` groups (`app/lib/features/settings/presentation/settings_screen.dart`, `widgets/settings_row.dart`). Every editable row opens a local, ephemeral `ConsumerStatefulWidget` bottom sheet (or, for Voice Coach, a dedicated screen) that seeds its state from the current `User`, mutates local state freely, and only calls back into `AuthController` on explicit Save (or immediately on toggle, for switches). There is no separate "settings" domain model or repository — all persistence goes through the existing auth feature's `AuthController`/`AuthRepository` and the existing `User` domain model (`app/lib/features/auth/domain/user.dart`, `app/lib/features/auth/presentation/auth_controller.dart`), reusing two backend endpoints that already existed for onboarding and profile updates. The Premium screen is a self-contained `StatefulWidget` with no backend calls of its own beyond the `in_app_purchase` plugin's device/store availability check — it does not touch `AuthController` or any FORMA API endpoint at all.

## Architecture / Data Flow

**Flow 1 — Editing notification preferences (storage-only, no push wiring)**
1. User taps the Notifications row → `_showNotificationsSheet` opens `_NotificationsSheet(initial: user.notificationPrefs)` (`settings_screen.dart:793-807`).
2. Local `NotificationPrefs` state (`app/lib/features/auth/domain/user.dart:77-...`) is mutated per-switch via `copyWith` (`settings_screen.dart:847-867`); no network call happens per-toggle.
3. On Save, `AuthController.updateProfile(notificationPrefs: prefs.toJson())` (`auth_controller.dart:49-69`) → `AuthRepository.updateProfile` → `PATCH /users/me` with body `{"notification_prefs": {...4 booleans}}`.
4. Backend `update_current_user` (`backend/app/api/v1/endpoints/users.py:19-30`) does `payload.model_dump(exclude_unset=True)` against `UserUpdate.notification_prefs: dict[str, bool] | None` (`schemas/user.py:25`) and `setattr`s the whole dict onto `User.notification_prefs` (a JSONB column, `models/user.py:51-61`), then commits and returns the refreshed `UserRead`.
5. The client replaces `authControllerProvider` state with the server's response (`auth_controller.dart:67-68`), so the sheet's initial values on next open reflect the persisted state.
6. Nothing in this path enqueues, schedules, or transmits a push notification: no FCM/APNs SDK, no push-token registration endpoint, and no background job/service references `notification_prefs` anywhere else in the backend (verified via repo-wide grep — the only hits are the model/schema/endpoint files themselves). The in-sheet copy at `settings_screen.dart:838-842` says exactly this to the user.

**Flow 2 — Voice-coach settings**
1. User taps Voice Coach row → `context.push(AppRoutes.voiceCoachSettings)` → `/profile/settings/voice-coach` → `VoiceCoachSettingsScreen` (`settings_screen.dart:153-157`; route at `app_router.dart:80`).
2. Screen seeds `_settings` from `authControllerProvider.valueOrNull?.voiceCoach` or `VoiceCoachSettings()` defaults (`voice_coach_settings_screen.dart:75-76`).
3. Most controls (enabled toggle, verbosity radio-card, voice picker, count-reps switch, encouragement switch) call `_persist(next)` immediately: `setState` then `AuthController.updateProfile(voiceCoach: next.toJson())` → `PATCH /users/me {"voice_coach": {...}}` → backend `setattr`s the whole JSONB blob the same way as notification_prefs (`models/user.py:64-77`).
4. The volume `Slider` updates local `_settings` on every `onChanged` frame (for a live "N%" readout) but only calls `_persist` in `onChangeEnd`, so dragging produces at most one PATCH (`voice_coach_settings_screen.dart:219-223`).
5. "Hear an example" (`_playSample`, `:96-107`) talks directly to a local `FlutterTts()` instance — `setVolume` then `speak(sampleCue)` — entirely client-side, no network call, no dependency on the persisted state having been saved yet.
6. The three "voice" choices in `_pickVoice` (`:109-135`) write an arbitrary id string (`alex_en_gb`/`sam_en_us`/`priya_en_in`) into `_settings.voice` and persist it like any other field, but nothing reads that id to select a real platform TTS voice — `_playSample` always uses whatever voice `flutter_tts`/the OS picks. This is a cosmetic-preference field, not a functional one (doc comment `:30-34`).

**Flow 3 — Premium/IAP screen's real current behavior**
1. User reaches `/profile/premium` (`PremiumScreen`, route `app_router.dart:82,238`) — from Settings indirectly (via profile hub) or directly from any "Pro" teaser, e.g. `ProLockedTeaser` in progress (`app/lib/features/progress/presentation/widgets/pro_teaser.dart:63`, owned by module 007) pushing `AppRoutes.premium`.
2. Screen renders static feature/price copy and a local `_plan` toggle (annual/monthly) — purely presentational `setState`, no persistence (`premium_screen.dart:33-34, 136-158`).
3. "Start 7-day free trial" → `_startTrial` → `InAppPurchase.instance.isAvailable()`. This is a real call into the `in_app_purchase: ^3.2.4` plugin (`app/pubspec.yaml:52`), which in turn queries the platform store (App Store/Play Store) connector.
4. If unavailable (the expected case on this build, since no product IDs are configured on either store), an `AlertDialog` explicitly tells the user purchases aren't configured yet and that nothing was unlocked or changed (`premium_screen.dart:58-71`).
5. If `isAvailable()` were ever true, execution falls through the `if` block and the method returns — there is no `queryProductDetails`, no `buyNonConsumable`/`buyConsumable` call, and no purchase-stream listener anywhere in the file. The code comment at `premium_screen.dart:72-77` states this is deliberate: "the plumbing is left ready rather than faked."
6. "Restore" → `InAppPurchase.instance.restorePurchases()` (a real plugin call) wrapped in a try/catch that swallows any error, followed unconditionally by a "Nothing to restore." `SnackBar` (`premium_screen.dart:44-53`) — so the UI outcome is identical whether the call succeeds, throws, or the plugin is misconfigured.
7. At no point does this screen call any FORMA backend endpoint or write `User.subscription_tier`; `subscription_tier` stays at its DB default `"free"` (`models/user.py:82`) for every account, which is what backend `progress.py:87-91` checks to 402-gate the Pro-only form-quality-trend endpoint, and what `User.isPro` (`auth/domain/user.dart:170`) reflects client-side (consumed by `profile_screen.dart:169` for the PRO badge and `progress_hub_screen.dart:61,305-...` for the locked-teaser gate).

## Data / Schema

- `users.notification_prefs` — JSONB, `NOT NULL`, default `{"workout_reminders": true, "achievement_alerts": true, "weekly_summary": true, "challenge_updates": true}` (`backend/app/models/user.py:51-61`). No dedicated migration file was inspected; the column is declared with `server_default`, implying it ships via Alembic migration alongside the rest of the `users` table (not verified in this pass — see Open Questions in requirements.md if migration history matters).
- `users.voice_coach` — JSONB, `NOT NULL`, default `{"enabled": true, "verbosity": "standard", "voice": "alex_en_gb", "count_reps": false, "encouragement": true, "volume": 0.7, "duck_music": true}` (`models/user.py:64-77`).
- `users.rest_timer_default_s` — `Integer NOT NULL DEFAULT 90` (`models/user.py:78`).
- `users.subscription_tier` — `String(16) NOT NULL DEFAULT 'free'` (`models/user.py:82`) — the only premium/subscription-related column on `User`. No `xp`-to-tier linkage, no expiry/renewal date column, no store-receipt or transaction-id column exists.
- `users.locale` — `String(8) NOT NULL DEFAULT 'en'` (`models/user.py:45`) — the Settings/Language entry point's persisted field; full mechanism owned by module 011.
- `UserUpdate` (`backend/app/schemas/user.py:19-26`) is the PATCH contract for all of Flow 1/2's fields: `notification_prefs: dict[str, bool] | None`, `voice_coach: dict[str, Any] | None`, `rest_timer_default_s: int | None`, `units: str | None`, `locale: str | None`, plus `full_name`/`avatar_url` (not exercised by this module's UI). None of these fields are validated server-side beyond Pydantic's basic typing — e.g., an arbitrary string can be written to `voice_coach.verbosity` or `notification_prefs` could contain unexpected keys, since the column is a free-form JSONB `dict[str, Any]`/`dict[str, bool]`.
- `UserRead` (`schemas/user.py:47-73`) mirrors these back out, including `subscription_tier` and `xp`, letting the client compute `User.isPro` (`auth/domain/user.dart:170`).

## Alternatives Considered

N/A — retroactive baseline.

## Testing Strategy

No automated tests exist for any part of this module — gap. Specifically verified absent:
- No widget/unit tests under `app/test/` reference settings, voice coach, or premium (the only file in `app/test/` is the default `widget_test.dart` counter-app smoke test, unrelated to this module).
- No backend test directory/files exist under `backend/` for `users.py`'s profile-update behavior (no `backend/tests/` or `test_users*.py` found; the repo has no backend test suite at all as of this baseline).

## Risks / Edge Cases

- **Notification prefs imply capability they don't have.** The switches and their persisted state look fully functional, and the only signal that nothing is wired up is the small explanatory caption in the sheet (`settings_screen.dart:838-842`). If that caption were ever removed or missed, a user would reasonably believe toggling "Workout reminders" off/on has a real effect today.
- **IAP "Start trial" silently no-ops when the store reports available.** `_startTrial`'s happy path (`isAvailable() == true`) falls through with no user feedback and no purchase initiated (`premium_screen.dart:55-78`) — if a store product were ever configured without also adding the `queryProductDetails`/`buyNonConsumable` code, tapping the button would do nothing visible at all, which is worse than the current "not available yet" dialog. This is flagged here as a known gap, not fixed.
- **Restore always claims "Nothing to restore," even on error.** The catch-and-fall-through in `_restore` (`premium_screen.dart:44-53`) means a real plugin/network error is indistinguishable from a genuine empty restore — acceptable for a build with no real purchases to restore, but would need differentiation once IAP is live.
- **Voice picker persists a non-functional preference.** `_settings.voice` is saved to the backend and re-shown on reload, but never changes what `flutter_tts` actually speaks (`voice_coach_settings_screen.dart:30-34`). Not a bug today (documented in-code), but a latent trap if a future engineer assumes the persisted value is wired to playback.
- **Free-form JSONB with no server-side shape validation.** Because `voice_coach` and `notification_prefs` are typed as `dict[str, Any]`/`dict[str, bool]` in `UserUpdate`, a malformed or partial PATCH body would be stored as-is and could produce a shape the Flutter `fromJson` parsers don't expect on the next login — the client-side parsers guard with `as bool? ?? true`-style fallbacks (`auth/domain/user.dart` `NotificationPrefs.fromJson`), which masks rather than rejects bad data.
- **Injuries settings edit is lossy relative to onboarding.** Every injury saved from the Settings sheet becomes `side: 'both', severity: 'moderate'` regardless of what was previously recorded during onboarding for that body part (`settings_screen.dart:560-565`) — a deliberate simplification per the in-code comment, but it means editing injuries from Settings can overwrite finer-grained onboarding data with coarser defaults.

## Backlog / Known Gaps

- **IAP is a real, deliberately honest stub — not a fake purchase flow (intentional, by design).** `in_app_purchase: ^3.2.4` is a genuine dependency (`app/pubspec.yaml:52`), and `PremiumScreen` makes real `isAvailable()` and `restorePurchases()` calls into it. But no product IDs are registered on either store for this build, so `_startTrial` always stops at the availability gate and shows an explicit "not available yet" dialog rather than pretending to sell anything (`premium_screen.dart:55-78`, comment `:72-77`). Completing it requires: registering real product IDs in App Store Connect/Play Console, adding `queryProductDetails` + `buyNonConsumable`/`buyConsumable` + a purchase-stream listener, and a server-side receipt-validation endpoint that flips `User.subscription_tier` to `"pro"` — none of which exists yet.
- **No server-side entitlement writer exists.** `subscription_tier` has no PATCH path, webhook, or receipt-validation endpoint anywhere in `backend/app` — it can only ever be `"free"` for every account created through the current code paths (`models/user.py:82`, confirmed via grep for writers).
- **Push notifications are entirely unimplemented (intentional, by design, honestly labeled in-UI).** No FCM/APNs client package, no server-side push-sending service, and no device-token registration endpoint exist. `notification_prefs` is pure storage, exactly as the in-app copy states.
- **No automated tests** for settings edits, voice-coach persistence, or the premium screen (see Testing Strategy) — gap.
- **No dedicated migration file was inspected** to confirm when `notification_prefs`/`voice_coach`/`subscription_tier` columns were added — flagged for follow-up if migration provenance matters, not asserted either way here.
