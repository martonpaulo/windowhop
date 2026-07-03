# Testing WindowHop

## Automated

```sh
swift test           # 88 unit tests
scripts/validate.sh  # repository invariants (identifiers, no private APIs, updater config)
```

Coverage: session state machine (held and persistent modes: open/cycle/wrap/reverse,
escape/return/space/arrows/click, modifier release semantics per mode, close-confirmation
phases, list shrinking, cancellation), tab-group resolution (incl. two browser windows
with five tabs each → exactly two entries), Settings-window entry lifecycle, window
eligibility and display rules, MRU ordering, title fallback (incl. Unicode/RTL),
persistent-shortcut matching/validation/encoding, settings defaults and persistence.
The pure Core layer makes these deterministic; the Settings-entry tests drive real
NSWindow notifications against a fresh store.

## Debug harness

```sh
.build/debug/WindowHop --dump-windows            # live discovery + timings (needs Accessibility)
.build/debug/WindowHop --demo-switcher [--dark] [--many]  # panel with sample rows (no permission)
.build/debug/WindowHop --render-ui <dir>         # PNG renders: switcher light/dark, overflow, settings
WINDOWHOP_DEBUG=1 <binary>                       # log tap decisions, commands, latency
```

## Updater end-to-end

`--updater-e2e <feed-url>` drives a real `SPUUpdater` with an auto-accepting user driver.
The full pipeline was exercised on 2026-07-03 against a local HTTP appcast:

1. **Install path**: old 1.0.0 (build 1) found signed 1.0.1 (build 2) → downloaded →
   EdDSA verified → installed (bundle replaced on disk) → relaunched. Verified by
   reading the bundle's Info.plist after install and observing the relaunched process.
2. **No-update path**: 1.0.1 against the same feed → "no update found".
3. **Tampered signature**: corrupted `sparkle:edSignature` → Sparkle rejected the update
   ("improperly signed and could not be validated"); the old bundle stayed intact.

To repeat: build two versions with `scripts/package-app.sh <ver> <build>`, sign the newer
zip with Sparkle's `sign_update`, write an appcast pointing at a local
`python3 -m http.server`, and run the older app's binary with `--updater-e2e`.

## Manual checklist (real macOS integration)

Run from a real `/Applications` install with Accessibility granted.

Core interaction
- [ ] ⌘Tab opens instantly with large icon tiles; selects the previously focused window;
      release switches to it
- [ ] ⌘⇧Tab opens selecting the last item; Shift press/release mid-session reverses direction
- [ ] Holding Tab autorepeats; navigation wraps; arrows move intuitively
- [ ] Escape cancels and focus stays put; Return activates; click activates; outside click cancels
- [ ] Native macOS switcher never appears while WindowHop is enabled; appears again when
      disabled (Settings/menu bar), after quit, and after `kill -9`
- [ ] With 0 eligible windows the chord falls through to the native switcher; with 1 window
      the panel shows that window selected

Persistent mode
- [ ] Record a shortcut (e.g. ⌥Space) in Settings; pressing it opens the switcher and it
      stays open after releasing every key
- [ ] Tab/⇧Tab/arrows navigate; Return, Space, and clicking switch; Escape cancels back
      to the original window
- [ ] Releasing modifiers never closes or activates; pressing the shortcut again keeps
      the session open; Delete still asks before closing
- [ ] Recording ⌘Tab is rejected inline; modifier-less keys are rejected inline;
      changing the switcher chord to match clears the persistent shortcut with a message

Window model
- [ ] Minimized windows and ⌘H-hidden apps never listed; unminimize/show restores them
- [ ] Windows with identical titles remain distinct entries and activate correctly
- [ ] Two Safari windows with 5 tabs each → exactly 2 entries, each showing "5 tabs"
- [ ] Finder/Terminal with tabs: one entry per tab *group* (the visible tab); selecting
      a different tab natively swaps which window represents the group
- [ ] Full-screen windows are listed and activation switches to their Space
- [ ] Window on another Space: visit the Space once, verify it stays listed after leaving
- [ ] Second display: window listed; disable "Include windows from other displays" and
      verify it disappears; panel opens on the display with keyboard focus
- [ ] Open WindowHop Settings → it appears exactly once in the switcher with the
      WindowHop icon; activating it focuses Settings; closing it removes the entry;
      minimizing it hides the entry; the switcher panel itself never appears

Closing
- [ ] Delete shows `Close "…" in …?` with Cancel as default; Return cancels, Escape cancels
- [ ] Confirming closes only that window; unsaved-changes dialogs come from the target app;
      the switcher stays open with a sensible selection
- [ ] Releasing ⌘ while the dialog is open does not activate anything

Lifecycle, permissions, updates
- [ ] Onboarding appears without permission; granting starts the engine without relaunch
- [ ] Revoking permission while running: no half-intercepted chord; onboarding reappears
- [ ] Sleep/wake and screen lock/unlock: switcher still works afterward
- [ ] Secure input (password field): chord falls back to native; recovers after
- [ ] Relaunching the app opens Settings with menu bar item and Dock icon hidden
- [ ] Launch-at-login toggle works from /Applications; login launch does not open Settings
- [ ] "Check for Updates…" works from Settings and the menu bar item; offline check
      fails gracefully

Accessibility & appearance
- [ ] VoiceOver announces the selected tile (title, app, tab count) while cycling
- [ ] Light/Dark switch live, Increase Contrast, Reduce Transparency all render sanely
- [ ] Long/Unicode/RTL/emoji titles truncate without layout jumps; 100+ windows scroll
      smoothly with the selection always visible

## Verified during development (2026-07-02/03, macOS 26.5, Apple Silicon)

With synthetic CGEvents and live use: chord interception with the native switcher
suppressed (verified via CGWindowList — no Dock switcher window during sessions), panel
shown in 3–22 ms, forward/backward triggers, wrap-around, Escape cancel with focus
unchanged, activation on ⌘ release switching real apps, ~15 real user-driven sessions
logged working, idle CPU 0.0 %, and the full Sparkle update pipeline (above).
120-tile panel: first-ever open ~100 ms (one-time pool growth), subsequent updates 1–3 ms.
