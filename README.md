# WindowHop

**A fast, native window switcher for macOS — Command-Tab, but for windows.**

[![Latest release](https://img.shields.io/github/v/release/martonpaulo/windowhop)](https://github.com/martonpaulo/windowhop/releases/latest)
[![CI](https://github.com/martonpaulo/windowhop/actions/workflows/ci.yml/badge.svg)](https://github.com/martonpaulo/windowhop/actions/workflows/ci.yml)
[![License: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-blue)](LICENSE)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black)

macOS's Command-Tab switches between *apps*. WindowHop switches between *windows*:
every window gets its own large icon and title, and releasing Command lands you on the
exact window you picked — even if it's on another Space or display. No previews, no
thumbnails, nothing to configure into shape. It looks and feels like a system component.

![The WindowHop switcher](docs/screenshots/switcher-light.png)

## Download

**[⬇ Download the latest release](https://github.com/martonpaulo/windowhop/releases/latest)** — free and open source.

## Features

- **One entry per window**, with its app icon and title. Tabs never clutter the list —
  a Safari window with 5 tabs is one entry with a quiet "5 tabs" hint.
- **Real most-recently-used order** at the window level; the first Tab press always
  selects the window you used before this one.
- **Everything included by default**: windows from other Spaces, other displays, and
  full-screen windows. Minimized windows and hidden apps stay out of the way.
- **Two ways to switch**: hold-based ⌘Tab (release to switch), or the optional
  **Open WindowHop** shortcut that keeps the switcher open hands-free.
- **Close windows from the switcher** (Delete), always with a confirmation.
- **Native to the bone**: system materials and colors, Light/Dark Mode, Reduce
  Transparency, Increase Contrast, Reduce Motion, VoiceOver announcements.
- **Private by design**: no telemetry, no accounts, no previews, never asks for
  Screen Recording. Automatic update checks are the only network activity.

## Install

1. Download `WindowHop-x.y.z.dmg` (or the ZIP) from the
   [latest release](https://github.com/martonpaulo/windowhop/releases/latest).
2. Open the DMG and drag **WindowHop** into **Applications**.
3. **First launch:** right-click WindowHop.app and choose **Open**, then confirm.
   (Releases are not notarized by Apple — see [Known limitations](#known-limitations) —
   so macOS asks once. If macOS still refuses, allow it under
   System Settings → Privacy & Security.)

### The one permission it needs

WindowHop needs **Accessibility** access — that's how macOS lets it list windows and
switch to them:

> System Settings → Privacy & Security → **Accessibility** → enable **WindowHop**

WindowHop shows a welcome window that takes you there on first launch. It never asks
for Screen Recording or anything else.

## Keyboard controls

| Keys | Action |
|---|---|
| **⌘ Tab** | Open the switcher and select your previous window |
| **⌘ Tab Tab…** (keep holding ⌘) | Cycle forward |
| **⌘ ⇧ Tab** | Cycle backward |
| **Release ⌘** | Switch to the selected window |
| **← → ↑ ↓** | Navigate |
| **Return** | Switch to the selected window |
| **Escape** | Cancel, stay where you were |
| **Delete (⌫)** | Close the selected window (asks first) |
| **Click** | Switch to a window; click outside cancels |

The switcher chord can be changed to ⌥Tab or ⌃Tab in Settings.

### The "Open WindowHop" shortcut

Prefer not to hold a modifier? Assign a second shortcut (for example ⌥Space) in
Settings. Pressing it opens the switcher and *keeps it open*: navigate with Tab,
Shift-Tab, or arrows; switch with Return, Space, or a click; cancel with Escape.
Releasing modifiers does nothing in this mode. It is unassigned by default.

## Settings

![Settings](docs/screenshots/settings-light.png)

Launching WindowHop again (from Finder, Spotlight, or the Dock) opens Settings even
when the menu bar item and Dock icon are hidden — both are hidden by default.

## Automatic updates and privacy

WindowHop updates itself through [Sparkle](https://sparkle-project.org): it checks a
feed on GitHub, and updates are cryptographically signed (EdDSA) and verified before
installing. You can turn automatic checks off, or check manually, in Settings.
**Update checks are WindowHop's only network activity.** There is no telemetry, no
analytics, and no account. Everything works offline except updating.

## Build from source

Requires macOS 14+ and Xcode 16+ (free). No paid Apple account needed.

```sh
git clone https://github.com/martonpaulo/windowhop && cd windowhop
swift test                # run the test suite
scripts/package-app.sh    # build build/WindowHop.app (ad-hoc signed)
cp -R build/WindowHop.app /Applications/
```

Development docs: [architecture](docs/architecture.md) · [testing](docs/testing.md) ·
[contributing](CONTRIBUTING.md) · [upstream attribution](UPSTREAM.md)

## Troubleshooting

- **⌘Tab shows the old macOS switcher** — WindowHop is not running, is disabled in
  Settings, or lost its Accessibility permission. That's by design: whenever WindowHop
  can't do its job, native switching keeps working.
- **Nothing happens after an update or macOS upgrade** — re-grant Accessibility in
  System Settings (remove WindowHop from the list and add it again), then relaunch.
- **A window is missing from the switcher** — minimized windows and hidden apps are
  excluded on purpose. A window that lives on another Space appears after you visit
  that Space once (a macOS API limitation, below).
- **Typing a password and ⌘Tab behaves natively** — secure input temporarily blocks
  all keyboard interception; WindowHop resumes automatically.

## Known limitations

- **Not notarized.** Notarization requires a paid Apple Developer account, so macOS
  shows a one-time warning on first launch. The release workflow signs and notarizes
  automatically as soon as Developer ID credentials are configured.
- **Windows on unvisited Spaces** appear only after that Space is visited once while
  WindowHop runs. macOS's public Accessibility API doesn't enumerate them earlier
  (AltTab works around this with private APIs; WindowHop deliberately uses none).
- **Tab counts** appear only for apps that expose native tab groups to Accessibility
  (Safari, Finder, Terminal, TextEdit, …). Chrome and other custom-tab apps show
  no count — WindowHop never guesses.
- English-only interface in this release.

## License and attribution

[GPL-3.0](LICENSE). WindowHop is derived from
[AltTab](https://github.com/lwouis/alt-tab-macos) by Louis Pontoise (lwouis) and
contributors — base tag `v10.12.0` (`317a485b`), with the full upstream history
preserved in this repository. See [UPSTREAM.md](UPSTREAM.md) for exactly what was
retained, rewritten, and removed. Thank you, AltTab.
