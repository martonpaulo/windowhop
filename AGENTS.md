# WindowHop — rules for coding agents

## Build and validate

```sh
swift build && swift test        # must pass, zero warnings
swift build -c release
scripts/package-app.sh           # release .app + artifacts/WindowHop-release.zip
```

Runtime checks (Accessibility permission is inherited when run from a trusted terminal):

```sh
.build/debug/WindowHop --dump-windows           # real discovery works?
.build/debug/WindowHop --render-ui /tmp/shots   # UI renders correctly?
WINDOWHOP_DEBUG=1 .build/debug/WindowHop        # diagnose input/session behavior
```

Keep task logs in `artifacts/` (gitignored). Inspect a failed log before rerunning.

## Hard rules

- **Public Apple APIs only.** No private frameworks, no `_`-prefixed SPI, no
  `@_silgen_name`. AX attribute *strings* not in headers (e.g. `AXFullScreen`) are fine.
- **Never request Screen Recording.** No screenshots, thumbnails, or previews — ever.
- **No polling while idle.** Observe events (AXObserver, KVO, notifications). Bounded
  timers are allowed only while a session or the onboarding window is open.
- **The event-tap callback must stay tiny and synchronous** (`EventTap.handle`): decide
  consume/pass with plain comparisons, post to main, return. Never do AX/IO there.
- **Never consume `flagsChanged` events**, and never disable the native Cmd-Tab symbolic
  hotkey. Fail-safe = if WindowHop dies, native switching works untouched.
- **No new dependencies, no telemetry, no network code, no Pro/license/update code.**
- Closing a window always goes through the confirmation dialog (Cancel is default).

## Architecture (see docs/architecture.md)

- `Core/` — pure logic, no AppKit/AX imports beyond value types. All business rules live
  here (eligibility, MRU, title fallback, session state machine, settings defaults).
  New behavior rules go here **with unit tests**.
- `Engine/` — AX integration: `TrackedApp`/`TrackedWindow`, `WindowStore` (main-thread
  source of truth), `AXNotificationRouter` (AX thread → reads queue → main).
- `Input/` — `EventTap` (tap thread) and `SwitcherController` (main-thread orchestration).
- `UI/` — AppKit switcher panel; SwiftUI Settings/onboarding.

Threading: AX reads/actions on `BackgroundWork` queues, never the main thread; state
mutation and UI on main only.

## Conventions

- Conventional Commits; English everywhere.
- Comments state constraints the code can't show (ported-rule provenance, macOS quirks).
- GPL-3.0 with AltTab attribution is non-negotiable; update UPSTREAM.md when porting
  upstream rules (include the upstream commit hash).
