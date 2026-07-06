# Changelog

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
