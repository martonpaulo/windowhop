# Changelog

All notable changes to WindowHop are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.1.0] - 2026-09-23

### Changed

- **Grant Accessibility again after this update**: WindowHop has a new bundle identifier,
  `com.martonpaulo.windowhop`, and macOS treats it as a new app. After the update,
  WindowHop opens its setup window: grant Accessibility again, and Screen Recording again
  if you use Window Previews. You can then remove the old WindowHop entries from System
  Settings › Privacy & Security › Accessibility and Screen Recording. Your settings are
  copied on the first launch and keep their values. If Launch at login was on, WindowHop
  registers itself again; macOS can ask you to approve it in Login Items.
- **Settings is shorter and easier to scan**: four panes instead of six. General shows
  whether WindowHop is on and whether Accessibility is allowed. Shortcuts lists the keys
  that work in the switcher, one row per action. Switcher holds the style, the windows it
  lists and where it appears, with one menu for the display. About holds the version,
  updates and credits. Each pane is as tall as its content, and every setting keeps its
  value.
- **Settings are stored under versioned names**: the first launch of this version moves
  every setting you chose to its new name and keeps its value. An older WindowHop version
  started afterwards keeps the settings it had before this update, and changes made in
  this version do not reach it.

### Fixed

- **Windows no longer disappear after the screen locks**: after a lock, a Screen Sharing
  reconnect, a user switch or a sleep, the switcher could list only the current window
  until you changed Space or restarted WindowHop. WindowHop now ignores what apps report
  while the screen is locked, and checks every window again as soon as you are back.

## [2.0.0] - 2026-09-23

### Added

- **Settings shows how to switch windows**: General now opens with a "Switch windows"
  section that explains holding the switcher shortcut and releasing it to switch, and
  opening WindowHop with its own shortcut and confirming with Return or Space. It uses
  the shortcuts you have set and updates as soon as you change them.
- **The shortcut recorder warns about conflicts**: recording ⌘Q, ⌘W, ⌘, or another
  standard app command as the Open WindowHop shortcut is refused with the command's name,
  since WindowHop would take it over in every app; so are the Force Quit shortcuts. A
  chord that macOS itself uses, such as ⌘Space, asks first, and Cancel keeps your previous
  shortcut. Shortcuts you already have are kept as they are.
- **About shows when your build was released**: Settings → About and Updates now show the
  release date next to the version and build, in your language's date format. Development
  builds say "Development build" instead of an invented version.
- **The menu bar item shows when WindowHop is paused or needs Accessibility access**: its
  symbol changes shape, VoiceOver reads the state, and its menu explains it, with a shortcut
  to Accessibility setup when access is missing.
- **A complete menu bar with the Dock icon on**: when "Show Dock icon" is enabled, the
  WindowHop menu now offers Services, Hide WindowHop (⌘H), Hide Others (⌥⌘H) and Show All,
  the Window menu offers Zoom, and a Help menu offers Report an Issue….
- **Settings reopens where you left it**: the Settings window keeps its position across
  launches instead of re-centering every time, and returns to the main display when the
  display it was on is no longer connected.
- **The website compares WindowHop with AltTab**: a new section explains when WindowHop
  suits you and when AltTab is the better choice, and the page title and description now
  name WindowHop as a free Mac window switcher and AltTab alternative.

### Changed

- **The switcher stays responsive while windows move**: with many windows open, dragging
  or resizing a window, or a changing window title, no longer redraws every card in the
  open switcher. Only the cards whose window changed are redrawn, so the arrow keys keep
  responding at once.
- **Diagnostics go to the macOS unified log**: to investigate a switching or shortcut
  problem, run `log stream --level debug --process WindowHop` in Terminal while you
  reproduce it. The `WINDOWHOP_DEBUG` environment variable no longer exists.
- **The website downloads the disk image directly**: Download on
  windowhop.martonpaulo.com now gets `WindowHop-<version>.dmg` instead of a ZIP you had
  to unzip first, and the download section shows how many times WindowHop was downloaded.
  The number is taken from GitHub's public release data when the site is published; the
  page itself makes no request for it.
