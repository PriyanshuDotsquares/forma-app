Status: Approved (Retroactive Baseline — documents behavior as implemented, dated 2026-09-10)
Owner: Engineering team (retroactive)
Related: n/a

## Approach

Standard Flutter internationalization: ARB files as the source of truth, `flutter gen-l10n` codegen to produce a typed `AppLocalizations` class per locale, a Riverpod `Notifier<Locale>` as the single mutable source for "which locale is active right now," and `MaterialApp.router`'s `locale:` parameter as the mechanism that makes `AppLocalizations.of(context)` resolve to the right generated subclass everywhere in the widget tree. Persistence is two-tier: an immediate local write to `SharedPreferences` (fast, works offline, drives the very next frame) and a best-effort account-level write to the backend's `User.locale` column (for durability/record-keeping — but, per the empirical trace below, not currently read back anywhere).

Locale coverage was scoped narrowly and deliberately to the screens a user sees before/around choosing a language: intro, auth, onboarding quiz, tab bar, Settings. No abstraction was built to "gradually migrate" other screens (no wrapper widgets, no lint rule flagging raw `Text()` literals) — screens outside the covered set simply never call `AppLocalizations.of(context)`, so they render whatever `Text('...')` literals their authors wrote in English.

## Architecture / Data Flow

**Codegen (build-time, not runtime):**
1. `app/l10n.yaml` configures `flutter gen-l10n`: `arb-dir: lib/l10n`, `template-arb-file: app_en.arb`, `output-class: AppLocalizations`, `output-dir: lib/l10n/generated`.
2. `app/pubspec.yaml:72` sets `generate: true`, which makes `flutter build`/`flutter run`/`flutter pub get` invoke `gen-l10n` automatically before compilation.
3. The generator reads `app/lib/l10n/app_en.arb` (template, 63 keys) and `app/lib/l10n/app_hi.arb` (63 keys, matching key set) and emits `app_localizations.dart` (abstract base + delegate), `app_localizations_en.dart`, and `app_localizations_hi.dart` into `app/lib/l10n/generated/`.

**Locale-switch flow (runtime), traced end to end:**
1. User opens Settings → Language row → `LanguageScreen` (`app/lib/features/settings/presentation/language_screen.dart`), which reads the current locale via `ref.watch(localeControllerProvider)` and renders a `RadioListTile` per entry in `supportedLocales` (`en`, `hi`).
2. Tapping an option calls `_select(code)` (`language_screen.dart:27-38`), which first no-ops if `code` already matches the current locale.
3. `_select` calls `ref.read(localeControllerProvider.notifier).setLocale(code)` (`app/lib/core/localization/locale_controller.dart:27-31`), which:
   a. Sets `state = Locale(code)` on the `Notifier<Locale>` — this is a synchronous Riverpod state update.
   b. Awaits `SharedPreferences.getInstance()` and writes the code under key `forma_locale`.
4. Because `app/lib/main.dart`'s `FormaApp.build()` does `final locale = ref.watch(localeControllerProvider);` and passes it to `MaterialApp.router(locale: locale, ...)` (`main.dart:20-30`), step 3a triggers an immediate rebuild of the whole `MaterialApp` subtree with the new `locale`. Flutter's `AppLocalizations.delegate` (registered in `localizationsDelegates`, `main.dart:31`) then re-resolves `AppLocalizations.of(context)` to `AppLocalizationsHi` (or `...En`) for every descendant on the very next frame — no explicit "reload strings" step is needed anywhere else in the app.
5. Back in `_select` (`language_screen.dart:32-36`), after the local switch, the screen calls `ref.read(authControllerProvider.notifier).updateProfile(locale: code)`. This flows through `AuthController.updateProfile` (`features/auth/presentation/auth_controller.dart:49-68`) → the auth repository → `PATCH /users/me` with `{"locale": code}` → `backend/app/api/v1/endpoints/users.py:19-29` (`update_current_user`), which loops `payload.model_dump(exclude_unset=True)` and `setattr`s each field onto the `User` ORM row (`backend/app/models/user.py:47`, `locale: Mapped[str] = mapped_column(String(8), default="en")`), then commits.
6. Any exception from step 5 (network failure, auth expiry, etc.) is caught and discarded in `language_screen.dart:33-36` — the local UI language from steps 3-4 is not reverted.
7. **Read-back gap (see Risks):** on a later app launch or a fresh login on a different device, `AuthController.build()` (`auth_controller.dart:15-31`) calls `repository.fetchMe()` (`GET /users/me`), which does populate the client-side `User.locale` field (`features/auth/domain/user.dart:142`) from the server — but nothing consumes that value to call `LocaleController.setLocale`. The only thing that seeds `LocaleController` on launch is its own `_restore()` reading local `SharedPreferences` (`locale_controller.dart:21-25`).

## Data / Schema

