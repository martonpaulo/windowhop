# WindowHop architecture

Four layers, one direction of knowledge: UI and Input know the Core; the Core knows nothing
about AppKit or AX.

```
┌──────────── UI ────────────┐  SwitcherPanel + SwitcherTileView (AppKit),
│                            │  Settings/Onboarding (SwiftUI), ShortcutRecorderControl,
│                            │  StatusItemController
├────────── Input ───────────┤  EventTap (tap thread) → SwitcherController (main)
├────────── Engine ──────────┤  WindowStore ← AXNotificationRouter ← TrackedApp observers
│                            │  WindowActions, AccessibilityPermission, LoginItem
├─────────── App ────────────┤  AppDelegate lifecycle, UpdateManager (Sparkle)
└─────────── Core ──────────┘  SwitcherState, WindowEligibility, TabGroupResolver,
                                MRUOrder, TitleResolver, PersistentShortcut, Preferences,
                                TemporaryActivationSession (pure, unit-tested)
```

## Window model (event-driven, no polling)

1. `WindowStore.start()` KVO-observes `NSWorkspace.runningApplications`; each app gets a
   `TrackedApp` with one `AXObserver` (run-loop source on the dedicated AX events thread).
   Subscription retries handle apps that are still launching (ported from AltTab).
2. AX notifications land in `AXNotificationRouter` on the AX thread, hop to the serial
   AX reads queue for one batched attribute call (plus tab-group titles), then hand plain
   values to `WindowStore` on the main thread.
3. `WindowStore` keeps `[TrackedWindow]` in window-level MRU order (index 0 = focused).
   Identity is the `AXUIElement` itself (CFEqual-stable), so duplicate titles cannot
   collide. `snapshot()` applies eligibility + display rules and returns value items.
4. On `activeSpaceDidChange`, every app is re-enumerated: this discovers windows the
   public AX API hides until their Space is visited and refreshes each window's
   current-Space flag.

### Tabs are never entries

Native NSWindow tabs (Finder, Terminal, …) are real AX windows; only the visible tab
exposes the `AXTabGroup` child. `TabGroupResolver` (pure, ported from AltTab's
TabGroup.updateState) matches the reported tab titles against same-app windows and marks
inactive tabs `isTabbed`, which excludes them from display while keeping them tracked.
Safari-style browsers expose one AX window per browser window, so nothing matches and
each window simply carries its own tab count. Counts come only from counting
`AXTabButton` children — never guessed, never parsed from titles.

### The own-window exception

WindowHop's own pid is never tracked through AX, which keeps the panel, alerts,
onboarding, and helper surfaces out by construction. The single sanctioned exception is
the Settings window: `SettingsWindowController` registers its `NSWindow` with the store,
which creates a native-backed `TrackedWindow` (no AX). It participates in MRU via
`didBecomeKey`, hides while miniaturized, disappears on `willClose`, and activates/closes
through plain AppKit.

## Input

1. `EventTap` owns a consuming CGEvent tap (keyDown/keyUp/flagsChanged) on its own
   thread. The callback reads a lock-protected mode — `off`, `watching`, `sessionHeld`,
   `sessionSticky`, `passthrough` — and decides synchronously whether to consume;
   semantic events are posted to the main thread. `flagsChanged` is never consumed.
2. In `watching` it matches two chords: the switcher shortcut (modifier+Tab, Shift
   reverses) opening a **held** session, and the optional persistent shortcut
   (`PersistentShortcut`, exact modifier match) opening a **sticky** session.
3. `SwitcherController` (main) feeds events into the pure `SwitcherState` machine
   (phases: inactive → held/sticky → confirming) and executes the returned commands:
   show/select on the panel, activate/close via `WindowActions`, cancel.
4. `TemporaryActivationSession` keeps four identities separate: origin, targeted,
   temporarily active, and committed. The `Preferences` dwell preset is the single source
   of truth: Off disables temporary activation; Short, Default (700 ms), and Long schedule
   one cancellable session timer. Target changes replace the pending request, so an expired
   request can never raise a stale intermediate window. The store keeps
   processing AX events but freezes MRU history until the final target is committed;
   cancellation raises the exact origin again when it still exists.
5. The switcher list is **frozen at session start**; store changes while open only remove
   or refresh entries (nearby selection preserved), never reorder or add.
6. While a **held** session runs, a 0.5 s timer cross-checks `NSEvent.modifierFlags` to
   recover from missed key-up events. Sticky sessions have no such timer — modifier
   release means nothing there; only Return/Space/click/Escape end them.

## Presentation

Fixed-size tiles in one of two appearances (Settings → Appearance; changing it
applies on the next session, no restart):

