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
| `src/logic/TabGroup.swift` | `Core/TabGroupResolver.swift` + `Engine/AXHelpers.swift` (`tabTitles`) | AXTabGroup/AXTabButton detection; tab-sibling resolution so tabs never become entries |
| `src/logic/events/KeyboardEvents.swift` | `Input/EventTap.swift` | tap re-enable on `tapDisabledBy*`, dedicated input thread |
| `src/logic/BackgroundWork.swift` | `Engine/BackgroundWork.swift` | dedicated run-loop threads, AX off the main thread |
| `src/logic/events/RunningApplicationsEvents.swift` | `Engine/WindowStore.swift` | KVO on `NSWorkspace.runningApplications` |
| `src/logic/SystemPermissions.swift` | `Engine/AccessibilityPermission.swift` | permission gating; polling reduced to onboarding-window-only |
| Window/screen coordinate conversion (`Window.isOnScreen`) | `Engine/TrackedWindow.swift` | Quartz↔Cocoa frame conversion |
| `src/logic/Screens.swift` (`withMouse()`, `uuid()`) | `Engine/DisplayRegistry.swift` | pointer-display detection via `NSMouseInRect`; stable display identity via `CGDisplayCreateUUIDFromDisplayID` with the nil checks those implicitly-unwrapped APIs actually need; the documented unreliability of `NSScreen.main` |

## Removed

- Pro/licensing/trial/upgrade code (never present in v10.12.0; the base was chosen for that).
- Window previews, thumbnails, ScreenCaptureKit/screen capture, Screen Recording permission.
- Search/typing filter, trackpad/scrollwheel gestures, drag-and-drop onto tiles,
  window tiling hooks, app launching, Dock/context-menu integrations.
- AppCenter (crash telemetry), SwiftyBeaver (logging), LetsMove, ShortcutRecorder —
  third-party dependencies. Sparkle was initially removed too, then reintroduced
  cleanly via Swift Package Manager as WindowHop's only dependency (updates only;
  WindowHop's shortcut recorder is its own small AppKit control).
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

## Consulting the upstream when planning

Check AltTab **before planning any issue that touches window discovery, screens, input,
focus, permissions, or AX behavior**. It shipped these problems years ago and its source
records macOS quirks that Apple's documentation does not.

The base revision's full tree is in this repository, so no network or checkout is needed:

```sh
git show 317a485b:src/logic/Screens.swift        # read one upstream file
git grep -l -i "<term>" 317a485b -- src          # find where upstream handles something
```

What to do with what you find:

- **A quirk or workaround** — port the *rule* into the matching WindowHop file with a comment
  naming the constraint, and add a row to the Retained table below.
- **A feature WindowHop removed on purpose** — leave it removed. The Removed list is a set of
  decisions, not a backlog.
- **A different default** — note it in the issue and let the owner decide. AltTab's default is
  evidence, not authority.

Record ported rules in the Retained table and cite the upstream commit hash in the commit
message. Never copy code verbatim without checking it still applies to a public-API-only,
AX-based engine.

## Evaluating upstream fixes later

1. `git fetch upstream` and review `git log upstream/master -- src/` since `v10.12.0`.
2. Only consider areas WindowHop kept: eligibility quirks (`WindowDiscriminator`/
   `WindowFilterResolver`), title/tab detection, AX subscription robustness, permission
   handling. Ignore fixes for previews, search, gestures, Pro, updates, and the v11
   WindowServer engine (private APIs).
3. Port the *rule*, not the code: add it to the matching WindowHop file with a test where
   feasible, and note the upstream commit hash in the commit message.
