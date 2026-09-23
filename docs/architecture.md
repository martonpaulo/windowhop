# WindowHop architecture

Four layers, one direction of knowledge: UI and Input know the Core; the Core knows nothing
about AppKit or AX.

The Core is its own SwiftPM library target, `WindowHopKit` (`Sources/WindowHopKit/`), with no
package dependencies. `WindowHopCore` (`Sources/WindowHopCore/`: `Engine/`, `Input/`, `UI/`,
`App/`) depends on it and on Sparkle, and every file that uses a Kit type says
`import WindowHopKit`. The compiler therefore enforces the direction of knowledge: a Kit file
cannot name an Engine, Input, UI or App type. `scripts/validate.sh` enforces the Kit import
allowlist recorded in `AGENTS.md` (Foundation, CoreGraphics value types, Observation,
Synchronization) and rejects AX, `NSWorkspace` and ScreenCaptureKit references in
the Kit. Tests follow the same split: `WindowHopKitTests` depends only on the Kit, and
`WindowHopTests` covers the integration layers.

```
┌──────────── UI ────────────┐  SwitcherPanel + SwitcherTileView (AppKit),
│                            │  Settings/Onboarding (SwiftUI), ShortcutRecorderControl,
│                            │  StatusItemController
├────────── Input ───────────┤  EventTap (tap thread) → SwitcherController (main)
├────────── Engine ──────────┤  WindowStore ← AXNotificationRouter ← TrackedApp observers
│                            │  WindowActions, AccessibilityPermission, LoginItem
├─────────── App ────────────┤  AppDelegate lifecycle, UpdateManager (Sparkle)
└──── Core (WindowHopKit) ───┘  SwitcherState, WindowEligibility, TabGroupResolver,
                                MRUOrder, TitleResolver, PersistentShortcut, Preferences,
                                ExpandedPreviewSession, SpaceMembership, ObserverLifecycle
                                (pure, unit-tested)
```

## Composition root

`AppDelegate` creates each long-lived object once and passes it to its consumers through
their initializers. `main.swift` only builds the `AppDelegate`. `Preferences` is an
`@Observable`, `@MainActor` model with no shared instance: the Settings panes receive it by
initializer and bind with `@Bindable`, never through an environment lookup of a global. The
debug harness builds its own `Preferences` over a separate `UserDefaults` suite that it
clears on each run, and tests build one over a throwaway suite (`IsolatedPreferences`), so
neither reads the person's real settings. Runtime reactions to a settings change still come
from `UserDefaults.didChangeNotification` and `Preferences.windowFiltersDidChange`.

`AppDelegate` also owns `UpdateManager`, the Settings window, the onboarding window and the
menu bar item. `UpdateManager`, `ConnectedDisplaysModel` and `LaunchAtLoginModel` are
`@Observable` too; the Settings panes receive what they use through `SettingsDependencies`
and their initializers. The menu bar item and the switcher reach the windows through
closures, not by naming a global.

The engine and input objects follow the same rule. `AppDelegate` creates `PreviewProvider`,
`WindowStore`, `EventTap` and `SwitcherController` in that order and keeps them for the
whole process. There is no `static let shared` in `Sources/`. The two C callbacks reach
their object without a global:

- the event-tap callback gets the `EventTap` through `userInfo`, as an unretained pointer
  that is sound because `AppDelegate` keeps the tap alive for the process lifetime;
- the AX observer callback gets the store's `AXNotificationRouter` through the
  notification's `refcon`. Every `AppObserver` holds that router strongly, so the pointer
  outlives the observer; the router holds the `WindowStore` weakly.

## Window model (event-driven, no polling)

