# Changelog

## 1.0.5 — 2026-07-08

- Window titles now wrap to **two lines** before truncating — no more premature
  "…" on titles that would fit. The title zone has a fixed two-line height, so
  tiles never resize between short and long titles and the tab-count line stays
  aligned across every tile.
- The native-switcher visual pass is fully unified across both appearances
  (App Icons and Window Previews share the same panel material, selection ramp,
  vertical rhythm, and badge controls), verified in Light and Dark Mode.
- Snapshot corners rounded slightly more (10 pt) to sit naturally inside the
  larger selection radius.


## 1.0.4 — 2026-07-08

Visual pass to match the native macOS switcher, reviewed primarily in Dark Mode:

- The panel now uses the stable dark-glass HUD material — bright desktops can no
  longer wash it out (the popover material was too transparent).
- Selection is the native idiom: a rounded rectangle *lighter* than the panel in
  Dark Mode (white ~16%), darker in Light Mode — no more near-black selection.
- Close and Settings controls use the Apple badge style: white glyph on a filled
  gray circle (like notification and Safari-tab close buttons) — high contrast on
  any snapshot.
- Density matched to the native switcher: tighter tiles (124×158 icons, 204×170
  previews), larger panel corner radius, quieter placeholder fill.


## 1.0.3 — 2026-07-07

- **Permission loop, part 2**: the welcome window now detects macOS App
  Translocation (running from a quarantined temporary path — a grant can never
  stick there) and offers a one-click "Reset Stuck Permission…" that clears a
  stale Accessibility entry via Apple's tccutil so the next grant binds cleanly.
- **Standard keyboard shortcuts everywhere**: WindowHop now has a proper main
  menu, so ⌘W closes the Settings window, ⌘Q quits, ⌘, opens Settings, and text
  editing shortcuts work.
- **Native-switcher colors**: selection and placeholder surfaces now use the
  system semantic fills (secondary/quaternary system fill) and the panel uses
  the standard popover material — the same palette family as Apple's switcher.
- **No more preview flash**: windows without a snapshot show a quiet rounded
  placeholder card with the app icon, and the first capture fades in over it
  (Reduce Motion disables the fade). Geometry never jumps.
- Close and Settings overlay controls redesigned to the Apple badge idiom:
  hierarchical SF Symbols anchored to the content corner (Mission Control
  style), on one shared inset grid.
- The Appearance pane keeps a fixed height — switching App Icons/Window
  Previews no longer resizes the Settings window mid-animation.
- The DMG is now built with sindresorhus/create-dmg (pinned): the familiar
  polished drag-to-Applications layout, reproducible on CI.
- Releases now ship exactly two assets: the DMG (for people) and the ZIP
  (for Sparkle updates).


## 1.0.2 — 2026-07-06

- **Fixed the endless Accessibility permission loop after updates**: releases are
  now signed with a stable certificate, so macOS keeps the grant across updates.
  One last re-grant is needed when installing this version (remove WindowHop from
  the Accessibility list with −, add it again with +); after that, updates keep
  working without asking again.
- **Native update dialog**: checking for updates now shows the plain macOS alert —
  no embedded web view. Full release notes stay on GitHub.
- Previews follow the AltTab model strictly: what the switcher opens with is what
  you see (snapshots are never swapped mid-session); captures only refresh the
  in-memory cache for the next open, and tiles that had no snapshot fill in.
- The WindowHop Settings window now shows its own preview in Window Previews mode.
- Multi-row layouts center every row (no more left-ragged last row).
- Bigger app-icon badge on previews (40 pt), close/Settings controls aligned on
  one 8 pt inset grid, and all UI dimensions moved into a single design-tokens
  file (`UI/DesignTokens.swift`).
- "Quit WindowHop…" in Settings is visibly destructive (red), with confirmation.

## 1.0.1 — 2026-07-06

- **Instant previews**: window snapshots are cached in memory (AltTab-style) so
  the switcher opens instantly with the last known preview, while fresh captures
  load in parallel and crossfade in when the content changed. Nothing is captured
  while the switcher is closed; snapshots stay in memory only and are evicted
  with their window.
- **Every window gets its own preview**: snapshot-to-window matching is now a
  unique assignment — two windows of the same app can no longer show the same
  preview; an uncertain match falls back to the app icon instead of guessing.
- **Grid instead of horizontal scrolling**: many windows now wrap into multiple
  rows (arrow keys navigate the grid spatially); icons never shrink.
- Bigger window titles (13 pt), slightly smaller preview tiles, and much more
  visible close and Settings controls.
- Fixed duplicate entries after a missed window-close notification (the
  "WhatsApp appeared twice" bug): stale Accessibility elements are now detected
  and pruned on Space changes and when the switcher opens.
- Fixed the WindowHop Settings window sometimes not coming to the front when
  activated from the switcher.
- Added a confirmed "Quit WindowHop…" button in Settings → General.
- New tagline everywhere: "Switch between windows, not just apps."

## 1.0.0 — 2026-07-03

First release.

- Window-first Command-Tab replacement: one entry per top-level window, never per
  tab — a Safari window with 5 tabs is one entry with a quiet "5 tabs" hint.
- Two appearances: **App Icons** (default, large icons, no extra permission) and
  optional **Window Previews** (live window snapshots via ScreenCaptureKit,
  generated locally in memory only while the switcher is open).
- Hold-based switching (⌘⇥ / ⇧⌘⇥, release to switch) plus an optional persistent
  "Open WindowHop" shortcut that keeps the switcher open without holding a modifier.
- Real window-level most-recently-used ordering; windows from other Spaces and
  displays included by default; exact-window activation.
- Close windows from the switcher (⌫ or the hover close button), always with a
  confirmation that also offers Quit — and a separately confirmed Force Quit for
  apps that refuse to quit.
- Native multi-pane Settings (General, Appearance, Updates, About), a hover
  Settings control on the panel, and ⌘, while the switcher is open.
- Automatic updates via Sparkle 2 (EdDSA-signed archives); update checks are the
  app's only network activity. No telemetry, no accounts.
- Derived from AltTab v10.12.0 (GPL-3.0), rebuilt on public Apple APIs only.

Known limitations: releases are not notarized (no paid Developer ID yet); windows
on unvisited Spaces appear after that Space is visited once; tab counts only for
apps exposing native tab groups; English-only interface.
