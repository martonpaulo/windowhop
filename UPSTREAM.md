# Upstream: AltTab

WindowHop is derived from **AltTab** — <https://github.com/lwouis/alt-tab-macos> —
by Louis Pontoise (lwouis) and contributors, licensed GPL-3.0.

## Base revision

- Tag: `v10.12.0`
- Commit: `317a485bcb090bf2b29e3f78872218f0099e1d62`
- Why this one: it is the last stable tag before the Pro/licensing/trial code introduced
  in `v11.0.0` (`9147a4a8`, "feat: introducing alt-tab pro!"), and the last release whose
  engine is Accessibility-based. v11.x reworked window tracking onto private SkyLight/CGS
  WindowServer APIs (`SLSRegisterNotifyProc` etc.), which WindowHop's public-API-only rule
  excludes.

The full upstream history up to that commit is preserved in this repository
(`git log 317a485b` and earlier). The `upstream` remote points at the original project.

## Retained (ported into new sources, same GPL license)

| Upstream (v10.12.0) | WindowHop | What was kept |
|---|---|---|
| `src/logic/WindowDiscriminator.swift` | `Core/WindowEligibility.swift` | window vs non-window rules incl. app-specific quirks |
| `src/logic/Window.swift` (`bestEffortTitle`) | `Core/TitleResolver.swift` | title fallback order |
| `src/logic/Windows.swift` (`updateLastFocusOrder`) | `Core/MRUOrder.swift` | window-level MRU semantics |
| `src/logic/Application.swift` | `Engine/TrackedApp.swift` | per-app AXObserver, launch-readiness retry pattern |
| `src/logic/events/AccessibilityEvents.swift` | `Engine/AXNotificationRouter.swift` | notification routing, batched attribute reads |
| `src/api-wrappers/AXUIElement.swift` | `Engine/AXHelpers.swift` | batched attributes, safe casting, subscription semantics, tab-group counting |
| `src/logic/TabGroup.swift` | `Engine/AXHelpers.swift` (`tabCount`) | AXTabGroup/AXTabButton tab detection |
| `src/logic/events/KeyboardEvents.swift` | `Input/EventTap.swift` | tap re-enable on `tapDisabledBy*`, dedicated input thread |
| `src/logic/BackgroundWork.swift` | `Engine/BackgroundWork.swift` | dedicated run-loop threads, AX off the main thread |
| `src/logic/events/RunningApplicationsEvents.swift` | `Engine/WindowStore.swift` | KVO on `NSWorkspace.runningApplications` |
| `src/logic/SystemPermissions.swift` | `Engine/AccessibilityPermission.swift` | permission gating; polling reduced to onboarding-window-only |
| Window/screen coordinate conversion (`Window.isOnScreen`) | `Engine/TrackedWindow.swift` | Quartz↔Cocoa frame conversion |

## Removed

- Pro/licensing/trial/upgrade code (never present in v10.12.0; the base was chosen for that).
- Window previews, thumbnails, ScreenCaptureKit/screen capture, Screen Recording permission.
- Search/typing filter, trackpad/scrollwheel gestures, drag-and-drop onto tiles,
  window tiling hooks, app launching, Dock/context-menu integrations.
- Sparkle (updates), AppCenter (crash telemetry), SwiftyBeaver (logging), LetsMove,
  ShortcutRecorder — all third-party dependencies. WindowHop has zero dependencies.
- All private API usage:
  - `CGSSetSymbolicHotKeyEnabled` (disabling native Cmd-Tab) → replaced by a consuming
    CGEvent tap, which is fail-safe by construction.
  - `_SLPSSetFrontProcessWithOptions` / `SLPSPostEventRecordTo` (focus) → replaced by
    AX raise + settable `kAXFrontmostAttribute` + `NSRunningApplication.activate()`.
  - `_AXUIElementGetWindow`, `_AXUIElementCreateWithRemoteToken` (window ids, brute-force
    discovery) → replaced by AXUIElement identity plus re-enumeration on Space changes.
  - `CGSCopySpaces*` and Spaces bookkeeping → replaced by a per-window current-Space flag
    maintained from public enumeration.
- Localization files (first release is English), preferences UI framework (~40 settings
  reduced to 8), update/feedback/crash windows, CI/release tooling, CocoaPods.

## Evaluating upstream fixes later

1. `git fetch upstream` and review `git log upstream/master -- src/` since `v10.12.0`.
2. Only consider areas WindowHop kept: eligibility quirks (`WindowDiscriminator`/
   `WindowFilterResolver`), title/tab detection, AX subscription robustness, permission
   handling. Ignore fixes for previews, search, gestures, Pro, updates, and the v11
   WindowServer engine (private APIs).
3. Port the *rule*, not the code: add it to the matching WindowHop file with a test where
   feasible, and note the upstream commit hash in the commit message.