- **The website shows how to install and get help**: a new Install section walks from the
  download to your first ⌘Tab, including the first-launch prompt and the Accessibility
  permission, and a Help section covers "⌘Tab still shows Apple's switcher" and how to
  uninstall. Accent text on the light page now meets WCAG AA contrast.
- **Settings no longer opens at every launch**: once the first launch is done and you
  show the menu bar item or the Dock icon, starting WindowHop opens nothing. With both
  icons hidden it still opens Settings, and opening WindowHop again while it runs always
  does. If Accessibility is missing, the setup window opens on any launch, including at
  login.
- **One About for WindowHop**: WindowHop › About WindowHop now opens Settings → About, the
  same page the Settings toolbar shows, instead of a separate About window. Its copyright
  line is the one the app bundle carries.
- **Report an Issue… fills in your versions**: from Settings → About or the Help menu, it
  now opens the bug report form with your WindowHop version, build, release date and macOS
  version already entered. Nothing else is included, and nothing is sent until you review
  and submit the form.
- **Launch at login is off for new installs**: turn it on in Settings → General. Existing
  installations keep their current choice, including the previous On default.
- **Restore Defaults leaves launch at login alone**: it no longer registers or removes the
  login item, so it cannot fail and never changes system settings.
- **WindowHop now requires macOS 26 or later**: Macs on macOS 14 or 15 keep the current
  version and are not offered this update.
- **Same-named windows show their folder**: when two windows of one app have the same
  title, such as two `Notes.txt` documents, each tile and its VoiceOver label now add the
  name of the folder the document is in. Windows without a saved document, such as two
  Untitled ones, keep their title as it is.
- **The expanded-preview delay says when it applies**: Settings → Appearance now disables
  the "Show an expanded preview after pausing" picker in App Icons mode and states that it
  works with Window Previews only. Your chosen delay is kept and returns when you switch
  back to Window Previews.
- **Sparkle 2.10.0 handles updates**: the updater framework moves from 2.9.6 to 2.10.0,
  with upstream fixes for update download progress and cleanup after a failed delta
  update. Updates keep the same signature checks.
- **A clearer website icon in browser tabs and search results**: the website's favicon
  now fills its square with a bolder hop arrow, so the WindowHop mark stays readable at
  16 to 48 pixels. The app icon itself is unchanged.

### Fixed

- **Window previews recover from a short capture failure**: when macOS fails to capture a
  window for a moment, WindowHop now tries that window once more during the same switcher
  session, so its preview can appear without closing and reopening the switcher. A window
  that cannot be captured still shows its placeholder at once.
- **No pause when windows open during a Window Previews session**: WindowHop now checks
  the Screen Recording permission once when the switcher opens, instead of once for each
  window that appears while it is open. Each check took about 15 ms, so several new
  windows could make the switcher stop responding for a moment.
- **A key release is no longer swallowed after macOS pauses WindowHop's keyboard
  monitor**: if macOS paused it (after a slow moment or sleep) while you
  still held Tab from a switch, the next release of Tab could be hidden from the app you
  were typing in, or from the native ⌘Tab switcher. The next press of that key now
  corrects it.
- **Merged windows become one entry right away**: after Window › Merge All Windows, the
  next switcher session shows the merged window once, with its tab count, instead of
  listing every former window until something else changed.
- **Floating windows stay in the switcher**: an app's ordinary window that floats above
  the others, such as a pinned document or an always-on-top dialog, is no longer mistaken
  for Picture in Picture and hidden. Browser Picture in Picture, in Chrome, Brave, Edge,
  Firefox and Zen, is still left out unless you include it in Settings.
- **A tab moved to its own window shows up again**: after Window ▸ Move Tab to New Window
  splits a two-tab group, both windows now appear in the switcher. The window left behind
  used to stay hidden as if it were still a tab.
- **Alerts and open panels stay in the switcher**: an app's alert or Open/Save panel shown
  in its own window, such as an update prompt, is no longer mistaken for Picture in
  Picture and hidden.
