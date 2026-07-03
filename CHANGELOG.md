# Changelog

## 1.0.0 — 2026-07-03

First release.

- Window-first Command-Tab replacement: one large-icon tile per window, each with
  its title and an optional tab count — no previews, no screenshots.
- Hold-based switching (⌘Tab / ⌘⇧Tab, release to switch) plus an optional
  persistent "Open WindowHop" shortcut that keeps the switcher open without
  holding a modifier.
- Real window-level most-recently-used ordering; windows from other Spaces and
  displays included by default; native tabs never appear as separate entries.
- Delete asks to close the selected window, always with confirmation.
- Automatic updates via Sparkle 2 (EdDSA-signed archives); update checks are the
  app's only network activity.
- Derived from AltTab v10.12.0 (GPL-3.0), rebuilt on public Apple APIs only.