1. `WindowStore.start()` KVO-observes `NSWorkspace.runningApplications`; each app gets a
   `TrackedApp` with one `AXObserver` (run-loop source on the dedicated AX events thread).
   Subscription retries handle apps that are still launching (ported from AltTab).
   The AX reads queue is the single owner of each app's observer state, held by an
   `AppObserver` actor whose executor is that queue: main reads eligibility and queues
   `start`/`stop` on it in FIFO order, where the pure `ObserverLifecycle`
   turns them and each subscription result into commands. Every attempt carries a
   generation; a retry, late result, or window subscription whose generation is no longer
   current does nothing, and `stop` is terminal, so pending work cannot revive a removed
   app. `WindowStore.discoverWindows` also drops requests for an app it no longer tracks.
   Removal reads the departed app's `processIdentifier` after the main-queue hop and
   requires `isTerminated`. Measured for #81 on macOS 26 (400 launch/exit cycles of a
   disposable app: SIGTERM, exit 50 ms after launch, Quit, early SIGKILL): every tracked
   app's departure arrived with its original pid and `isTerminated == true`, and none
   stayed tracked. The KVO change can land up to ~2 s after the app leaves
   `runningApplications`; the few departures that report pid −1 matched no tracked
   app by identity and carried no bundle identifier.
2. AX notifications land in `AXNotificationRouter` on the AX thread, hop to the serial
   AX reads queue for one batched attribute call (plus tab-group titles), then hand plain
   values to `WindowStore` on the main thread.
3. `WindowStore` keeps its windows in window-level MRU order (index 0 = focused). The
   order is owned by the pure `MRUOrder` (new windows enter at the end, focus moves a
   window to the front, the Settings entry enters at the front); `WindowStore.windows` is
   derived from it and never reordered by hand, so the `MRUOrder` tests cover the
   production policy. Open sessions keep their own stable order (`SessionListReconciler`)
   rather than re-sorting on every event. Identity is the `AXUIElement` itself (CFEqual-stable), so duplicate titles cannot
   collide. `snapshot()` applies eligibility + display rules and returns value items.
4. On `activeSpaceDidChange`, every app is re-enumerated: this discovers windows the
   public AX API hides until their Space is visited and refreshes each window's
   current-Space flag. `SpaceMembership` applies only a successful read: a failed
   enumeration (timeout, `.cannotComplete`) keeps each window's last known Space flag,
   while an empty successful list still marks the app's windows off-Space.

### Tabs are never entries