- **Window Previews use far less memory after dwelling**: each expanded preview used to
  stay in memory, about nine times the size of a card's snapshot, for every window you
  had dwelled on, until the window closed. Now only the latest one is kept, and only
  while the switcher is open; cards keep their own snapshot as before.
- **Launch at login shows what macOS actually holds**: the toggle in Settings → General
  now reads the real login-item status instead of remembering what you last clicked.
  When macOS waits for your approval, it says so and offers Open Login Items Settings….
  Changes you make in System Settings appear as soon as you return to WindowHop.
- **Closing a same-named window names its folder**: the close confirmation and the
  expanded preview now show the same folder-qualified title as the tile, such as
  "Notes.txt — Work", so you can tell which of two same-named windows you are closing.
- **Shortcuts show the letter your keyboard types**: on layouts such as German or French,
  the Open WindowHop shortcut used to be shown and spoken with US letters, so a recorded
  ⌥Y read as ⌥Z. Letters and symbols now follow your current keyboard layout and update
  when you switch input sources; the shortcut itself stays on the same physical key.
- **VoiceOver reads the Open WindowHop shortcut field completely**: the recorder now
  speaks the current chord in words ("Option Tab"), says "None" when it is cleared and
  "Recording" while it waits for a chord, explains that Escape cancels and Delete clears,
  and announces why a chord was rejected.
- **Windows no longer vanish when an app is slow during a Space switch**: with other Spaces
  hidden, an app that did not answer in time had all its windows treated as off-Space until
  the next focus change. They now stay where they were last seen.
- **VoiceOver names each selection once**: with the switcher shown on several displays,
  every panel announced the same selection, so it was spoken once per display.
- **VoiceOver follows the selection when its window closes**: if the selected window
  disappeared while the switcher was open, VoiceOver kept naming it while Return would
  activate a different window. The new target is now announced.
- **Preview cards no longer pulse forever**: a window whose preview could not be captured,
  or every card while Screen Recording was off, went back to the animated loading
  placeholder as soon as any window changed its title or the list reordered. Those cards
  now stay a calm static placeholder for the rest of the session.
- **Recording a shortcut no longer opens the switcher**: while Settings records the Open
  WindowHop shortcut, pressing a chord WindowHop already uses reaches the recorder instead
  of opening a session. ⌘Tab reaches macOS as it does in any shortcut field, and
  interception resumes as soon as recording ends.
- **VoiceOver commands work while the switcher is open**: ⌃⌥ with an arrow, Space, Return
  or Delete now reaches VoiceOver instead of moving the switcher. Keys still navigate with
  the modifier you hold (⌘ + arrows after ⌘Tab) or with none in a persistent session.
- **Open WindowHop never shadows the switcher shortcut**: an installation that cycles with
  ⌥Tab and never chose an Open WindowHop shortcut received ⌥Tab for both, so Open WindowHop
  could not fire. A chord that conflicts with the switcher shortcut now loads as unassigned,
  exactly as when you pick a conflicting pair in Settings; every other choice is kept.
- **Check for Updates… stays in the menu bar item**: when the menu bar item was already on
  at launch, its menu never offered Check for Updates…. The menu now shows it whenever the
  updater is running, and dims it while a check is already in progress.
- **A window no longer disappears because it shares a tab's title**: when an independent
  window had the same title as an inactive tab of another window in the same app, the
  independent window could be hidden while the tab showed up instead. Tabs are now
  matched by position as well as title, and a window that cannot be told apart stays
  visible.
- **A tab no longer pops out as its own window when an app answers slowly**: if one
  tab of a native tab group could not be read, the remaining tabs were treated as the
  whole group and the unread tab appeared as a separate switcher entry. An incomplete
  read now leaves the group as it was until the next complete one.
- **Tabs of a background app stay grouped at startup**: when WindowHop found a window's
  visible tab before its other tabs, those tabs could show up as separate entries until
  the app was focused. Tabs are now grouped whichever order they are found in.