- **ARB source files:** `app/lib/l10n/app_en.arb` (template, `@@locale: "en"`) and `app/lib/l10n/app_hi.arb` (`@@locale: "hi"`), each with 63 flat string keys, no ICU plurals/selects, no placeholders/interpolation observed. Categories covered: intro carousel (3 slides × title/body + skip/getStarted/alreadyHaveAccount), auth (create-account title, sign-up/sign-in tabs, email/password labels, password-strength words, password requirement copy, buttons, verification notice, forgot-password link), tab bar (5 tab labels), Settings (screen title, 4 section headers, 15 row labels), onboarding (Continue/Skip-this-step/"nothing to report"/"Build my plan" + 10 step titles, including separate `step4LocationTitle` and `step4EquipmentTitle`).
- **Generated code:** `app/lib/l10n/generated/app_localizations.dart` (abstract `AppLocalizations` class + `LocalizationsDelegate`), `app_localizations_en.dart`, `app_localizations_hi.dart` (concrete per-locale getters). Regenerated by `flutter gen-l10n` on every build; not hand-edited.
- **Locale-controller state:** in-memory `Locale` (Riverpod `NotifierProvider<LocaleController, Locale>`, `app/lib/core/localization/locale_controller.dart:35`); persisted copy in `SharedPreferences` under string key `forma_locale`, storing the raw language code (`"en"` / `"hi"`).
- **Backend schema:** `users.locale` column, `String(8)`, `NOT NULL DEFAULT 'en'` (`backend/app/models/user.py:47`). Exposed read/write via `UserRead.locale` and `UserUpdate.locale` (`backend/app/schemas/user.py`), both optional-on-write (`str | None = None`) so a `PATCH /users/me` omitting `locale` leaves it untouched (`exclude_unset=True` semantics in `users.py:26`).

## Alternatives Considered

N/A — retroactive baseline.

## Testing Strategy

No automated tests found — gap. Searched `app/test` for any file or reference matching `AppLocalizations`, `LocaleController`, or `localeControllerProvider`; none exist. There is no widget test verifying that switching locale actually changes rendered text, no unit test on `LocaleController.setLocale`/`_restore`, and no backend test asserting `PATCH /users/me` persists `locale` (the broader `users` endpoint test suite, if any, was not in scope to re-verify here beyond confirming no l10n-specific test references exist client-side).

## Risks / Edge Cases

- **Cold-start locale flash:** `LocaleController.build()` returns `Locale('en')` synchronously and only overwrites it once the async `SharedPreferences` read in `_restore()` completes (`locale_controller.dart:14-19`). A user who previously chose Hindi can see a first frame (or first few frames) in English before the restored locale applies. No loading gate exists to hide this.
- **One-directional backend sync:** as traced in Architecture step 7, the backend's `User.locale` is written on every language-screen selection but never read back into `LocaleController` on login or app restart on a new device. The doc comment atop `LocaleController` (`locale_controller.dart:9-11`) states the choice is meant to "follow the user across devices too" — that claim is only half-true: it *saves* cross-device, it does not yet *restore* cross-device. This is a real functional gap, not just a documentation nit.
- **Silent PATCH failure:** by design (see requirements.md), a failed `updateProfile(locale:)` call is swallowed with an empty `catch (_) {}` (`language_screen.dart:33-36`). This is a deliberate UX choice (don't block the language switch on network), but it also means the account-level `locale` can silently drift out of sync with the device's actual displayed language with no retry, no error surfaced to the user, and no logging.
- **Partial localization within "localized" screens:** `settings_screen.dart` and `auth_screen.dart` both mix `AppLocalizations`-sourced labels with hardcoded English literals for dialogs, snackbars, and error banners (see requirements.md Out of Scope for exact strings/lines). A Hindi-selecting user will see a jarring mid-sentence language switch on these specific interactions (e.g. tapping delete-account gets an English "Cancel"/"OK" dialog inside an otherwise-Hindi Settings screen).
- **`supportedLocales` is a hard 2-element list** (`locale_controller.dart:5`); adding a third language requires code changes in that file plus new ARB files — there's no data-driven/remote locale list.

## Backlog / Known Gaps

- **Cross-device locale restore not implemented** — `backend/app/models/user.py:47`'s `locale` column is written via `PATCH /users/me` but never read back into `LocaleController` from `AuthController.build()`/`fetchMe()` (`app/lib/features/auth/presentation/auth_controller.dart:15-31`). A fix would apply `user.locale` to `localeControllerProvider` once `fetchMe()`/login resolves, if it differs from the locally-persisted value.
- **Hardcoded dialog/snackbar/error strings inside localized screens** — `settings_screen.dart` (Cancel/OK dialog buttons, "Could not save. Try again." snackbars, e.g. around `settings_screen.dart:247-270`) and `auth_screen.dart` (raw `_error!` text) are not ARB-backed. Not part of the 011 module's stated scope, but a natural next increment before claiming those two screens are "fully" localized.
- **No automated test coverage** for locale switching, persistence/restore, or backend `locale` persistence (see Testing Strategy).
- **Seven feature areas remain entirely unlocalized** (dashboard, workout, camera_coach, programs, progress, achievements, challenges) — this is the deliberate scope boundary documented in requirements.md, not treated here as a "gap" absent evidence it was meant to be broader; no TODO/FIXME comments or commit history point to a planned expansion (`git log` on `app/lib/l10n/`, `core/localization/`, and `language_screen.dart` shows only the single initial commit, `bc88e1f`).
- No other TODO/FIXME markers found in the localization-related files (`app/lib/l10n/`, `app/lib/core/localization/`, `language_screen.dart`).
