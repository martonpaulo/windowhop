# WindowHop — rules for coding agents

## Build and validate

```sh
swift build && swift test        # must pass, zero warnings
scripts/validate.sh              # repository invariants (must pass)
scripts/package-app.sh [ver] [build]  # release .app with Sparkle embedded + zip
scripts/make-dmg.sh [ver]        # DMG (expects build/WindowHop.app)
```

Runtime checks (Accessibility permission is inherited when run from a trusted terminal):

```sh
.build/debug/WindowHop --dump-windows           # real discovery works?
.build/debug/WindowHop --render-ui /tmp/shots   # switcher + settings renders, light/dark/overflow
.build/debug/WindowHop --demo-switcher [--dark] [--many]  # on-screen panel demo
.build/debug/WindowHop --updater-e2e <feed-url> # headless Sparkle end-to-end (see docs/testing.md)
WINDOWHOP_DEBUG=1 .build/debug/WindowHop        # diagnose input/session behavior
```

Keep task logs in `artifacts/` (gitignored). Inspect a failed log before rerunning.

## Hard rules

- **Public Apple APIs only.** No private frameworks, no `_`-prefixed SPI, no
  `@_silgen_name`. AX attribute *strings* not in headers (e.g. `AXFullScreen`) are fine.
- **Screen Recording is opt-in only**: ScreenCaptureKit may be used exclusively in
  `Engine/PreviewProvider.swift` (validate.sh enforces this), only during an open
  session in Window Previews mode, never idle-capturing, never persisting images.
  App Icons mode (the default) must always work without the permission.
- **No polling while idle.** Observe events (AXObserver, KVO, notifications). Bounded
  timers are allowed only while a session or the onboarding window is open.
- **The event-tap callback must stay tiny and synchronous** (`EventTap.handle`): decide
  consume/pass with plain comparisons, post to main, return. Never do AX/IO there.
- **Never consume `flagsChanged` events**, and never disable the native Cmd-Tab symbolic
  hotkey. Fail-safe = if WindowHop dies, native switching works untouched.
- **One entry per top-level window; tabs are never entries** (see TabGroupResolver).
  The own-process exclusion has exactly one exception: the registered Settings window.
- **Sparkle is the only runtime dependency**, and update checks are the only permitted
  network activity. No telemetry, no analytics, no accounts, no Pro/license code.
- The bundle identifier is `com.perso.windowhop` — everywhere, always.
- Closing a window always goes through the confirmation dialog (Cancel is default);
  Quit is graceful termination only; Force Quit requires its own second confirmation.
- Icon size is fixed Large; the only appearance options are App Icons (default) and
  Window Previews; system Light/Dark only. No other presentation settings.
- All shortcut strings render through `Core/ShortcutFormatter` — never hardcode a
  second representation of the same key.
- All UI dimensions come from `UI/DesignTokens.swift` — no hardcoded sizes,
  insets, radii, or font sizes in views.
- Official releases are signed with one stable Apple-issued Developer ID Application
  identity (`DEVELOPER_ID_CERT_P12`), notarized and stapled, so the TCC Accessibility
  grant survives updates — never ship ad-hoc, self-signed, or unnotarized releases.

## Architecture (see docs/architecture.md)

- `Core/` — pure logic, no AppKit/AX imports beyond value types. All business rules live
  here (eligibility, MRU, title fallback, tab-group resolution, PiP detection,
  preview-result ledger, session state machine, shortcut model, settings defaults).
  New behavior rules go here **with unit tests**.
- `Engine/` — AX integration: `TrackedApp`/`TrackedWindow`, `WindowStore` (main-thread
  source of truth), `AXNotificationRouter` (AX thread → reads queue → main).
- `Input/` — `EventTap` (tap thread; modes off/watching/sessionHeld/sessionSticky/
  passthrough) and `SwitcherController` (main-thread orchestration).
- `UI/` — AppKit switcher panel (horizontal large-icon tiles, pooled); SwiftUI
  Settings/onboarding; native shortcut recorder.
- `App/` — lifecycle and `UpdateManager` (Sparkle; only starts from a real bundle).

Threading: AX reads/actions on `BackgroundWork` queues, never the main thread; state
mutation and UI on main only.

## Sessions

Two explicit session modes share one pure state machine (`SwitcherState`):
- **held** (`⌘Tab`): modifier release activates; guarded by a session-scoped timer.
- **sticky** (`Open WindowHop` shortcut, or after a close confirmation): modifier
  release is meaningless; Return/Space/click/Escape end it.
Fixing one mode must not silently change the other — both are covered by tests.

## User-facing feature defaults and configurability

For every new user-facing behavior or presentation feature:

- Explicitly define its default value.
- Decide whether it should be configurable by the user and record that decision in
  implementation notes or product documentation.
- Prefer a Settings option when both enabled and disabled states are legitimate user
  preferences.
- Do not add settings for bug fixes, security behavior, internal implementation details,
  mandatory accessibility behavior, or features with only one valid outcome.
- Store defaults in `Core/Preferences.Defaults`. Do not duplicate fallback values in
  views, services, tests, shortcut registration, or migration code.
- Persist configurable preferences through the existing typed `Preferences.Key`
  infrastructure and keep `Preferences` as the runtime source of truth.
- Preserve existing user choices during upgrades; migration may change a stored value
  only when the old representation is obsolete or invalid.
- Add every configurable preference to `Preferences.configurableKeys` so Restore Defaults
  picks it up. Reset must not change permissions, identity, build metadata, caches, or
  non-preference user data.
- Add default, migration, persistence, runtime-update, and reset coverage as applicable.
- Update the Settings-related pull-request checklist whenever this contract evolves.

Features that are intentionally non-configurable must say why in the task implementation
notes. A missing configurability decision is a review failure.

## Conventions

- Conventional Commits; English everywhere.
- Comments state constraints the code can't show (ported-rule provenance, macOS quirks).
- GPL-3.0 with AltTab attribution is non-negotiable; update UPSTREAM.md when porting
  upstream rules (include the upstream commit hash).
- Release flow: tag `vX.Y.Z` → `.github/workflows/release.yml` (or local scripts);
  the Sparkle private key lives in the Keychain and the `SPARKLE_PRIVATE_KEY` GitHub
  secret — never in the repository or logs.

## Imported Claude Cowork project instructions
