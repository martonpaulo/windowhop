# WindowHop

**Switch between windows, not just apps.**

[![Latest release](https://img.shields.io/github/v/release/martonpaulo/windowhop)](https://github.com/martonpaulo/windowhop/releases/latest)
[![CI](https://github.com/martonpaulo/windowhop/actions/workflows/ci.yml/badge.svg)](https://github.com/martonpaulo/windowhop/actions/workflows/ci.yml)
[![License: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-blue)](LICENSE)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black)

**[Visit the WindowHop website](https://martonpaulo.github.io/windowhop/)**

macOS Command-Tab switches between *apps*. WindowHop gives every top-level window its
own tile, then lands on the exact window you select — including windows on another Space
or display. It is native, free, open source, and contains no telemetry.

![WindowHop App Icons in Light Mode with a borderless selected background](docs/screenshots/switcher-light.png)

Prefer snapshots? Enable **Window Previews** in Settings → Appearance.

![WindowHop previews in Light Mode with semantic surfaces, selected treatment, tall-window letterboxing, loading and unavailable states](docs/screenshots/switcher-previews-light.png)

## Download and install

1. Download **[WindowHop 1.3.1](https://github.com/martonpaulo/windowhop/releases/latest)**.
   The `WindowHop-1.3.1-Installer.zip` asset preserves the branded Finder icon; the
   release also provides the raw `WindowHop-1.3.1.dmg`.
2. Unzip the installer if needed, open the DMG, and drag WindowHop to Applications.
3. Open WindowHop from Applications and grant
   **System Settings → Privacy & Security → Accessibility**.

Official releases are signed with WindowHop's stable Developer ID identity, notarized
by Apple, stapled, and Gatekeeper-validated before publication.

![Branded WindowHop DMG with the app and real Applications alias](docs/screenshots/installer-dmg.png)

## Using WindowHop

| Keys | Action |
|---|---|
| **⌘⇥** | Open and select the previous window |
| **⌘⇥⇥…** while holding ⌘ | Cycle forward |
| **⇧⌘⇥** | Cycle backward |
| **Release ⌘** | Confirm and activate the selected window |
| **← → ↑ ↓** | Navigate |
| **↩** or **Space** | Confirm the selected window |
| **⎋** | Cancel without changing the desktop |
| **⌫** | Close the selected window after confirmation |
| **⌘,** | Open Settings without confirming or cancelling |
| **Click** | Confirm a tile; click outside to cancel |

Hovering reveals a Close control centered on the preview canvas's top-left point. It
always targets that tile and uses a 44 pt hit area without moving the card. During normal
cycling, the global Settings control appears only while the pointer is anywhere over the
panel. It remains visible for the complete persistent **Open WindowHop** session. In both
cases it overlaps the top-right corner without taking layout space or moving previews.
Close always asks first; Quit is graceful, and Force Quit has its own second warning.

### Expanded preview after pausing

Pause on the selected tile for the configured delay (3 seconds by default) and
WindowHop enlarges the latest snapshot **inside the switcher**. It never activates,
raises, focuses, reorders, or moves the real window. Navigation remains available;
moving to another tile closes the expanded view and starts a new delay. Confirming
activates the current target immediately. Cancelling leaves the originally focused
window and desktop stacking unchanged.

![Expanded in-panel preview in Light Mode](docs/screenshots/switcher-expanded-light.png)

![Expanded in-panel preview in Dark Mode](docs/screenshots/switcher-expanded-dark.png)

### One entry per window

Tabs are never separate switcher entries. Finder, Safari, and Terminal tab groups collapse
to their visible top-level window. Optional tab-count metadata is hidden by default and
can be enabled in Settings → Appearance without changing preview width.

### Open WindowHop shortcut

Use **⌥Tab** (configurable in Settings → General) when you do not want to hold a modifier.
It opens a sticky session: Tab, Shift-Tab, and arrows navigate; Return or Space confirms;
Escape cancels.

## Preview behavior and permissions

**App Icons** is the default and needs no Screen Recording permission. **Window
Previews** uses ScreenCaptureKit only while the switcher is open. Captures remain in
memory and are never written to disk or transmitted. A cached preview may appear first;
a fresh capture replaces it in place.

Every preview keeps one fixed display-ratio canvas. Wide, tall, and narrow windows are
scaled proportionally and centered over an adaptive semantic surface — never stretched,
cropped, or left as a transparent hole. The app badge remains attached to the canvas's
bottom-right corner in every state.

| State | What WindowHop shows |
|---|---|
| Capturing | A gently pulsing macOS-window skeleton |
| Screen Recording is missing | A static subdued skeleton; one panel-level Settings action |
| Capture failed while permission exists | A static unavailable skeleton |
| Capture succeeded | The current snapshot |

Missing permission is checked before capture starts, so it cannot masquerade as loading
or enter a retry loop. Returning from Privacy & Security refreshes the state; once
permission exists, capture starts without moving the cards.

![Permission-blocked preview skeletons in Light Mode](docs/screenshots/switcher-permission-blocked-light.png)

![Permission-blocked preview skeletons in Dark Mode](docs/screenshots/switcher-permission-blocked-dark.png)

## Settings and defaults

Settings has four native panes: General, Appearance, Updates, and About. Changes persist
and apply immediately when safe; invalid stored values restore documented defaults.

### General

- Enable WindowHop — **on**
- Launch at login — **on**
- Switcher shortcut — **⌘Tab**
- Open WindowHop shortcut — **⌥Tab**
- Include windows from other Spaces — **on**
- Include windows from other displays — **on**
- Include minimized windows — **off**
- Include windows from hidden applications — **off**
- Include Picture-in-Picture windows — **off**
- Show menu bar item — **off**
- Show Dock icon — **off**
- Restore Defaults… — confirmed action that restores every configurable preference

The default is intentionally a curated set of normal windows. Inclusion toggles are
explicit opt-ins, rebuild the available list, and do not weaken the invariants that
exclude menus, tooltips, tab siblings, system overlays, or WindowHop's own helper UI.

![Settings General with the Windows shown section](docs/screenshots/settings-general.png)

### Appearance

- Switcher shows — **App Icons** or Window Previews; default **App Icons**
- Show tab counts — **off**
- Show an expanded preview after pausing — **Off, 1, 2, 3, or 5 seconds**; default
  **3 seconds**
- Screen Recording status and the single permission action for Window Previews

![Settings Appearance with expanded-preview and Screen Recording controls](docs/screenshots/settings-appearance.png)

### Updates and About

Automatic checks are enabled by default. Sparkle verifies the EdDSA signature and Apple
code signature before replacing the app in place; the Settings pane also offers a manual
check. About identifies **Developed by Marton Paulo** and links to the official WindowHop
website, source, issue tracker, GPL-3.0 license, and AltTab acknowledgement.

![Settings Updates](docs/screenshots/settings-updates.png)

![Settings About](docs/screenshots/settings-about.png)

## Interface gallery

These images are generated by the app's release-equivalent render harness with synthetic
titles and preview content — no personal windows or Screen Recording data.

![WindowHop App Icons in Dark Mode](docs/screenshots/switcher-dark.png)

![WindowHop previews in Dark Mode with selected, letterboxed, loading and unavailable cards](docs/screenshots/switcher-previews-dark.png)

![WindowHop responsive multi-row layout with consistent row spacing](docs/screenshots/switcher-overflow.png)

## Updates, signing, and privacy

WindowHop uses [Sparkle](https://sparkle-project.org) and GitHub Releases. Update checks
are its only network activity. There are no accounts, analytics, advertising, or
telemetry. Official release automation refuses to publish if the Developer ID identity,
nested signatures, hardened runtime, designated requirement, notarization, stapling,
Gatekeeper assessment, DMG branding, or Sparkle signature is missing or inconsistent.

The bundle identifier, Team ID, leaf Developer ID certificate, entitlements, and exact
designated requirement are validated against the previous official release. This keeps
macOS TCC permissions associated with the same code identity across Sparkle updates and
manual in-place replacement.

### One-time recovery for an already-corrupted grant

Only users whose Accessibility entry was created by an old ad-hoc, development-signed,
translocated, or otherwise differently identified build may need one repair: remove the
stale WindowHop entry from Privacy & Security → Accessibility, install the current
official build in Applications, and grant it once. Normal signed updates must not require
this again.

## Troubleshooting

- **⌘Tab shows Apple's switcher** — WindowHop is not running, is disabled, or lacks
  Accessibility. This is the fail-safe; WindowHop never disables the native shortcut.
- **Window Previews remain static** — use the one panel or Settings action to open Screen
  Recording, enable WindowHop, then return to the app. App Icons remains fully usable
  without it.
- **A window is missing** — minimized, hidden-app, and PiP windows are excluded by
  default and can be enabled under General → Windows shown. Public Accessibility APIs
  reveal an unvisited Space only after you visit it once.
- **A previous build's Accessibility toggle does not stick** — ensure WindowHop is in
  Applications and use the one-time recovery above. Running directly from Downloads or
  the DMG can trigger App Translocation.
- **Secure input is active** — password fields make WindowHop pass ⌘Tab through to the
  native switcher until secure input ends.

## Uninstall

Quit WindowHop, delete `/Applications/WindowHop.app`, and optionally run
`defaults delete com.perso.windowhop`. You can also remove WindowHop from Accessibility
and Screen Recording in System Settings.

## Build from source

Requires macOS 14+ and Xcode 16+.

```sh
git clone https://github.com/martonpaulo/windowhop
cd windowhop
swift build && swift test
scripts/validate.sh
scripts/package-app.sh 1.3.1 10301
scripts/make-dmg.sh 1.3.1
```

Local packages are ad-hoc signed unless `DEVELOPER_ID_IDENTITY` names the approved
Developer ID identity. Official tags run the fail-closed signing, notarization, stapling,
Gatekeeper, Sparkle, and GitHub Release workflow.

Docs: [architecture](docs/architecture.md) · [testing](docs/testing.md) ·
[feature defaults](docs/feature-defaults.md) · [website deployment](docs/website.md) ·
[contributing](CONTRIBUTING.md) · [upstream attribution](UPSTREAM.md)

## Known limitations

- Other-Space windows become discoverable only after that Space has been visited while
  WindowHop runs; WindowHop deliberately uses no private APIs.
- Tab counts exist only for apps exposing native tab groups and are never guessed.
- Screen Recording's public preflight API distinguishes authorized from unavailable but
  does not expose whether an unavailable grant is specifically denied or restricted;
  both correctly use the static permission-blocked fallback and single recovery action.
- English-only interface in this release.

## License and attribution

[GPL-3.0](LICENSE). Derived from
[AltTab](https://github.com/lwouis/alt-tab-macos) by Louis Pontoise (lwouis) and
contributors — base tag `v10.12.0` (`317a485b`), with upstream history preserved.
See [UPSTREAM.md](UPSTREAM.md).
