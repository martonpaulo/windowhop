# WindowHop

**Switch between windows, not just apps.**

[![Latest release](https://img.shields.io/github/v/release/martonpaulo/windowhop)](https://github.com/martonpaulo/windowhop/releases/latest)
[![CI](https://github.com/martonpaulo/windowhop/actions/workflows/ci.yml/badge.svg)](https://github.com/martonpaulo/windowhop/actions/workflows/ci.yml)
[![License: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-blue)](LICENSE)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black)

macOS's Command-Tab switches between *apps*. WindowHop switches between *windows*:
every window gets its own large tile, and releasing Command lands you on the exact
window you picked — even on another Space or display. Free, open source, native.

![WindowHop App Icons in Light Mode with a rounded selection background](docs/screenshots/switcher-light.png)

Prefer window snapshots? Turn on the optional **Window Previews** appearance:

![Window Previews in Light Mode with a semantic selected focus ring, corner badges, a complete Close control, and loading and unavailable states](docs/screenshots/switcher-previews-light.png)

## Download and install

1. **[⬇ Download WindowHop-1.1.2.dmg](https://github.com/martonpaulo/windowhop/releases/latest)**
2. Open the DMG and **drag WindowHop into Applications**.
3. Open WindowHop from Applications. Official releases are Developer ID signed,
   notarized by Apple, and validated by Gatekeeper before publication.
4. Grant the one required permission:
   **System Settings → Privacy & Security → Accessibility → enable WindowHop.**
   The welcome window takes you there. That's it — press ⌘⇥.

## Using WindowHop

| Keys | Action |
|---|---|
| **⌘⇥** | Open the switcher and select your previous window |
| **⌘⇥⇥…** (keep holding ⌘) | Cycle forward |
| **⇧⌘⇥** | Cycle backward |
| **Release ⌘** | Switch to the selected window |
| **← → ↑ ↓** | Navigate |
| **↩** | Switch to the selected window |
| **⎋** | Cancel and restore the window active before WindowHop opened |
| **⌫** | Close the selected window (always asks first) |
| **⌘,** | Open WindowHop Settings |
| **Click** | Switch to a window; click outside cancels |

Hover a tile for a close button centered on that card's top-left canvas corner.
The global Settings control overlaps the panel's top-right corner with most of its
hit target inside, without moving the previews. The close dialog can also
**Quit** the app — and offers a separately confirmed **Force Quit**
if an app refuses to quit. Closing always preserves the app's own unsaved-changes
questions.

Pause on a tile while navigating and WindowHop temporarily brings that window forward
behind the switcher after the configured dwell. Fast traversal cancels pending work, so
intermediate windows are skipped.
Confirming keeps the targeted window active; cancelling restores the exact origin window
when it still exists.

**One entry per window, never per tab.** A Safari window with 5 tabs is one entry
showing "5 tabs". Finder/Terminal tab groups collapse to their visible tab.

### The "Open WindowHop" shortcut

Prefer not to hold a modifier? Assign a second shortcut (say ⌥Space) in Settings →
General. It opens the switcher and *keeps it open*: ⇥/⇧⇥/arrows navigate, ↩ or
Space switches, ⎋ cancels. Unassigned by default.

### App Icons vs Window Previews

Settings → **Appearance**. *App Icons* (default) shows each window as a large app
icon and needs no extra permission. *Window Previews* shows a snapshot of each
window and needs **Screen Recording** permission (macOS requires it); WindowHop
asks only when you pick previews, and falls back to icons until it's granted.
Previews are generated on your Mac and kept only in memory, never written to disk or
transmitted. A cached preview can appear immediately when the switcher opens; a fresh
capture replaces it in place when available. Loading and unavailable cards keep the
same fixed canvas, outline, title position, and bottom-right app badge, so nothing jumps.
Loading cards say “Loading preview…”; a failed first capture changes in place to the
secondary “Preview unavailable” state without exposing a technical error.
App Icons stays borderless and uses a soft rounded selection background; Window Previews
uses one semantic macOS focus ring that replaces its subtle neutral outline.

## Settings

Native multi-pane Settings — General, Appearance, Updates, About. General exposes every
existing user-configurable behavior: enablement, launch at login, both shortcuts,
Space/display inclusion, and menu bar/Dock visibility. Appearance owns presentation,
tab counts, and the navigation-preview dwell: Off, Short, Default (700 ms), or Long.
Updates owns automatic update checks. Invalid stored values fall back to documented
defaults. Launching
WindowHop again (Finder, Spotlight, Dock) opens Settings even with the menu bar
item and Dock icon hidden (both hidden by default).

![Settings — General](docs/screenshots/settings-general.png)

### Interface gallery

The screenshots below are generated by the app's release-equivalent render harness
using synthetic titles and preview content—no personal windows or Screen Recording data.

![WindowHop switcher in Dark Mode](docs/screenshots/switcher-dark.png)

![Window Previews in Dark Mode with one selected loaded preview, corner badges, a loaded-preview Close control, and loading and unavailable states](docs/screenshots/switcher-previews-dark.png)

![WindowHop multi-row layout with consistent row spacing and selection](docs/screenshots/switcher-overflow.png)

![Settings — Appearance](docs/screenshots/settings-appearance.png)

![Settings — Updates](docs/screenshots/settings-updates.png)

![Settings — About](docs/screenshots/settings-about.png)

## Automatic updates and privacy

WindowHop updates itself with [Sparkle](https://sparkle-project.org): it checks a
feed on GitHub and cryptographically verifies (EdDSA) every update before
installing — a plain native dialog, no embedded web pages. Control it in
Settings → Updates, which also shows when a newer version is available.
**Update checks are WindowHop's only network activity** — no telemetry, no
analytics, no accounts.

## Uninstall

Quit WindowHop (menu bar item → Quit, or via Activity Monitor), then delete
`/Applications/WindowHop.app`. Optional cleanup:
`defaults delete com.perso.windowhop` and remove WindowHop from
System Settings → Privacy & Security → Accessibility (and Screen Recording).

## Troubleshooting

- **⌘⇥ shows the old macOS switcher** — WindowHop isn't running, is disabled, or
  lost Accessibility permission. That's the fail-safe: native switching always keeps
  working.
- **The Accessibility toggle doesn't stick** — the welcome window has a
  "Reset Stuck Permission…" button that clears the stale entry so you can grant
  it fresh. Also make sure WindowHop was dragged into Applications with Finder
  (running it straight from the DMG or Downloads triggers macOS App
  Translocation, where no grant can persist — WindowHop warns about this).
  Official releases use one stable Developer ID identity so the grant survives updates.
- **Previews are icons instead of snapshots** — grant Screen Recording in
  System Settings → Privacy & Security, then relaunch WindowHop.
- **A window is missing** — minimized windows, hidden apps, and floating
  Picture-in-Picture panels are excluded by design; a window on an unvisited
  Space appears after you visit that Space once.
- **Typing a password?** Secure input pauses interception; ⌘⇥ is native until done.

## Build from source

macOS 14+, Xcode 16+ (free); no paid account needed.

```sh
git clone https://github.com/martonpaulo/windowhop && cd windowhop
swift test                # test suite
scripts/validate.sh       # repository invariants
scripts/package-app.sh    # build/WindowHop.app (ad-hoc signed)
scripts/make-dmg.sh       # the installer DMG
```

Docs: [architecture](docs/architecture.md) · [testing](docs/testing.md) ·
[contributing](CONTRIBUTING.md) · [upstream attribution](UPSTREAM.md)

## Known limitations

- **Windows on unvisited Spaces** appear only after that Space is visited once
  while WindowHop runs — a limitation of macOS's public Accessibility API
  (WindowHop deliberately uses no private APIs, unlike AltTab).
- **Tab counts** appear only for apps exposing native tab groups (Safari, Finder,
  Terminal, TextEdit, …); Chrome-style custom tabs show no count — never guessed.
- English-only interface in this release.

## License and attribution

[GPL-3.0](LICENSE). Derived from
[AltTab](https://github.com/lwouis/alt-tab-macos) by Louis Pontoise (lwouis) and
contributors — base tag `v10.12.0` (`317a485b`), full upstream history preserved
in this repository. See [UPSTREAM.md](UPSTREAM.md). Thank you, AltTab.