- **App Icons** (default): a large application icon dominates a compact tile.
- **Window Previews**: an aspect-fit window snapshot with the app icon as a
  bottom-right badge overlapping the fixed preview canvas by the same amount on both
  edges. Until a preview arrives, a subtle labelled loading state remains inside that
  canvas; a failed first capture becomes a labelled unavailable state while the badge
  stays at the same corner. Every preview
  container shares the aspect ratio of the display the switcher is presented
  on, so all cards have identical dimensions; the snapshot centers inside with
  transparent letterboxing (whole window visible, never cropped or stretched),
  and carries a soft shadow whose path follows the preview's rounded shape.

Every tile keeps a 13 pt title and the reserved 11 pt tab-count line so nothing
shifts as data arrives (all dimensions from `UI/DesignTokens.swift`). Titles
wrap to two lines; a single-line title centers vertically in the same fixed
zone. Horizontal and vertical spacing each have one shared token; the latter separates
the complete card footprint, including overlays, title, and metadata. Preview states
share one outline implementation: subtle when unselected, restrained while hovered or
temporarily active, and one 4 pt AppKit semantic focus ring on the selected target that
replaces the neutral outline. App Icons has no neutral border and uses the native
switcher's soft rounded background for selected and hovered states. Selection surrounds
only the fixed content canvas
— the title stays outside — and every overlay is excluded from layout measurement.
Hovering a tile reveals an overlay close control (routed through the same
confirmation as ⌫; also a VoiceOver custom action). Its center equals the canvas's
top-left point; the scroll document reuses the panel's existing padding as a clip-safe,
hit-testable overflow gutter, so the card and panel do not grow. A compact Settings
control (⌘, works without a pointer) keeps most of its 44 pt target inside the panel and
10 pt outside its top-right corner. A transparent host preserves that outside area;
the control reserves no chrome row and cannot change the visible
panel's centering or dimensions. On macOS 26+ the panel
background is the system glass material (NSGlassEffectView, the native
switcher's look); older systems use the HUD visual-effect material. Tiles wrap
into **rows** when one row can't fit ~88 % of the screen width (the AltTab
layout model) — there is no horizontal scrolling and tiles never shrink; ←/→
step linearly while ↑/↓ move by one row. Only an extreme window count exceeds
the ~85 % height budget and falls back to vertical scrolling with the selection
kept visible. Tile views are pooled and reconfigured, so repeated opens and
live updates are single-digit milliseconds even with 100+ windows. System
materials and semantic colors handle Light/Dark, Increase Contrast, and Reduce
Transparency.

## Window previews

`PreviewProvider` (the only file allowed to touch ScreenCaptureKit — enforced by
`scripts/validate.sh`) captures tile-sized snapshots via `SCScreenshotManager`,
but only while a session is open, only in Window Previews mode, and only with
Screen Recording granted (requested the first time the user selects previews;
App Icons never needs it). The cache is memory-only and app-lifetime: opening
the switcher shows the last known snapshot of every window instantly. The
session recaptures in parallel waves of four and delivers every result live —
a tile that opened with a cached snapshot crossfades to the fresh capture the
moment it lands (constant geometry, no layout shift; Reduce Motion disables
the fade), and tiles that opened with none fill in. Captures are taken without
the system window shadow (`ignoreShadowsSingleWindow`); the tile draws its own
shadow along the preview's rounded clip. WindowHop's own Settings window is
captured too (own pid + converted frame). Entries are evicted the moment their
window disappears and when the user switches back to App Icons.

Captures finish asynchronously and out of order, so the pure, unit-tested
`PreviewLedger` decides what a late result may do: results for evicted windows
are discarded entirely, and results from an ended or superseded session may
still warm the cache but are never delivered live. Panel delivery is keyed by
the window's stable id — never by tile position — and pooled tiles reset their
image state on reconfigure, so a snapshot can never appear on another window's
card (regression-tested, including rapid list changes).

Source images aspect-fit and center inside a display-ratio canvas with transparent
letterboxing. The app badge, Close control, outline, selection indicator, shadow, hit testing,
and title position all anchor to that canvas rather than the fitted source-image bounds.

While a window has no snapshot, the tile shows a quiet “Loading preview…” state
(quaternary system fill) under the same corner-aligned app badge, and the first capture
fades in over it (Reduce Motion disables the fade). If acquisition, matching, or capture
fails and no cache exists, the same canvas changes to “Preview unavailable”; cached
previews are never replaced by a failure. Both paths keep constant geometry, with no
icon, outline, or title movement.

Matching AX windows to `SCWindow`s is a **unique assignment** (pid + frame first,
title as tiebreak, then exact title), so two windows of the same app can never
share a snapshot; a request with no confident match keeps the placeholder and badge —
a wrong preview is worse than none. Images are requested pre-scaled (no
full-resolution retention). Preview failure can never remove an entry or block
activation.