## [1.6.2] - 2026-09-09

### Changed

- **The website moved to windowhop.martonpaulo.com**: the About window and the website link
  now open <https://windowhop.martonpaulo.com/>.

## [1.6.1] - 2026-09-08

### Changed

- Updated Sparkle to 2.9.6.

### Fixed

- **Window previews are readable again on wide displays**: every preview card took its
  shape from the monitor, so on an ultrawide screen the snapshot shrank to a thin strip
  exactly where previews are hardest to recognize. Cards now use one fixed 16:10 canvas on
  every Mac. The expanded preview shown after pausing goes further and takes the shape of
  the window it is showing, so the snapshot fills it instead of floating in empty space.
- **The expanded preview stays put**: an unrelated window changing its title, moving, or
  appearing used to collapse an open expanded preview for the rest of the session. It now
  survives anything that does not change the selected window. If the first snapshot is
  still being captured when the pause elapses, the preview opens as soon as it arrives
  instead of never appearing.
- **VoiceOver can activate a window**: window tiles announced themselves as buttons but did
  nothing when activated through VoiceOver. Pressing one now switches to that window, and
  it can no longer be confused with the separate Close action.
- **Two tab groups in one app stay collapsed**: refreshing one native tab group dissolved
  the others in the same application, so their hidden tabs reappeared as separate entries.
  Each group is now independent.
- **Settings is listed on the display it is actually on**: dragging the Settings window to
  another display left it filed under the display it opened on while
  "Include windows from other displays" was off.
- **A conflicting Open WindowHop shortcut is rejected again**: after changing the switcher
  shortcut, recording a chord that collided with the new one was saved silently and then
  opened the wrong kind of session.
- **No terminal window at login for development builds**: enabling "Launch at login" from a
  build that is not a real app bundle registered that bare executable, which opened a
  terminal window at the next login. It is now refused, with the existing explanation.
- **Honest permission onboarding**: the first-run screen claimed WindowHop never records the
  screen and never uses the network. It now explains that Accessibility is the only
  permission always required, that Window Previews asks for Screen Recording and keeps its
  snapshots in memory, and that the network is used only for updates.
- **Readable download buttons on the website**: the primary download buttons did not meet
  the minimum text contrast, in Light Mode and much less in Dark Mode.
- Preview snapshots of a window are released on every path that removes it, so repeatedly
  opening and closing Settings no longer leaves stale images in memory.

## [1.6.0] - 2026-08-07

### Added

- **Choose which displays the switcher appears on**: WindowHop now opens on every display
  by default, instead of picking one for you. Settings → Windows also offers the display
  with the pointer — the one you are actually looking at — or one specific display you
  choose. A chosen display is remembered by a stable identifier, so unplugging it falls
  back to the display with the pointer and reconnecting restores your choice without
  reconfiguring anything. Single-display Macs are unaffected.

## [1.5.0] - 2026-07-27

### Changed

- **Windows that open while the switcher is up now show up**: the list used to be frozen
  the moment you opened WindowHop, so an app launching, a new document, or a dialog
  appearing behind the panel stayed invisible until you closed and reopened the switcher.
  New windows are now appended to the end of the open list — every tile you were already
  cycling through keeps its position, so nothing moves under your fingers — and in Window
  Previews mode the new tile gets its own snapshot without disturbing the captures still
  filling in.

## [1.4.0] - 2026-07-24

### Changed

- **Documentation captures**: the published screenshots are a smaller, curated set, and
  the Settings images are now the real window — title bar, toolbar, and all six panes'
  identical frame — instead of an offscreen crop of one pane.
- **One Settings window size**: panes no longer resize the window. General is split into
  General, Shortcuts, and Windows, every pane renders into one shared canvas (and scrolls
  if it ever outgrows it), and the selected pane is restored by identifier so future panes
  cannot shift it.

### Fixed

