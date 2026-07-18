# Changelog

## 1.2.0 — 2026-07-18

- **Branded macOS installer**: the automated appdmg build now produces a compact custom
  WindowHop installation window with real draggable app/Applications items, branded
  background, custom mounted-volume icon, and a complete multi-resolution Finder icon.
  The release also wraps the DMG in a resource-fork-preserving installer ZIP.
- **Stable release identity**: official builds are checked against the reviewed Developer
  ID leaf certificate and exact designated requirement. Bundle/team identity, hardened
  runtime, entitlements, nested executable signatures, notarization, stapling,
  Gatekeeper, and Sparkle signing all fail closed before publication.
- **Permission-aware previews**: Screen Recording is classified before capture begins.
  Missing permission uses a dedicated `Permission required` canvas and one panel action;
  authorized capture distinguishes `Loading preview…` from `Preview unavailable` and
  handles revocation without retry loops.
- **Configurable windows shown**: General now owns one shared filtering policy for other
  Spaces/displays and opt-in minimized, hidden-application, and Picture-in-Picture
  windows. Existing curated behavior remains the default and changes apply immediately.
- **Non-activating dwell preview**: pausing for 3 seconds by default enlarges the latest
  snapshot inside WindowHop. Target changes cancel stale work; only confirmation activates
  the real window, while cancellation leaves desktop focus and stacking untouched.
- **Apple-style preview surfaces**: unselected cards drop heavy permanent frames in favor
  of an adaptive surface and shallow rounded shadow. Selection is one appearance-aware
  background plate, App Icons remains borderless, and letterboxing/loading/fallback states
  share the same intentional semantic canvas.
- **Documentation and visual regressions**: privacy-safe Light/Dark, permission, expanded,
  Settings, overflow, and DMG captures now match 1.2.0. Tests cover permission states,
  shared filter combinations, overlay geometry, selection semantics, and stale dwell work.

## 1.1.2 — 2026-07-18

- **Native selection for each appearance**: Window Previews uses one 4 pt semantic
  macOS focus ring that replaces its subtle neutral outline for loaded, loading, and
  unavailable canvases. App Icons has no neutral border and follows the native switcher
  idiom with a soft rounded selection background instead of a heavy outline.
- **Calmer multi-row layout**: one shared vertical spacing token separates complete
  cards, including preview overlays, titles, and tab metadata, while the existing
  display-height budget still switches extreme window counts to vertical scrolling.
- **Precise overlay geometry**: Close is centered exactly on the fixed canvas's
  top-left point; app badges remain anchored beyond its bottom-right corner. The global
  Settings control is slightly larger and now keeps most of its hit target inside the
  panel with a small, stable outer overlap.
- **Explicit preview fallback**: failed first captures show a semantic “Preview
  unavailable” placeholder inside the normal canvas. Cached snapshots remain visible,
  and loading, fallback, and loaded transitions never move the badge, border, or title.
- **Configurable navigation preview dwell**: Appearance offers Off, Short, Default
  (700 ms), and Long presets. Rapid traversal cancels superseded work; confirmation is
  immediate, cancellation restores the origin, and temporary focus never becomes MRU
  history.
- **Release integrity and documentation**: official tag workflows now require an
  Apple-issued Developer ID Application certificate plus all notarization credentials,
  wait for acceptance, staple and validate the app and DMG, and run Gatekeeper checks
  before publishing. README screenshots and behavior documentation reflect 1.1.2.

## 1.1.1 — 2026-07-18

- **Complete Settings contract**: every existing user-configurable behavior is exposed
  through the native General, Appearance, or Updates panes. `Preferences` is now the
  single observable runtime model backed by `UserDefaults`; existing values survive,
  and invalid or obsolete shortcut, appearance, and Boolean values restore documented
  defaults.
- **Temporary window activation**: pause on a target and WindowHop raises it behind the
  still-active switcher after a short debounce. Confirm commits that target; Escape or
  outside click restores the exact origin when it still exists. Temporary focus changes
  never rewrite MRU history, and closed origins/targets, rapid traversal, same-app
  windows, modal confirmation, and Settings focus races are covered by regressions.
- **Clear preview boundaries and selection**: uniform horizontal card spacing, a subtle
  outline on every preview, restrained hover/temporary emphasis, and exactly one strong
  blue selected outline that remains legible over bright and dark snapshots without
  moving layout.
- **Canvas-aligned overlays**: the app badge is 60% of its former size at the fixed
  canvas bottom-right and overlaps both edges; Close is 50% of its former rendered size
  over the top-left with a 44 pt hit target. Both stay aligned across wide, tall,
  letterboxed, loading, and unavailable windows.
- **Global Settings control**: the gear is 50% of its former rendered size and overlays
  the panel with its center on the top-right corner, without a reserved chrome strip,
  preview displacement, or visible-panel size changes.
- **Consistent preview geometry**: source images remain proportional, centered, and
  transparently letterboxed while outline, selection, shadow, overlays, hit testing, and
  title rhythm all follow the display-ratio preview canvas.

## 1.1.0 — 2026-07-18

- **Live preview refresh**: opening the switcher still shows cached snapshots
  instantly, but each tile now crossfades to a fresh capture the moment it
  lands — no more stale previews for the whole session. Late captures for
  closed windows are discarded (new tested PreviewLedger), and regression
  tests pin previews to their window id so a snapshot can never appear on
  another window's card.
- **Picture-in-Picture windows are excluded** — browser PiP (Chrome/Brave/
  Safari) and native floating video panels no longer clutter the switcher.
  Detection is behavior-based (the window server keeps PiP panels floating
  above normal windows), not an app-name list; fullscreen surfaces like
  Keynote presentations stay listed.
- **Preview cards redesigned**: every preview container now uses the display's
  aspect ratio, so all cards are identical; snapshots aspect-fit, centered,
  with transparent letterboxing. Captures no longer bake in the system window
  shadow — the tile draws its own shadow along the preview's rounded shape
  (no more rectangular halo around rounded windows). The selection highlight
  surrounds only the preview, leaving the title outside, and single-line
  titles center vertically in the two-line title zone.
- **Bigger overlay controls**: the app-icon badge on previews is 2× larger,
  and the close and Settings controls are 3× larger, with the panel reserving
  a chrome strip so the gear never covers tiles.
- **Native glass panel**: on macOS 26 the switcher background is the system
  glass material (NSGlassEffectView), matching the native ⌘⇥ switcher; older
  systems keep the HUD material fallback. Both respect Reduce Transparency.
- **Update notice in Settings**: the Updates pane now shows "WindowHop X.Y.Z
  is available" with an Install Update button when the scheduled Sparkle check
  finds a newer version (the standard Sparkle prompt still handles install /
  remind-later / skip).
- **Polished DMG installer**: background artwork with drag-to-Applications
  guidance, fixed icon layout, a volume icon, and a matching file icon —
  generated headlessly (appdmg), so CI produces the full layout too.

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
