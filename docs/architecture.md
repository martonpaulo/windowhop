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
                                MRUOrder, TitleResolver, PersistentShortcut, Preferences
                                (pure, unit-tested)
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
4. The switcher list is **frozen at session start**; store changes while open only remove
   or refresh entries (nearby selection preserved), never reorder or add.
5. While a **held** session runs, a 0.5 s timer cross-checks `NSEvent.modifierFlags` to
   recover from missed key-up events. Sticky sessions have no such timer — modifier
   release means nothing there; only Return/Space/click/Escape end them.

## Presentation

Fixed-size tiles in one of two appearances (Settings → Appearance; changing it
applies on the next session, no restart):

- **App Icons** (default): a 96 pt application icon dominates a 136×176 tile.
- **Window Previews**: an aspect-fit window snapshot in a 220×186 tile with the app
  icon as a corner badge on the fitted image; until a preview arrives (or when one
  is unavailable) the large icon shows instead — never a blank tile.

Every tile keeps a 13 pt title and the reserved 11 pt tab-count line so nothing
shifts as data arrives. Selection is a neutral rounded rectangle like the native
switcher. Hovering a tile reveals an overlay close control (routed through the same
confirmation as ⌫; also a VoiceOver custom action); hovering the panel reveals a
Settings control (⌘, works without a pointer). Tiles wrap into **rows** when one
row can't fit ~88 % of the screen width (the AltTab layout model) — there is no
horizontal scrolling and tiles never shrink; ←/→ step linearly while ↑/↓ move by
one row. Only an extreme window count exceeds the ~85 % height budget and falls
back to vertical scrolling with the selection kept visible. Tile views are pooled
and reconfigured, so repeated opens and live updates are single-digit milliseconds
even with 100+ windows. System materials and semantic colors handle Light/Dark,
Increase Contrast, and Reduce Transparency.

## Window previews

`PreviewProvider` (the only file allowed to touch ScreenCaptureKit — enforced by
`scripts/validate.sh`) captures tile-sized snapshots via `SCScreenshotManager`,
but only while a session is open, only in Window Previews mode, and only with
Screen Recording granted (requested the first time the user selects previews;
App Icons never needs it). The cache is memory-only and app-lifetime (the AltTab
model): opening the switcher shows the last known snapshot of every window
instantly, while the session recaptures in parallel waves of four and crossfades
in any changed snapshot (Reduce Motion disables the fade). Entries are evicted
the moment their window disappears and when the user switches back to App Icons.

Matching AX windows to `SCWindow`s is a **unique assignment** (pid + frame first,
title as tiebreak, then exact title), so two windows of the same app can never
share a snapshot; a request with no confident match keeps the icon fallback —
a wrong preview is worse than none. Images are requested pre-scaled (no
full-resolution retention). Preview failure can never remove an entry or block
activation.

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
real bundle (`com.perso.windowhop` with `SUFeedURL` present). The appcast lives at
`https://raw.githubusercontent.com/martonpaulo/windowhop/main/appcast.xml`; archives are
EdDSA-signed (`SUPublicEDKey` embedded in Info.plist, private key in Keychain/CI secret).
Update checks are the app's only network activity.

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
