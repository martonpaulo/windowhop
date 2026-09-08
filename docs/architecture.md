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
                                ExpandedPreviewSession (pure, unit-tested)
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
4. `ExpandedPreviewSession` owns only targeted and expanded identities. The `Preferences`
   delay is the single source of truth: Off, 1, 2, 3 (default), or 5 seconds. Target
   changes cancel the one session-scoped timer and invalidate its generation, so an
   expired request can never display stale content. Settling presents the latest snapshot
   inside WindowHop; it never calls the AX activation/raise path or changes MRU. Only the
   state machine's final confirm command activates the selected real window. Cancellation
   performs no desktop action because navigation never changed the desktop.
5. While a session is open the list is **reconciled, not reordered**: surviving eligible
   entries keep their session order, entries that disappear are removed in place (nearby
   selection preserved), and newly eligible windows are appended in fresh-store order —
   session `[A, B]` with a fresh store of `[C, B, A]` becomes `[A, B, C]`. The selected
   window's identity is preserved whenever it survives. An entry that briefly loses its
   location metadata while Spaces update is retained rather than removed, which is distinct
   from appending a new one (`Core/SessionListReconciler.swift`, and
   `SwitcherController.shouldPreserveAcrossLocationRefresh`).
6. While a **held** session runs, a 0.5 s timer cross-checks `NSEvent.modifierFlags` to
   recover from missed key-up events. Sticky sessions have no such timer — modifier
   release means nothing there; only Return/Space/click/Escape end them.

## Placement across displays

Where the panel is drawn is display *behavior*, not appearance, and is owned by three
pieces with one responsibility each:

- `Core/PanelPlacement.swift` — the pure rule. `PanelDisplayResolver` maps
  (placement preference, chosen display, connected displays, pointer display) to the
  ordered target set, and every fallback lives here: a chosen display that is not
  connected resolves to the pointer display, and the result is never empty while any
  display exists. `SwitcherGridCapacity` owns the grid math both a single panel and a
  mirrored group need.
- `Engine/DisplayRegistry.swift` — the only code touching `NSScreen`/CoreGraphics.
  Displays are read live at session start, so nothing is cached and nothing observes
  them while WindowHop is idle. Identity is the display UUID rather than
  `CGDirectDisplayID`, which is reassigned across reconnects. `NSScreen.main` is
  deliberately unused: it misreports the active screen with a fullscreen app or when
  `screensHaveSeparateSpaces` is off (see `UPSTREAM.md`).
- `UI/SwitcherPanelGroup.swift` — one `SwitcherPanel` per target display, presenting
  the same command surface `SwitcherController` used against a single panel. Callbacks
  are index-based, so which panel a click came from never reaches the controller.

Mirrored panels are identical by construction. They share one grid derived from the
most constrained target display, because `SwitcherState` tracks a single column count
for arrow navigation and per-display grids would make ↑/↓ mean different things
depending on which display the user is looking at. One capture per window feeds every
panel, sized for the sharpest target scale, so mirroring does not multiply
ScreenCaptureKit work.

`Include windows from other displays` is a different concern with a different owner:
it decides which *windows* are listed, through `WindowInclusionPolicy`, and is
unaffected by placement.

## Presentation

Fixed-size tiles in one of two appearances (Settings → Appearance; changing it
applies on the next session, no restart):

- **App Icons** (default): a large application icon dominates a compact tile.
- **Window Previews**: an aspect-fit window snapshot with the app icon as a
  bottom-right badge overlapping the fixed preview canvas by the same amount on both
  edges. Every canvas is the same fixed 16:10 shape
  (`DesignTokens.previewCanvasAspect`), so the snapshot can center and aspect-fit
  without cropping or distortion. The canvas deliberately ignores the monitor:
  deriving it from the display made every card a shallow strip on an ultrawide
  screen. Unused space is an intentional semantic
  surface rather than transparent letterboxing. Loading, permission-required, failure,
  and loaded content all reuse that surface, geometry, badge anchor, and corner radius.