- **The right preview on the right window**: Accessibility and the window server spell the
  same window's title differently (Chromium reports `Page – Brave – Profile` where the
  window server knows only `Page`), so same-sized windows of one app used to fall back to
  window-server order and could show each other's snapshot. Matching now scores pid, frame,
  and decoration-tolerant titles, accepts a pair only when it is the unambiguous best
  choice for both sides, and leaves genuinely indistinguishable windows without a preview
  instead of guessing. Long titles the window server reports with their middle elided are
  recognized too, verified against real stacked browser windows.

## [1.3.1] - 2026-07-18

### Added

- **About and product website**: About now identifies developer Marton Paulo and links to
  the official responsive GitHub Pages site. The zero-backend site includes current
  product visuals, direct downloads, release notes, GPL-3.0 source, issue reporting, and
  AltTab acknowledgement in adaptive Light and Dark appearances.

### Changed

- **Centralized defaults and safe reset**: every user preference now consumes one typed
  `Preferences.Defaults` contract. Fresh installs use ⌘Tab and ⌥Tab with tab counts hidden;
  upgrades retain saved choices, and the confirmed Restore Defaults action resets every
  configurable value without touching permissions, identity, or first-run state.
- **Contextual switcher chrome**: Settings stays out of normal cycling until the pointer
  enters the panel, while persistent Open WindowHop sessions keep it visible. The overlay
  never changes panel measurement, preview placement, or keyboard navigation.
- **Polished card hierarchy**: native system typography strengthens titles, optional tab
  metadata leaves no hidden row, and loading/failure copy is replaced by explicit animated
  or static macOS-window skeleton states that respect Reduce Motion.
- **Regression coverage and documentation**: typed reset coverage fails when a future
  preference is omitted; shortcut interception, contextual gear visibility, compact
  metadata layout, shared typography, and skeleton domain states are tested. README,
  release metadata, and privacy-safe screenshots reflect 1.3.1.

### Fixed

- **Reliable shortcut ownership**: WindowHop now consumes the complete configured
  Command–Tab key sequence, including rapid release, reverse cycling, repeated input, and
  re-arming after sleep/wake. No new preference was added for this correctness fix.

## [1.2.0] - 2026-07-18

### Added

- **Configurable windows shown**: General now owns one shared filtering policy for other
  Spaces/displays and opt-in minimized, hidden-application, and Picture-in-Picture
  windows. Existing curated behavior remains the default and changes apply immediately.
- **Non-activating dwell preview**: pausing for 3 seconds by default enlarges the latest
  snapshot inside WindowHop. Target changes cancel stale work; only confirmation activates
  the real window, while cancellation leaves desktop focus and stacking untouched.

### Changed

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
- **Apple-style preview surfaces**: unselected cards drop heavy permanent frames in favor
  of an adaptive surface and shallow rounded shadow. Selection is one appearance-aware
  background plate, App Icons remains borderless, and letterboxing/loading/fallback states
  share the same intentional semantic canvas.
- **Documentation and visual regressions**: privacy-safe Light/Dark, permission, expanded,
  Settings, overflow, and DMG captures now match 1.2.0. Tests cover permission states,
  shared filter combinations, overlay geometry, selection semantics, and stale dwell work.

## [1.1.2] - 2026-07-18

### Added

- **Explicit preview fallback**: failed first captures show a semantic “Preview
  unavailable” placeholder inside the normal canvas. Cached snapshots remain visible,
  and loading, fallback, and loaded transitions never move the badge, border, or title.
- **Configurable navigation preview dwell**: Appearance offers Off, Short, Default
  (700 ms), and Long presets. Rapid traversal cancels superseded work; confirmation is
  immediate, cancellation restores the origin, and temporary focus never becomes MRU
  history.

### Changed

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
- **Release integrity and documentation**: official tag workflows now require an
  Apple-issued Developer ID Application certificate plus all notarization credentials,
  wait for acceptance, staple and validate the app and DMG, and run Gatekeeper checks
  before publishing. README screenshots and behavior documentation reflect 1.1.2.

## [1.1.1] - 2026-07-18

### Added

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

### Changed

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

## [1.1.0] - 2026-07-18

