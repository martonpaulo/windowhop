# Testing WindowHop

## Automated

```sh
swift test          # 53 unit tests
```

Coverage: session state machine (open/cycle/wrap/reverse, escape/return/arrows/click,
modifier release, close-confirmation phases, list shrinking, cancellation), window
eligibility and display rules, MRU ordering, title fallback (incl. Unicode/RTL), settings
defaults and persistence, shortcut specs. The pure Core layer makes these deterministic —
no AX doubles needed; system integration is validated via the harness and checklist below.

## Debug harness

```sh
.build/debug/WindowHop --dump-windows            # live discovery + timings (needs Accessibility)
.build/debug/WindowHop --demo-switcher [--dark]  # panel with sample rows (no permission)
.build/debug/WindowHop --render-ui <dir>         # PNG renders of switcher + settings, light/dark
WINDOWHOP_DEBUG=1 <binary>                       # log tap decisions, commands, latency
```

## Manual checklist (real macOS integration)

Run from a real `/Applications` install with Accessibility granted.

Core interaction
- [ ] Cmd-Tab opens instantly, selects the previously focused window; release switches to it
- [ ] Cmd-Shift-Tab opens selecting the last item; Shift press/release mid-session reverses direction
- [ ] Holding Tab autorepeats; navigation wraps both ways; arrows move intuitively
- [ ] Escape cancels and focus stays put; Return activates; click activates; outside click cancels
- [ ] Native macOS switcher never appears while WindowHop is enabled; appears again when
      disabled (Settings/menu bar), after quit, and after `kill -9`
- [ ] With 0 eligible windows the chord falls through to the native switcher; with 1 window
      the panel shows that window selected

Window model
- [ ] Minimized windows and Cmd-H-hidden apps never listed; unminimize/show restores them
- [ ] Windows with identical titles remain distinct entries and activate correctly
- [ ] Safari/Finder/Terminal show correct tab counts; Chrome shows none; count updates after
      opening/closing tabs (may require a focus change to refresh)
- [ ] Full-screen windows are listed and activation switches to their Space
- [ ] Window on another Space: visit the Space once, verify it stays listed after leaving;
      activation hops Spaces correctly
- [ ] Second display: window listed; disable "Include windows from other displays" and
      verify it disappears; panel opens on the display with keyboard focus

Closing
- [ ] Delete shows `Close "…" in …?` with Cancel as default (Return cancels, Escape cancels)
- [ ] Confirming closes only that window; app keeps running; unsaved-changes dialog comes
      from the target app; switcher stays open with a sensible selection
- [ ] Releasing Cmd while the dialog is open does not activate anything
- [ ] Close the target window elsewhere before confirming → confirming does nothing harmful
- [ ] A window that refuses to close (no close button) beeps and stays

Lifecycle and permissions
- [ ] Onboarding appears without permission; granting starts the engine without relaunch
- [ ] Revoking permission while running: no half-intercepted chord (native switcher works),
      onboarding reappears; re-granting recovers
- [ ] Quit an app with windows open while the switcher is open → entries disappear,
      selection stays near; relaunching the app re-lists its windows
- [ ] Sleep/wake and screen lock/unlock: switcher still works afterward
- [ ] Password field focused (secure input): chord falls back to native; recovers after
- [ ] Relaunching the app opens Settings with menu bar item and Dock icon hidden
- [ ] Launch-at-login toggle works from /Applications; login launch does not open Settings

Accessibility & appearance
- [ ] VoiceOver announces the selected row (title, app, tab count) while cycling
- [ ] Light/Dark, Increase Contrast, Reduce Transparency, Reduce Motion all render sanely
- [ ] Long/Unicode/RTL/emoji titles truncate in the middle without layout jumps

## Already verified end-to-end during development (2026-07-02, macOS 26.5)

With synthetic CGEvents and live use: trigger interception with the native switcher
suppressed (verified via CGWindowList — no Dock switcher window during sessions), panel
shown in 3–22 ms, forward/backward triggers, wrap-around, Escape cancel with focus
unchanged, activation on Cmd release switching real apps (Claude → Brave), MRU order
correctness, idle CPU 0.0 %, ~15 real user-driven sessions logged working.