Every tile keeps a 13 pt title and the reserved 11 pt tab-count line so nothing
shifts as data arrives (all dimensions from `UI/DesignTokens.swift`). Titles
wrap to two lines; a single-line title centers vertically in the same fixed
zone. Horizontal and vertical spacing each have one shared token; the latter separates
the complete card footprint, including overlays, title, and metadata. Unselected previews
use the semantic surface and a shallow rounded shadow instead of a permanent gray frame.
Selected and hovered states use one rounded background plate derived from AppKit's
appearance-aware keyboard focus color; no neutral border remains underneath it. App Icons
has no border and uses the native switcher's soft rounded background for selection and
hover. Selection surrounds only the fixed content canvas
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
Screen Recording granted. `ScreenRecordingPermission` classifies permission before the
provider emits a loading state, so unavailable authorization never starts capture or a
retry loop. One panel-level action requests a not-determined grant or opens the correct
Privacy & Security pane; cards never duplicate that action. App activation refreshes the
status after the user returns from System Settings. App Icons never needs this permission.
The cache is memory-only and app-lifetime: opening
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

Accessibility and the window server describe the same window with different data, so
`PreviewMatcher` (pure, unit-tested, in `Core/`) pairs them. Titles disagree by design —
Chromium reports `Page – Brave – Profile` through AX while the window server knows only
`Page` — and frames agree exactly but are not unique, because same-size, stacked, zoomed,
and full-screen windows of one app share a frame and every app also owns invisible helper
windows. Each pair is therefore scored on pid, frame agreement, and a
decoration-tolerant title comparison, and is accepted only when it is the unambiguous best
choice for both sides. Settling the certain pairs frees candidates and can resolve a
window that was ambiguous a moment earlier; whatever stays ambiguous — same app, same
frame, same title — is left unassigned, so the tile keeps its placeholder instead of
showing another window's content.

Source images aspect-fit and center inside that fixed 16:10 canvas over the semantic
preview surface. The app badge, Close control, selection plate, shadow, hit testing, and
title position all anchor to that canvas rather than the fitted source-image bounds.

While an authorized window has no snapshot, the tile shows a simplified macOS-window
skeleton with a quiet pulse; Reduce Motion makes it static. Missing or revoked permission
uses the same geometry as a subdued, non-animating fallback while the single panel-level
recovery action remains available. Acquisition, matching, or capture failure also uses a
static skeleton, without exposing technical copy. A cached snapshot is never replaced by
an ordinary capture or permission failure. All paths keep constant geometry and selection,
with no badge, surface, or title movement.

After the configured dwell, `SwitcherController` asks the provider for a current snapshot
of the selected id and presents it in `ExpandedPreviewView`. Both the dwell request and
asynchronous result carry session/target generations; navigating or closing invalidates
them. This path is snapshot-only and has no reference to `WindowActions.activate`.

Matching AX windows to `SCWindow`s is a **unique assignment** (pid + frame first,
title as tiebreak, then exact title), so two windows of the same app can never
share a snapshot; a request with no confident match keeps the placeholder and badge —
a wrong preview is worse than none. Images are requested pre-scaled (no
full-resolution retention). Preview failure can never remove an entry or block
activation.

## Shared window-inclusion policy

`Preferences.windowInclusionPolicy` is the single value passed to
`WindowEligibility.shouldDisplay`, so discovery, session snapshots, navigation, previews,
and tests cannot disagree. Existing defaults remain curated: other Spaces and displays
are included; minimized, hidden-application, and Picture-in-Picture windows are excluded
unless the user opts in. A filter notification asks `WindowStore` to rebuild immediately.

PiP detection remains behavioral because AX cannot
tell them apart — a Chromium PiP window reports `AXStandardWindow` like a real
browser window — so detection is behavioral: the window server keeps PiP
floating above normal windows (nonzero `kCGWindowLayer`, public
`CGWindowListCopyWindowInfo` — bounds and layer need no capture permission).
The pure rule lives in `PictureInPictureDetector` (unit-tested): a floating
window is PiP unless it covers (almost) a whole screen — Keynote presentations
and fullscreen overlays stay eligible. Each window's floating status is resolved
once, lazily, at snapshot time, and only when an unresolved on-screen window
exists — idle stays query-free. Core safety invariants remain non-configurable: actual
top-level windows only, one visible tab-group member, no menus/tooltips/system overlays,
and no WindowHop-owned UI except the registered Settings window.

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
credentials, and validates the final app against `Support/ExpectedDesignatedRequirement.txt`
and the stable public leaf certificate in `Support/WindowHopCodeSigning.cer`. The validator
checks bundle id, Team ID, hardened runtime, entitlements, every nested Mach-O signature,
and the exact designated requirement. The workflow submits both the app archive and final
DMG with `notarytool --wait`, staples and validates both tickets, runs Gatekeeper on the
app and DMG, preserves the branded DMG resource fork in an installer ZIP, then signs the
Sparkle archive and publishes. Local packages may remain ad-hoc signed only when release
identity validation is explicitly inapplicable.

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