### Added

- **Live preview refresh**: opening the switcher still shows cached snapshots
  instantly, but each tile now crossfades to a fresh capture the moment it
  lands — no more stale previews for the whole session. Late captures for
  closed windows are discarded (new tested PreviewLedger), and regression
  tests pin previews to their window id so a snapshot can never appear on
  another window's card.
- **Update notice in Settings**: the Updates pane now shows "WindowHop X.Y.Z
  is available" with an Install Update button when the scheduled Sparkle check
  finds a newer version (the standard Sparkle prompt still handles install /
  remind-later / skip).

### Changed

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
- **Polished DMG installer**: background artwork with drag-to-Applications
  guidance, fixed icon layout, a volume icon, and a matching file icon —
  generated headlessly (appdmg), so CI produces the full layout too.

## [1.0.5] - 2026-07-08

### Changed

- Window titles now wrap to **two lines** before truncating — no more premature
  "…" on titles that would fit. The title zone has a fixed two-line height, so
  tiles never resize between short and long titles and the tab-count line stays
  aligned across every tile.
- The native-switcher visual pass is fully unified across both appearances
  (App Icons and Window Previews share the same panel material, selection ramp,
  vertical rhythm, and badge controls), verified in Light and Dark Mode.
- Snapshot corners rounded slightly more (10 pt) to sit naturally inside the
  larger selection radius.

## [1.0.4] - 2026-07-08

Visual pass to match the native macOS switcher, reviewed primarily in Dark Mode:

### Changed

- The panel now uses the stable dark-glass HUD material — bright desktops can no
  longer wash it out (the popover material was too transparent).
- Selection is the native idiom: a rounded rectangle *lighter* than the panel in
  Dark Mode (white ~16%), darker in Light Mode — no more near-black selection.
- Close and Settings controls use the Apple badge style: white glyph on a filled
  gray circle (like notification and Safari-tab close buttons) — high contrast on
  any snapshot.
- Density matched to the native switcher: tighter tiles (124×158 icons, 204×170
  previews), larger panel corner radius, quieter placeholder fill.

## [1.0.3] - 2026-07-07

### Added

- **Standard keyboard shortcuts everywhere**: WindowHop now has a proper main
  menu, so ⌘W closes the Settings window, ⌘Q quits, ⌘, opens Settings, and text
  editing shortcuts work.

### Changed

- **Native-switcher colors**: selection and placeholder surfaces now use the
  system semantic fills (secondary/quaternary system fill) and the panel uses
  the standard popover material — the same palette family as Apple's switcher.
- Close and Settings overlay controls redesigned to the Apple badge idiom:
  hierarchical SF Symbols anchored to the content corner (Mission Control
  style), on one shared inset grid.
- The DMG is now built with sindresorhus/create-dmg (pinned): the familiar
  polished drag-to-Applications layout, reproducible on CI.
- Releases now ship exactly two assets: the DMG (for people) and the ZIP
  (for Sparkle updates).

### Fixed

- **Permission loop, part 2**: the welcome window now detects macOS App
  Translocation (running from a quarantined temporary path — a grant can never
  stick there) and offers a one-click "Reset Stuck Permission…" that clears a
  stale Accessibility entry via Apple's tccutil so the next grant binds cleanly.
- **No more preview flash**: windows without a snapshot show a quiet rounded
  placeholder card with the app icon, and the first capture fades in over it
  (Reduce Motion disables the fade). Geometry never jumps.
- The Appearance pane keeps a fixed height — switching App Icons/Window
  Previews no longer resizes the Settings window mid-animation.

## [1.0.2] - 2026-07-06

### Added

- The WindowHop Settings window now shows its own preview in Window Previews mode.

### Changed

- **Native update dialog**: checking for updates now shows the plain macOS alert —
  no embedded web view. Full release notes stay on GitHub.
- Previews follow the AltTab model strictly: what the switcher opens with is what
  you see (snapshots are never swapped mid-session); captures only refresh the
  in-memory cache for the next open, and tiles that had no snapshot fill in.
