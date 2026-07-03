# WindowHop architecture

Four layers, one direction of knowledge: UI and Input know the Core; the Core knows nothing
about AppKit or AX.

```
┌──────────── UI ────────────┐  SwitcherPanel (AppKit), Settings/Onboarding (SwiftUI),
│                            │  StatusItemController
├────────── Input ───────────┤  EventTap (tap thread) → SwitcherController (main)
├────────── Engine ──────────┤  WindowStore ← AXNotificationRouter ← TrackedApp observers
│                            │  WindowActions, AccessibilityPermission, LoginItem
└─────────── Core ───────────┘  SwitcherState, WindowEligibility, MRUOrder,
                                TitleResolver, Preferences, ShortcutSpec   (pure, tested)
```

## Event flow

**Window model (event-driven, no polling):**

1. `WindowStore.start()` KVO-observes `NSWorkspace.runningApplications`; each app gets a
   `TrackedApp` with one `AXObserver` (run-loop source on the dedicated AX events thread).
   Subscription retries handle apps that are still launching (ported from AltTab).
2. AX notifications land in `AXNotificationRouter` on the AX thread, hop to the serial
   AX reads queue for one batched `AXUIElementCopyMultipleAttributeValues` call (plus tab
   group counting), then hand plain values to `WindowStore` on the main thread.
3. `WindowStore` keeps `[TrackedWindow]` in window-level MRU order (index 0 = focused).
   Identity is the `AXUIElement` itself (CFEqual-stable), so duplicate titles cannot
   collide. `snapshot()` applies eligibility + display rules and returns value items.
4. On `activeSpaceDidChange`, every app is re-enumerated: this discovers windows the
   public AX API hides until their Space is visited and refreshes each window's
   current-Space flag.

**Input (Cmd-Tab session):**

1. `EventTap` owns a consuming CGEvent tap (keyDown/keyUp/flagsChanged) on its own thread.
   The callback reads a lock-protected mode (`off` / `watching` / `session` /
   `passthrough`) and decides synchronously whether to consume; semantic events are posted
   to the main thread. `flagsChanged` is never consumed.
2. `SwitcherController` (main) feeds events into the pure `SwitcherState` machine
   (phases: inactive → held → sticky/confirming) and executes the returned commands:
   show/select on the panel, activate/close via `WindowActions`, cancel.
3. The switcher list is **frozen at session start**; store changes while open only remove
   or refresh entries (nearby selection preserved), never reorder or add.
4. While a session is held, a 0.5 s timer cross-checks `NSEvent.modifierFlags` to recover
   from missed key-up events (session-scoped; never runs while idle).

## Public-API replacements for AltTab's private calls

| Concern | AltTab (private) | WindowHop (public) |
|---|---|---|
| Suppress native Cmd-Tab | `CGSSetSymbolicHotKeyEnabled` | consuming event tap; nothing to restore on quit/crash |
| Focus a window | `_SLPSSetFrontProcessWithOptions` + `SLPSPostEventRecordTo` | `kAXMainAttribute` + `kAXRaiseAction` + settable `kAXFrontmostAttribute`, then `NSRunningApplication.activate()` |
| Window identity | `_AXUIElementGetWindow` (CGWindowID) | the `AXUIElement` itself (CFEqual/CFHash) |
| Other-Space windows | `_AXUIElementCreateWithRemoteToken` brute force + `CGSCopySpaces*` | persistent store + re-enumeration on Space change (see limitation in README) |

## Fail-safe properties

- The native macOS switcher is never modified. Interception exists only while the tap is
  alive and consuming; disabled/quit/crash/permission-revoked ⇒ native behavior.
- Missing permission stops the tap entirely (`applyConfiguration`) — the shortcut is never
  partially intercepted.
- `tapDisabledByTimeout/UserInput` events re-enable the tap in the callback; sleep/wake and
  session-switch notifications re-arm it from the app delegate.
- Modifier release is detected from event flags (covers left/right and both-held cases);
  the held-modifier guard covers missed events.

## Performance principles (inherited from AltTab)

- All AX IPC on background queues with a 1 s messaging timeout; the main thread only
  mutates state and draws.
- The tap callback does no allocation or IPC on the hot path.
- Idle = zero timers, zero polling; the app only reacts to OS events.