## Picture-in-Picture exclusion

PiP panels (browser PiP, native floating video) are never entries. AX cannot
tell them apart — a Chromium PiP window reports `AXStandardWindow` like a real
browser window — so detection is behavioral: the window server keeps PiP
floating above normal windows (nonzero `kCGWindowLayer`, public
`CGWindowListCopyWindowInfo` — bounds and layer need no capture permission).
The pure rule lives in `PictureInPictureDetector` (unit-tested): a floating
window is PiP unless it covers (almost) a whole screen — Keynote presentations
and fullscreen overlays stay listed. Each window's floating status is resolved
once, lazily, at snapshot time, and only when an unresolved on-screen window
exists — idle stays query-free.

## Stale-window pruning

A missed `kAXUIElementDestroyed` notification can leave a dead element tracked as
a phantom "other-Space window" (visible symptom: a duplicate entry). Dead elements
answer `.invalidUIElement` to any attribute read, so the store validates suspects
off the main thread — on Space changes (elements missing from `kAXWindows`) and on
every switcher open (the visible entries) — and removes the dead ones. Ported in
spirit from AltTab's missing-window checks on trigger (upstream `39070383`).

## Close, Quit, Force Quit

The confirmation dialog hides the switcher panel while it runs (so it is always on
top and keyboard-focused) and restores it afterwards with the previous selection.
Buttons: Cancel (default), Close Window (AX close button; the app's own
unsaved-changes flow runs), and Quit <App> (`NSRunningApplication.terminate()` —
never injected keystrokes). If a quit was already requested and the app still runs,
the offer escalates to "Force Quit <App>…", which opens a second, explicitly
destructive confirmation before `forceTerminate()`. WindowHop's own Settings entry
offers Cancel/Close only.

## Updates

`UpdateManager` wraps Sparkle 2's `SPUStandardUpdaterController` and only starts from a
real bundle (`com.perso.windowhop` with `SUFeedURL` present). As the updater
delegate it mirrors the latest found update version (`availableVersion`,
observable) so the Settings Updates pane can show "X.Y.Z is available" with an
install button; the standard Sparkle dialog still owns install / remind-later /
skip-this-version, so the same version never nags twice and a failed check
changes nothing. The appcast lives at
`https://raw.githubusercontent.com/martonpaulo/windowhop/main/appcast.xml`; archives are
EdDSA-signed (`SUPublicEDKey` embedded in Info.plist, private key in Keychain/CI secret).
Update checks are the app's only network activity.

Official tag builds are fail-closed: the workflow accepts only the current `main` commit,
requires an Apple-issued Developer ID Application identity plus Apple ID notarization
credentials, submits both the app archive and final DMG with `notarytool --wait`, staples
and validates both tickets, and runs `codesign` and Gatekeeper assessment before the
release or appcast can be published. Local packages may remain ad-hoc signed and skip
notarization explicitly.

## Public-API replacements for AltTab's private calls

| Concern | AltTab (private) | WindowHop (public) |
|---|---|---|
| Suppress native Cmd-Tab | `CGSSetSymbolicHotKeyEnabled` | consuming event tap; nothing to restore on quit/crash |
| Focus a window | `_SLPSSetFrontProcessWithOptions` + `SLPSPostEventRecordTo` | `kAXMainAttribute` + `kAXRaiseAction` + settable `kAXFrontmostAttribute`, then `NSRunningApplication.activate()` |
| Window identity | `_AXUIElementGetWindow` (CGWindowID) | the `AXUIElement` itself (CFEqual/CFHash) |
| Other-Space windows | `_AXUIElementCreateWithRemoteToken` brute force + `CGSCopySpaces*` | persistent store + re-enumeration on Space change (see limitation in README) |
| Tab-group siblings | CGWindowID matching | object-identity matching in pure `TabGroupResolver` |

## Fail-safe properties

- The native macOS switcher is never modified. Interception exists only while the tap is
  alive and consuming; disabled/quit/crash/permission-revoked ⇒ native behavior.
- Missing permission stops the tap entirely — the shortcut is never partially intercepted.
- `tapDisabledByTimeout/UserInput` events re-enable the tap in the callback; sleep/wake and
  session-switch notifications re-arm it from the app delegate.
- Modifier release is detected from event flags (covers left/right and both-held cases);
  the held-modifier guard covers missed events.

## Performance principles (inherited from AltTab)

- All AX IPC on background queues with a 1 s messaging timeout; the main thread only
  mutates state and draws.
- The tap callback does no allocation or IPC on the hot path.
- Idle = zero timers, zero polling; the app only reacts to OS events.
- View work is bounded: pooled tiles, no per-frame layout, no animations.