Native NSWindow tabs (Finder, Terminal, …) are real AX windows; only the visible tab
exposes the `AXTabGroup` child. `TabGroupResolver` (pure, ported from AltTab's
TabGroup.updateState) matches the reported tab titles against same-app windows and marks
inactive tabs `isTabbed`, which excludes them from display while keeping them tracked.
A title match alone is not proof of membership. Candidates for one title are ranked by
their AX frame against the active tab's (same frame, then unknown, then different — a
freshly merged inactive tab keeps reporting its pre-merge frame, so a different frame
ranks last instead of being excluded), then by recorded membership, never by discovery
order. When the best-ranked candidates outnumber the titles left to fill, none of them is
matched: an ambiguous window stays a visible entry rather than being hidden by a guess.
Each read of a window's tab bar is a `TabObservation`: `.group` (every tab button read),
`.standalone` (children read, no tab bar of 2 or more tabs), or `.unknown` (some AX read
failed). Only a complete read changes membership; `.unknown` keeps the last known group
and tab count, and the next complete read recovers without a retry timer.
A detached tab becomes an entry again on public facts only (#82). When a group's active
tab reports `.standalone`, every member recorded with it is released; a group that still
exists re-forms on its new active tab's next tab bar. An inactive tab that reports
`.standalone` with a focused- or main-window event and a frame different from its group's
active tab was dragged out: it leaves, and the old group shrinks as on a close. Any other
`.standalone` from an inactive tab keeps it hidden. Measured on macOS 26 with TextEdit's
Move Tab to New Window: in a two-tab group the remaining tab reports first, unmoved, and
used to stay hidden; in a three-tab group the new active tab's tab bar arrives first.
Discovery order is arbitrary, so a late-arriving sibling is matched against the active
tab's last complete tab bar (`TabGroupResolver.resolveArrival`); only groups with an
unmatched title equal to the newcomer's are resolved again.
A live merge is invisible to the observed notifications. Measured for #113 on macOS 26
(TextEdit, Window ▸ Merge All Windows): none of the subscribed app or window
notifications fire, the inactive tabs stay valid elements that keep their pre-merge
frames, and only the active tab remains in `kAXWindows`. An app-level subscription would
see `AXTitleChanged` on the new `AXTabButton`s, but it would also deliver every title
change of every element in every app. Instead, each session open re-reads the tab bars of
the entries whose app shows two or more of them (`TabGroupResolver.sessionRereadTargets`;
a merge needs two windows) on the AX reads queue, next to the dead-window check, and
applies them in one main-thread pass. The open session drops the merged tabs through its
normal list refresh. Measured cost: 2–15 ms for three TextEdit windows; nothing runs
while idle.
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
   thread. The callback reads a mutex-protected mode — `off`, `watching`, `sessionHeld`,
   `sessionSticky`, `passthrough` — and decides synchronously whether to consume;
   semantic events are posted to the main thread. `flagsChanged` is never consumed.
2. In `watching` it matches two chords: the switcher shortcut (modifier+Tab, Shift
   reverses) opening a **held** session, and the optional persistent shortcut
   (`PersistentShortcut`, exact modifier match) opening a **sticky** session.
   While the Settings shortcut recorder records, `isRecordingShortcut` makes `watching`
   pass every key, so a chord already in use reaches the recorder. The recorder owns the
   flag through `onRecordingChanged` → `SwitcherController.setShortcutRecordingActive`;
   stopping the tap keeps it. A key-up owned before recording began is still consumed.
   In a session, navigation keys (Tab, arrows, Return/Enter, Escape, Delete, sticky Space)
   match only with Shift plus the modifiers that own the session: the hold modifier when
   held, the Open WindowHop chord's modifiers when sticky. A chord with any other ⌘/⌥/⌃
   passes, so ⌃⌥ VoiceOver commands reach assistive technology whichever tap sees them
   first. Exceptions: the switcher trigger keeps stepping, and ⌘, needs ⌘. An Open
   WindowHop chord built from ⌃⌥ still owns ⌃⌥ keys in its sticky session.
3. `SwitcherController` (main) feeds events into the pure `SwitcherState` machine
   (phases: inactive → held/sticky → confirming) and executes the returned commands:
   show/select on the panel, activate/close via `WindowActions`, cancel.
   A held session starts at once (input interception, modifier-release activation) but
   draws its panels only after the `SwitcherRevealDelay` preference (default 100 ms),
   through one session-scoped timer; ending the session first invalidates it, so a quick
   press activates its target without drawing anything. Sticky sessions reveal immediately.
   Disabling or losing permission tears the session down from any phase, including
   confirming (`SwitcherState.teardown`); deferred confirmation work is bound to its
   session id, so a stale callback never revives an ended or newer session.
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
   window's identity is preserved whenever it survives; when the selected identity
   changes, the new target is announced once. An entry that briefly loses its
   location metadata while Spaces update is retained rather than removed, which is distinct
   from appending a new one (`WindowHopKit/SessionListReconciler.swift`, and
   `SwitcherController.shouldPreserveAcrossLocationRefresh`).
6. While a **held** session runs, a 0.5 s timer cross-checks `NSEvent.modifierFlags` to
   recover from missed key-up events. Sticky sessions have no such timer — modifier
   release means nothing there; only Return/Space/click/Escape end them.

The shortcut recorder in Settings (`UI/ShortcutRecorderControl`) stays custom rather than
adopting a library such as KeyboardShortcuts
([#74](https://github.com/martonpaulo/windowhop/issues/74)). Adopting one would override
three recorded rules: Sparkle is the only runtime dependency, `WindowHopKit/ShortcutFormatter` is the
only owner of key names, and product copy is English-only in one String Catalog. It would
also not remove the hardest part of the job: a library recorder cannot see `EventTap`, so
coordination with the tap would stay custom either way. Matching stays in `EventTap`, and
persistence stays in `PersistentShortcut` and `Preferences`. Known recorder gaps are fixed in
place against the custom control. Revisit this only by first amending the dependency rule.

Shortcut labels follow the keyboard layout; bindings do not. A recorded shortcut stores and
matches the physical key code. `ShortcutFormatter` names printable keys through its
`KeyLabelSource` seam: the app installs `Engine/KeyboardLayout` at launch (Text Input
Sources + `UCKeyTranslate`, main thread only), while tests, the render harness and any
failed translation use the fixed ANSI table in `KeyCodeNames`. Special keys (Tab, Return,
Space, arrows, F-keys…) never consult the layout. The recorder refreshes its title on
`kTISNotifySelectedKeyboardInputSourceChanged` only while it is in a window.

Conflict knowledge for a recorded chord has one owner, `WindowHopKit/ShortcutConflicts.swift`
(`PersistentShortcut.assessCapture`): accept, reject with a named reason (reserved by
macOS, standard app command), or confirm (an enabled macOS shortcut). Its inputs are
fixtures in tests; in the app, `Engine/SystemShortcuts` reads the enabled symbolic hotkeys
with the read-only `CopySymbolicHotKeys` at capture time, and `ShortcutRecorderField` shows
the reason inline or the confirmation sheet. The load path never re-assesses a stored chord.

## Placement across displays

Where the panel is drawn is display *behavior*, not appearance, and is owned by three
pieces with one responsibility each:

- `WindowHopKit/PanelPlacement.swift` — the pure rule. `PanelDisplayResolver` maps
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
  The group, not each panel, posts the selection announcement
  (`UI/SelectionAnnouncer.swift`), so one selection speaks once on any number of displays.

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
panel's centering or dimensions. The panel
background is the system glass material (NSGlassEffectView, the native
switcher's look); only the offscreen `--render-ui` harness substitutes the HUD
visual-effect material, because glass draws empty under cacheDisplay. Tiles wrap
into **rows** when one row can't fit ~88 % of the screen width (the AltTab
layout model) — there is no horizontal scrolling and tiles never shrink; ←/→
step linearly while ↑/↓ move by one row. Only an extreme window count exceeds
the ~85 % height budget and falls back to vertical scrolling with the selection
kept visible. Tile views are pooled and reconfigured, so repeated opens and
live updates are single-digit milliseconds even with 100+ windows. A list refresh
keeps each window on the tile that already shows it and reconfigures only tiles whose
data changed (title, icon, tab count, appearance); a reordered window moves with its
tile, and only new windows take a free one. The pure `TileReusePlan` (in
`WindowHopKit`) makes that decision. Before, every refresh redrew every tile, and one
window dragged at 60 Hz cost 13–24 ms of main-thread time per event at 120 windows;
now it costs about 5 ms at the 95th percentile
([#119](https://github.com/martonpaulo/windowhop/issues/119)). System
materials and semantic colors handle Light/Dark, Increase Contrast, and Reduce
Transparency.

## Window previews

`PreviewProvider` (the only file allowed to touch ScreenCaptureKit — enforced by
`scripts/validate.sh`) captures tile-sized snapshots via `SCScreenshotManager`,
but only while a session is open, only in Window Previews mode, and only with
Screen Recording granted. `ScreenRecordingPermission` classifies permission before the
provider emits a loading state, so unavailable authorization never starts capture or a
retry loop. The preflight costs 14–18 ms on the main thread, so a session reads it once when
it opens; windows that join the session reuse that status, and only a capture failure reads
it again, which is how a grant revoked during the session still blocks the panel
([#120](https://github.com/martonpaulo/windowhop/issues/120)). One panel-level action requests
a not-determined grant or opens the correct Privacy & Security pane; cards never duplicate
that action. App activation refreshes the
status after the user returns from System Settings. App Icons never needs this permission.
The cache is memory-only and app-lifetime: opening
the switcher shows the last known snapshot of every window instantly. The
session recaptures in parallel and delivers every result live —
a tile that opened with a cached snapshot crossfades to the fresh capture the
moment it lands (constant geometry, no layout shift; Reduce Motion disables
the fade), and tiles that opened with none fill in. Captures are taken without
the system window shadow (`ignoreShadowsSingleWindow`); the tile draws its own
shadow along the preview's rounded clip. WindowHop's own Settings window is
captured too (own pid + converted frame). Entries are evicted the moment their
window disappears and when the user switches back to App Icons. Views hold an image only
while they present it: hidden pool slots and a collapsed expanded preview drop theirs at
once, and every view releases its image when the session ends, so the provider cache is
the only warm owner between sessions and an evicted snapshot is actually freed.

Every capture takes a slot of one provider-wide `CaptureBudget` (in `Core/`, limit four),
whether it serves the session's list, a window that joined the open session, or the dwell
snapshot, which is served first. A slot passes to the next capture the moment one finishes,
and captures still waiting when the session ends never start. Before, each batch limited
only itself, and ten windows opening during a session put up to 10 captures in flight at
once ([#86](https://github.com/martonpaulo/windowhop/issues/86)).

A tile capture that fails for a reason that can pass on its own gets one retry per window
per session ([#91](https://github.com/martonpaulo/windowhop/issues/91)). `TileCaptureFlow`
(pure, in `WindowHopKit`) owns the order: one shared lookup, captures in list order through
the same `CaptureBudget`, then, only for retryable failures, one 500 ms wait and one
coalesced lookup and capture. `PreviewRetryPolicy` retries only a failed inventory read and
the capture errors that describe a broken connection or a system hiccup (internal error,
interrupted or invalid application connection, no window list, stream stopped by the
system); `PreviewProvider` keeps the `SCStreamError` code to make that distinction, and an
unknown error is stable. No match, a window without a drawable area, a declined grant and
every other error are final at once, so an ambiguous match never becomes a retry loop or a
guess. `PreviewLedger.claimRetry` grants the allowance once per window per session and only
while a result could still be delivered live; before the retry the provider confirms the
grant once, and an ended session, a mode change, a revoked grant or an evicted window stops
the retry before its lookup. While a retry waits the tile keeps its loading state; after
the retry fails it shows the unavailable state, and a cached snapshot stays in place.

Captures finish asynchronously and out of order, so the pure, unit-tested
`PreviewLedger` decides what a late result may do: results for evicted windows
are discarded entirely, and results from an ended or superseded session may
still warm the cache but are never delivered live. Panel delivery is keyed by
the window's stable id — never by tile position — and pooled tiles reset their
image state on reconfigure, so a snapshot can never appear on another window's
card (regression-tested, including rapid list changes).

Accessibility and the window server describe the same window with different data, so
`PreviewMatcher` (pure, unit-tested, in `WindowHopKit`) pairs them. Titles disagree by design —
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
skeleton with a quiet pulse; Reduce Motion makes it static. The pulse runs only while the
skeleton is visible: a hidden skeleton (App Icons tiles, loaded previews, hidden pool slots)
never carries one, because an animation on a hidden layer inside the visible panel still
keeps WindowServer compositing (measured in #88). Missing or revoked permission
uses the same geometry as a subdued, non-animating fallback while the single panel-level
recovery action remains available. Acquisition, matching, or capture failure also uses a
static skeleton, without exposing technical copy. A cached snapshot is never replaced by
an ordinary capture or permission failure. All paths keep constant geometry and selection,
with no badge, surface, or title movement. The acquisition state is kept per window for the
session by the pure `PreviewAvailability` (in `WindowHopKit`), not by the pooled tile, so a list
refresh, retitle, or reorder keeps a failed or permission-blocked card static instead of
resetting it to a loading pulse that no capture would ever end.

After the configured dwell, `SwitcherController` asks the provider for a current snapshot
of the selected id and presents it in `ExpandedPreviewView`. Both the dwell request and
asynchronous result carry session/target generations; navigating or closing invalidates
them. This path is snapshot-only and has no reference to `WindowActions.activate`.
The expanded snapshot is session-only: it never enters the preview cache and never
replaces the tile's image. The provider keeps just the latest one, until the session ends
or its window disappears, so returning to that window shows it sharp at once. Keeping one
per visited window used to grow the cache by 132 MB of raster after dwelling on 60
windows ([#87](https://github.com/martonpaulo/windowhop/issues/87)).

Matching AX windows to `SCWindow`s is a **unique assignment** (pid + frame first,
title as tiebreak, then exact title), so two windows of the same app can never
share a snapshot; a request with no confident match keeps the placeholder and badge —
a wrong preview is worse than none. Images are requested pre-scaled (no
full-resolution retention). Preview failure can never remove an entry or block
activation.

A capture that succeeds is trusted as-is; there is no size or blank-image threshold.
Measured on macOS 26 ([#89](https://github.com/martonpaulo/windowhop/issues/89)): small
legitimate windows (30×30 to 260×120 pt) return full, usable images; minimized, hidden
and ordered-out windows return their last full content; a window destroyed mid-capture
fails with an error, which keeps the cached preview. The one unusable success is a
window resized between listing and capture: the image comes back at the requested size
but only partly filled (nearly blank at 1×1 pt), and the next capture corrects it.

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
and fullscreen overlays stay eligible — or its AX close button is enabled, unless
minimize is disabled while zoom stays enabled (Firefox PiP).
Floating level alone is not PiP: any app can float an ordinary document, palette or
dialog. Measured for #90 on macOS 26: Chromium PiP (Chrome and Brave, layer 3) keeps its
close, minimize and zoom buttons but disables all three, while AppKit titled windows at
`.floating` or `.modalPanel` keep an enabled close button. Firefox PiP (and Zen) is the
closable exception: AeroSpace's corpus (#117) shows close and zoom (full screen) enabled
and only minimize disabled, a combination no ordinary floating window in it has;
closable-only dialogs disable zoom too. App-modal alerts and open/save
panels have no close button at all and float at the modal-panel layer (8, measured for
#115 with `NSAlert` and `NSOpenPanel`), so that layer is never PiP. System PiP (PIPAgent, measured
through AVKit) is an `AXSystemFloatingWindow` at layer 19, which `isActualWindow`
already rejects; borderless floating windows report `AXUnknown` and are rejected there
too, and `NSPanel` utilities (`AXFloatingWindow`) never reach the rule. The close,
minimize and zoom buttons' states are read once per window creation on the AX reads queue
(a few extra reads, never per move or resize); an unread or missing close button leaves
the layer rule in charge.
Each window's floating status is resolved
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

Build metadata has one reader, `WindowHopKit/AppVersion` (version, build, release date), used by
Settings › About, the Updates pane and support reports. The release date is the packaged
commit's committer date (`git log -1 --format=%cs`), written as `AppReleaseDate`
(`YYYY-MM-DD`) by `scripts/stamp-app-metadata.sh`. `release.yml` runs it on the runner's
copy of `Support/Info.plist` right before the canonical `scripts/package-app.sh` copies that
plist into the bundle and signs it; the repository copy never carries the key
(`scripts/validate.sh` checks), so local packages and development builds have no date.

Official tag builds are fail-closed: the workflow accepts only the current `main` commit,
requires an Apple-issued Developer ID Application identity plus a team App Store
Connect API key for notarization, and validates the final app against `Support/ExpectedDesignatedRequirement.txt`
and the stable public leaf certificate in `Support/ReleaseCertificate.cer`. The validator
checks bundle id, Team ID, hardened runtime, entitlements, every nested Mach-O signature,
and the exact designated requirement. The workflow submits both the app archive and final
DMG through `scripts/notarize.sh` (`notarytool --wait`), staples and validates both tickets, runs Gatekeeper on the
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

## Launch and reopen

Decided on [#80](https://github.com/martonpaulo/windowhop/issues/80) (option C, the
visibility-aware hybrid). `AppDelegate` asks the pure `WindowHopKit/LaunchPresentation` rule at launch
and at reopen; `LaunchPresentationTests` covers every row. The menu bar item and the Dock
icon are both hidden by default, so "another visible surface" means the user turned one on.

| Condition | Surface |
| --- | --- |
| Normal launch, granted, first run | Settings |
| Normal launch, granted, menu bar item or Dock icon visible | Nothing |
| Normal launch, granted, both icons hidden | Settings |
| Login-item launch, granted | Nothing |
| Any launch (login included), Accessibility not granted | Onboarding |
| Reopen while running | Settings if granted, onboarding if not |
| Accessibility revoked while running | Onboarding |
| Onboarding completes | Settings |

First run is `Preferences.firstLaunchCompleted` still false, read before the launch marks it
done; it is set once Accessibility is granted, is not user-configurable, and Restore Defaults
does not reset it. A login-item launch is detected from the `kAEOpenApplication` event's
`keyAELaunchedAsLogInItem` property.

**Recorded exception to the shared shell standard** (`skd-macos-app-shell`, launch rule "a
login-item launch never opens a window"): a login launch without Accessibility opens
onboarding. Native ⌘Tab keeps working when WindowHop cannot intercept it, so without a window
nothing would reveal that WindowHop is inert, and with both icons hidden by default there is
no menu bar item to carry the pending state instead.

## Fail-safe properties

- The native macOS switcher is never modified. Interception exists only while the tap is
  alive and consuming; disabled/quit/crash/permission-revoked ⇒ native behavior.
- Missing permission stops the tap entirely — the shortcut is never partially intercepted.
- `tapDisabledByTimeout/UserInput` events re-enable the tap in the callback; sleep/wake and
  session-switch notifications re-arm it from the app delegate.
- A key-up is consumed only when the latest key-down of that key was consumed: every
  key-down reassigns the key's ownership. A key-up missed while the tap was disabled
  therefore heals at the next press of that key, and a re-enable neither resets the ledger
  (which would leak a held session's Tab release) nor needs a timer (#84).
- Modifier release is detected from event flags (covers left/right and both-held cases);
  the held-modifier guard covers missed events.

## Concurrency

Every target builds in the Swift 6 language mode, so the compiler checks the threading
rules above.

- **Main actor.** `WindowStore`, `TrackedApp`, `TrackedWindow`, `SwitcherController`,
  `Preferences`, `PreviewProvider`, `UpdateManager`, `EventTap`'s main-side API and the UI
  controllers are `@MainActor`. Callbacks that AppKit delivers on the main thread
  (notification observers on `.main`, main-run-loop timers, global event monitors) enter
  it with `MainActor.assumeIsolated`; AX results reach it with `DispatchQueue.main.async`,
  which keeps FIFO order with other main-queue work where a `Task` would not.
- **AX reads queue.** `BackgroundWork.axReadsQueue` is a serial queue and the executor of
  every `AppObserver` actor, so observer state is actor-isolated while AX reads keep their
  order. Values handed to main are plain `Sendable` values. The `AXNotificationRouter` is
  `Sendable`: its only state is a `weak let` to the store, read on main.
- **Event tap.** `EventTap.handle` stays a synchronous `nonisolated` function: the C
  callback captures nothing and reaches the tap through `userInfo`; everything the tap
  thread touches sits in one `Mutex`.
- **Window previews.** The capture pipeline runs on the main actor between its awaits;
  the screenshots themselves run inside ScreenCaptureKit.
- **Audited `@unchecked Sendable`.** Exactly three, each with its invariant beside it:
  `AXUIElement` (a retroactive conformance for the immutable, thread-safe CF reference),
  `RunLoopThread` (its run loop is written once before `init` returns) and `EventTap`'s
  `TapPort` (the tap's mach port, guarded by the tap mutex).

## Performance principles (inherited from AltTab)

- All AX IPC on background queues with a 1 s messaging timeout; the main thread only
  mutates state and draws.
- The tap callback does no allocation or IPC on the hot path.
- Idle = zero timers, zero polling; the app only reacts to OS events.
- View work is bounded: pooled tiles, no per-frame layout, no animations.
