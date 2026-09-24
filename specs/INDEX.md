# FORMA — Spec Catalog

Retroactive baseline specs for FORMA, an AI-coached strength-training app
(Flutter client + FastAPI/Postgres backend). All 13 modules below are
**Retroactive Baseline** specs, dated 2026-09-10 — they document behavior
as implemented, grounded in code actually read at that time, not
aspirational design. See [SPEC_DRIVEN_DEVELOPMENT.md](../SPEC_DRIVEN_DEVELOPMENT.md)
for the full process this catalog follows.

New work starts at **014**.

## Modules

| # | Module | Description | Spec |
|---|--------|-------------|------|
| 001 | auth-identity | Register/login/session/logout, password reset, change password/email | [requirements.md](001-auth-identity/requirements.md) |
| 002 | onboarding | 9-step signup quiz → equipment/goals/injuries → triggers first plan generation | [requirements.md](002-onboarding/requirements.md) |
| 003 | programs-plan-exercises | Program/day/exercise structure, exercise catalog, AI (Groq) + deterministic plan generation, day editor | [requirements.md](003-programs-plan-exercises/requirements.md) |
| 004 | dashboard-today | The Today tab — home screen aggregating active plan/workout/recovery state | [requirements.md](004-dashboard-today/requirements.md) |
| 005 | workout-tracking | Active workout session logging — manual set entry and camera-coached flow | [requirements.md](005-workout-tracking/requirements.md) |
| 006 | camera-coach | On-device real-time pose detection, heuristic rep/form scoring, TTS voice coaching | [requirements.md](006-camera-coach/requirements.md) |
| 007 | progress-analytics | Volume/consistency/form-quality/recovery analytics, personal records | [requirements.md](007-progress-analytics/requirements.md) |
| 008 | achievements | Badges, XP/leveling, the Profile tab landing screen | [requirements.md](008-achievements/requirements.md) |
| 009 | challenges | Weekly/monthly/ongoing challenges, streaks, leaderboard | [requirements.md](009-challenges/requirements.md) |
| 010 | settings-profile-premium | Settings, notification prefs, voice-coach settings, premium/IAP | [requirements.md](010-settings-profile-premium/requirements.md) |
| 011 | localization-i18n | English/Hindi ARB-based i18n, locale switching | [requirements.md](011-localization-i18n/requirements.md) |
| 012 | uploads-media | Generic backend image-upload endpoint + static file serving | [requirements.md](012-uploads-media/requirements.md) |
| 013 | engineering-infrastructure | DI, networking, routing, persistence, design system, backend core, deployment (architecture reference) | [requirements.md](013-engineering-infrastructure/requirements.md) |

## Notable findings

Surfaced while writing these specs — documentation-only, nothing here has
been fixed. Ordered roughly by severity.

### Security

- **CORS is wildcard in the committed production config, combined with
  credentialed requests.** `render.yaml` pins `CORS_ORIGINS` to `["*"]`
  and `backend/app/main.py` sets `allow_credentials=True`. Because
  Starlette's CORS middleware reflects the request's actual `Origin`
  rather than a literal `*` whenever credentials are allowed, any origin
  can currently make credentialed requests against the deployed API. Live,
  not hypothetical. (`013-engineering-infrastructure`)
- `Settings.secret_key` (JWT signing key) defaults to the literal string
  `"change-me-in-.env"` with no startup check forcing a real value outside
  Render's dashboard-managed `sync: false` mechanism — a misconfigured
  non-Render deploy would boot fine with a known signing key.
  (`013-engineering-infrastructure`)
- No refresh-token flow or server-side revocation — a leaked JWT stays
  valid for the full 24h default expiry regardless.
  (`013-engineering-infrastructure`)
- Registration has no server-side password-length validation (only the
  Flutter client enforces 8 chars), while password-reset and
  change-password both correctly enforce it server-side. A non-app client
  could register a 1-character password. (`001-auth-identity`)

### Real bugs

- **"✨ Let AI fill this day" doesn't call the AI.** It uses the same
  deterministic heuristic as the non-AI plan generator — zero Groq calls
  despite the UI copy. (`003-programs-plan-exercises`)