- Bigger app-icon badge on previews (40 pt), close/Settings controls aligned on
  one 8 pt inset grid, and all UI dimensions moved into a single design-tokens
  file (`UI/DesignTokens.swift`).
- "Quit WindowHop…" in Settings is visibly destructive (red), with confirmation.

### Fixed

- **Fixed the endless Accessibility permission loop after updates**: releases are
  now signed with a stable certificate, so macOS keeps the grant across updates.
  One last re-grant is needed when installing this version (remove WindowHop from
  the Accessibility list with −, add it again with +); after that, updates keep
  working without asking again.
- Multi-row layouts center every row (no more left-ragged last row).

## [1.0.1] - 2026-07-06

### Added

- **Instant previews**: window snapshots are cached in memory (AltTab-style) so
  the switcher opens instantly with the last known preview, while fresh captures
  load in parallel and crossfade in when the content changed. Nothing is captured
  while the switcher is closed; snapshots stay in memory only and are evicted
  with their window.
- Added a confirmed "Quit WindowHop…" button in Settings → General.

### Changed

- **Grid instead of horizontal scrolling**: many windows now wrap into multiple
  rows (arrow keys navigate the grid spatially); icons never shrink.
- Bigger window titles (13 pt), slightly smaller preview tiles, and much more
  visible close and Settings controls.
- New tagline everywhere: "Switch between windows, not just apps."

### Fixed

- **Every window gets its own preview**: snapshot-to-window matching is now a
  unique assignment — two windows of the same app can no longer show the same
  preview; an uncertain match falls back to the app icon instead of guessing.
- Fixed duplicate entries after a missed window-close notification (the
  "WhatsApp appeared twice" bug): stale Accessibility elements are now detected
  and pruned on Space changes and when the switcher opens.
- Fixed the WindowHop Settings window sometimes not coming to the front when
  activated from the switcher.

## [1.0.0] - 2026-07-03

First release.

Known limitations: releases are not notarized (no paid Developer ID yet); windows
on unvisited Spaces appear after that Space is visited once; tab counts only for
apps exposing native tab groups; English-only interface.

### Added

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

[Unreleased]: https://github.com/martonpaulo/windowhop/compare/v2.1.0...HEAD
[2.1.0]: https://github.com/martonpaulo/windowhop/releases/tag/v2.1.0
[2.0.0]: https://github.com/martonpaulo/windowhop/releases/tag/v2.0.0
[1.6.2]: https://github.com/martonpaulo/windowhop/releases/tag/v1.6.2
[1.6.1]: https://github.com/martonpaulo/windowhop/releases/tag/v1.6.1
[1.6.0]: https://github.com/martonpaulo/windowhop/releases/tag/v1.6.0
[1.5.0]: https://github.com/martonpaulo/windowhop/releases/tag/v1.5.0
[1.4.0]: https://github.com/martonpaulo/windowhop/releases/tag/v1.4.0
[1.3.1]: https://github.com/martonpaulo/windowhop/releases/tag/v1.3.1
[1.2.0]: https://github.com/martonpaulo/windowhop/releases/tag/v1.2.0
[1.1.2]: https://github.com/martonpaulo/windowhop/releases/tag/v1.1.2
[1.1.1]: https://github.com/martonpaulo/windowhop/releases/tag/v1.1.1
[1.1.0]: https://github.com/martonpaulo/windowhop/releases/tag/v1.1.0
[1.0.5]: https://github.com/martonpaulo/windowhop/releases/tag/v1.0.5
[1.0.4]: https://github.com/martonpaulo/windowhop/releases/tag/v1.0.4
[1.0.3]: https://github.com/martonpaulo/windowhop/releases/tag/v1.0.3
[1.0.2]: https://github.com/martonpaulo/windowhop/releases/tag/v1.0.2
[1.0.1]: https://github.com/martonpaulo/windowhop/releases/tag/v1.0.1
[1.0.0]: https://github.com/martonpaulo/windowhop/releases/tag/v1.0.0