- **Locale sync is one-directional.** Selecting a language correctly
  PATCHes it to the backend, but the client never reads `User.locale`
  back to restore it on another device, contradicting `LocaleController`'s
  own doc comment that it "follows the user across devices."
  (`011-localization-i18n`)
- Challenge windowed progress (`_period_bounds()`) is computed against the
  *current* time rather than each user's stored `period_start`, so
  progress always floats to the live current week/month — `period_start`
  is effectively write-only. (`009-challenges`)
- `completed_at` on a challenge is never cleared when its period rolls
  over, so stale "completed" styling can persist while the live progress
  bar shows a lower value. (`009-challenges`)
- Per-set RPE exists end-to-end in the backend schema/model but the
  active-workout UI never passes it when logging a set — only
  session-level RPE (via the summary screen) is reachable.
  (`005-workout-tracking`)

### Dead code / unused features

- **`backend/app/api/v1/endpoints/uploads.py` is fully built and mounted
  but has zero callers anywhere in the Flutter client** — `image_picker`
  is a declared dependency with no usages at all. Almost certainly a
  leftover from the pre-pivot "memory-keeping" app. (`012-uploads-media`)
- **The `BodyMetric` model/table exists in the schema with zero
  consumers** — no endpoint, no service, no Flutter code. Body-weight
  history tracking is modeled but entirely unimplemented.
  (`007-progress-analytics`)
- `Program.source` (would indicate AI-personalized vs. deterministic
  fallback) is parsed into the Flutter model but never displayed anywhere
  — users can't tell which generation path produced their plan.
  (`003-programs-plan-exercises`)
- Achievement/PR-count "leveling" (`domain/leveling.dart`) is a
  client-only invented mechanic with no backend counterpart; the
  100-XP-per-level curve is explicitly a placeholder per its own code
  comment. (`008-achievements`)
- The one "secret" achievement has no real hidden title — its seeded
  title/description are literally `"???"` / `"Keep training to find
  out."`, so the reveal-on-unlock UI changes nothing visible.
  (`008-achievements`)
- `ios/Podfile`'s iOS 15.5 deployment-target comment cites
  `google_mlkit_commons`, which isn't a dependency anywhere in the app —
  leftover from a pre-MediaPipe prototype. (`006-camera-coach`)
- `RepResult`'s tempo fields are computed every rep but never read
  downstream. (`006-camera-coach`)
- Dead `UserLogin` Pydantic schema — `/auth/login` actually takes
  `OAuth2PasswordRequestForm`. (`001-auth-identity`)
- The Today screen's notification bell is a no-op (`onPressed: () {}`),
  and its rest-day mobility button shows a permanent "Coming soon."
  snackbar. (`004-dashboard-today`)
- `notification_prefs.challenge_updates` is stored on `User` but there is
  no notification-sending service anywhere in the backend to consume it.
  (`009-challenges`, `010-settings-profile-premium`)

### Testing

- **No automated tests exist anywhere in the repo beyond a single,
  currently-broken Flutter widget test.** `app/test/widget_test.dart`
  asserts text (`'Welcome back'`) that appears nowhere in the app and a
  route a signed-out cold start never reaches. `backend/` has no `tests/`
  directory, no pytest config, and no CI workflow at all. This applies to
  every module in this catalog and is called out individually in each
  module's `design.md` Testing Strategy section. (`001-auth-identity`,
  `013-engineering-infrastructure`, and all others)

### UX inconsistencies (non-bugs, worth knowing)

- IAP (`premium_screen.dart`) and notification prefs are honestly-scoped,
  labeled stubs — not faked functionality. Voice-coach voice selection is
  cosmetic only (persists a choice that never changes what `flutter_tts`
  actually speaks). (`010-settings-profile-premium`)
- Recovery/"Progress" screens have dead "no training data yet" UI
  branches that can never trigger, because the backend's recovery
  calculation always returns all 10 muscle groups. Two different
  "fully recovered" thresholds (`>=100` vs. `>=85`) are used in two
  adjacent screens. (`007-progress-analytics`)
- Onboarding quiz state is held only in memory (no local persistence) —
  an app kill mid-quiz loses all progress. Split/day-compatibility rules
  are duplicated, in sync but with no shared source of truth, across two
  files. (`002-onboarding`)
