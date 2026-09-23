# User-facing defaults and configurability

`Preferences.Defaults` is the only runtime source of persisted defaults. Every typed
user-facing key participates in `Preferences.configurableKeys`, except one that mirrors a
system registration (launch at login), and a regression test fails when a new
configurable key is omitted from Restore Defaults without that explicit exception.

## Key names

Every `Preferences.Key` that WindowHop owns is stored under a constant, versioned name,
`<name>.v1` (for example `showTabCounts.v1`). A later change to the shape of a stored value
takes the next version (`<name>.v2`) with its own tested migration, and never reinterprets
data stored under the old name. `PreferencesKeyMigration` moved the unversioned names once,
from `Preferences.init(defaults:)` before the first read, guarded by the integer
`preferences.schema` in the same domain: it copies each stored value that is valid for the
key's current type, drops an invalid one (the key then takes its default), and removes the
old name. Two names keep their spelling: `SUEnableAutomaticChecks`, which Sparkle owns and
reads under that name, and `navigationPreviewDelay`, which exists only as the 1.1.2 name the
expanded-preview migration reads. Window-state entries that are not `Preferences.Key`
values (the Settings frame autosave and the selected pane) are outside this rule. An older
WindowHop started after the migration no longer finds the old names and shows its
defaults. Decided on #111.

## Bundle identifier move

`UserDefaults` is keyed to the bundle identifier, so the release that moved it to
`com.martonpaulo.windowhop` starts from an empty domain. `LegacyDomainMigration` copies the
previous identifier's domain once, from the app delegate before `Preferences` is created:
every `Preferences.Key` name, the unversioned name each key had before #111, the
`preferences.schema` marker, and the Settings window frame and selected pane. A name the new
domain already stores keeps its value, and anything else (Sparkle's own state, other
apps' window frames) is left behind. `PreferencesKeyMigration` then runs on the copied
names as usual. `preferences.legacyDomainMigrated` records that the copy ran; it is not a
setting, so Restore Defaults leaves it alone. The old domain is only read, so an older
build still finds its settings. The bare `swift build` binary never copies. It is not
configurable: keeping the person's settings is the only valid outcome. Decided on #43.

## WindowHop 1.3.1 decisions

| Feature | Default | Configurable | Settings / persistence / migration / Restore Defaults |
|---|---|---|---|
| Switcher shortcut | ⌘Tab | Yes | Shortcuts; typed `UserDefaults`; existing stored values win; resets to ⌘Tab. |
| Open WindowHop shortcut | ⌥Tab | Yes | Shortcuts; typed `UserDefaults`; an existing custom or explicitly cleared value wins; a stored or default chord that conflicts with the loaded switcher shortcut loads as unassigned and is stored as cleared; resets to ⌥Tab. |
| Show tab counts | Off | Yes | Appearance; typed `UserDefaults`; existing stored values win; resets to Off. |
| Context-sensitive Settings button | Enabled | No | One intended presentation behavior: hidden in cycling until panel hover, always visible in persistent mode. No persistence or reset entry. |
| Complete shortcut interception | Enabled | No | Correctness fix: an owned shortcut must not leak into the native app switcher. No persistence or reset entry. |
| Native title and metadata typography | Enabled | No | Shared required presentation and accessibility behavior. No arbitrary font preference, persistence, migration, or reset entry. |
| Preview skeletons | Enabled | No | Standard loading/fallback presentation. Loading animation follows the mandatory Reduce Motion system setting. No persistence or reset entry. |
| About attribution and website | Shown | No | Application metadata, centralized in `ProjectLinks`; no persistence or reset entry. Settings › About is the one About surface: the app menu's About WindowHop opens that pane instead of AppKit's standard About panel, and its copyright footer is the bundle's `NSHumanReadableCopyright` read through `WindowHopKit/AppVersion` (omitted in unbundled development builds). "Report an Issue…" (About and Help) opens the public bug-report form prefilled through `ProjectLinks.issueReport` with the version, build, ISO release date when present and macOS version only; the person reviews and submits it. |
| Restore Defaults | Available | No | Confirmed action rather than a preference. Resets every key in `Preferences.configurableKeys` and never changes permissions, identity, version, or first-run state. |

Existing preferences are never overwritten during an upgrade. Missing keys receive the
centralized default through the registration domain; migrations are explicit and tested.

## WindowHop 1.4.0 decisions

| Feature | Default | Configurable | Settings / persistence / migration / Restore Defaults |
|---|---|---|---|
| Uniform Settings pane size | Enabled | No | One intended presentation behavior: every pane shares `DesignTokens.settingsPaneWidth`/`settingsPaneHeight`, so selecting a pane never resizes the window. No persistence or reset entry. |
| Selected Settings pane | General | No | Window-state restoration, not a preference: the pane identifier is stored in `UserDefaults` and ignored when unknown. Not part of `configurableKeys`; Restore Defaults leaves it untouched. |
| Unambiguous preview matching | Enabled | No | Correctness fix: a preview is shown only for the window it belongs to, otherwise the tile keeps its placeholder. No persistence or reset entry. |

## WindowHop 1.5.0 decisions

| Feature | Default | Configurable | Settings / persistence / migration / Restore Defaults |
|---|---|---|---|
| Windows appearing mid-session | Shown | No | Correctness fix: a window the user cannot see is a window they cannot reach, and the existing inclusion policy already decides what qualifies. The stability concern that motivated the frozen list is met by appending instead of reordering (see `SessionListReconciler`), so no legitimate "hide new windows" state remains. No persistence or reset entry. |

## WindowHop 1.6.0 decisions

| Feature | Default | Configurable | Settings / persistence / migration / Restore Defaults |
|---|---|---|---|
| Switcher placement across displays | All displays | Yes | Windows pane; typed `UserDefaults` (`switcherDisplayPlacement`); no migration — an installation with no stored value takes the new default and every other stored choice is untouched; resets to All displays. Placement is display *behavior*, so it lives beside the inclusion filters rather than under Appearance. |
| Chosen display for "a specific display" | None | Yes | Windows pane; typed `UserDefaults` (`switcherDisplayID`), a display UUID from `CGDisplayCreateUUIDFromDisplayID` so it survives reconnect and reboot. A disconnected choice is kept verbatim, shown in the picker as disconnected, and falls back to the pointer display until it returns; resets to none. |
| Pointer display rather than keyboard focus | Pointer | No | One valid outcome: `NSScreen.main` is documented to misreport the active screen (fullscreen app, or `screensHaveSeparateSpaces` off), and the pointer is what tracks where the user is looking. No persistence or reset entry. See `UPSTREAM.md`. |
| Identical grid on mirrored panels | Enabled | No | Correctness constraint: `SwitcherState` holds one column count for arrow navigation, so per-display grids would make the arrow keys ambiguous. The shared grid comes from the most constrained target display. No persistence or reset entry. |

## Unreleased decisions

| Feature | Default | Configurable | Settings / persistence / migration / Restore Defaults |
|---|---|---|---|
| Switcher reveal delay | 100 ms | Yes | Windows pane; typed `UserDefaults` (`switcherRevealDelay`), presets Off, 100, 200, 300, 500 ms; no migration — an installation with no stored value takes the default, an invalid value falls back to it; resets to 100 ms. Applies only to held sessions: a quick press switches without drawing the panel, while Open WindowHop always shows immediately. Both states are legitimate preferences, so it is a setting. |
| Launch at login | Off for new installs | Yes | General; typed `UserDefaults` (`launchAtLogin`). Migration: an installation that completed first launch without storing a value keeps On, the default it received. Every stored choice is kept. Restore Defaults leaves it and the login item alone, because it mirrors a system registration. The stored value is the person's intent; the toggle shows the real login-item status (next row). |
| Launch at login status | Reflects `SMAppService` | No | One valid outcome, a truthful status, so no setting. `WindowHopKit/LoginItemStatus` maps `SMAppService.Status` to enabled, disabled, requires approval (toggle on, explanation, Open Login Items Settings…) and unavailable (a bare executable; toggle dimmed). A bundled app that reads `notFound` shows Off and stays enableable, because a never-registered bundle reads `notFound` on macOS 26. Read when General appears and when WindowHop becomes active, never polled; reading never registers or writes `launchAtLogin`. Only a successful toggle click writes the intent. Nothing persisted, so no migration or Restore Defaults entry. |
| Settings window position | Restored (first use centered) | No | Restoration behavior with one valid outcome. AppKit frame autosave (`NSWindow Frame WindowHopSettings`), OS/UI restoration state rather than a `Preferences.Key`: not in `configurableKeys`, and Restore Defaults leaves it untouched, like the selected pane. Only the origin is restored; the size stays the pane canvas. A frame whose title bar is on no connected display is recentered on the main display (`WindowHopKit/WindowFrameRecovery.swift`). |
| Menu bar item state | Derived | No | Presentation only, derived from `switcherEnabled` and the Accessibility grant through `WindowHopKit/StatusItemState.swift`: a distinct symbol shape and accessibility label for active, paused, and Accessibility access needed, plus a status row (and Open Accessibility Setup…) in the menu. One valid outcome, so no setting; nothing is persisted, so no migration or Restore Defaults entry. Whether the item is shown stays the separate `showMenuBarItem` preference (off). |
| Parent folder for same-app title collisions | Enabled | No | One valid outcome: identical tiles for different windows only hide which one is which. When same-app entries share a displayed title, each whose `AXDocument` folder tells the group apart gets " — <folder>" (`WindowHopKit/CollisionLabel`); nothing is invented when no document separates them. Presentation only — the raw title still drives preview matching and AX association — and it needs no Screen Recording and keeps card geometry. No persistence or reset entry. |
| Layout-aware shortcut labels | Enabled | No | One valid outcome: a label must name the key the user presses. The stored and matched binding stays the physical key code, so a layout change never rewrites a shortcut; only printable keys are relabelled from the current keyboard layout (`ShortcutFormatter.keyLabels`), with the US ANSI names as fallback. No persistence, migration or reset entry. |
| Shortcut conflict validation | Enabled | No | Correctness guard at capture time only (`WindowHopKit/ShortcutConflicts.swift`): chords macOS reserves and the standard app commands (matched by the layout's character) are rejected with a named reason; an enabled macOS keyboard shortcut (read-only `CopySymbolicHotKeys`) needs a per-capture confirmation whose default is Cancel. Re-recording the stored chord is always accepted, and the load path keeps using `validate(against:)` only, so an existing stored chord is never rejected or rewritten. No persistence, migration or reset entry. |
| Switching guide in General | Shown | No | Explanatory copy derived from the current switcher shortcut, Open WindowHop shortcut and Enable state through `SwitchingGuide` and `ShortcutFormatter`, with no state of its own; the Shortcuts footer is built from the same guide. No persistence, migration or reset entry, and it never touches first-launch state or visibility choices. |
| Window shown at launch and reopen | Derived | No | Owner decision on #80: Settings at a normal launch only on first run or with both icons hidden, nothing at a login launch, onboarding on any launch while Accessibility is missing (`WindowHopKit/LaunchPresentation`, table in [architecture.md](architecture.md) "Launch and reopen"). Not a setting, because the menu bar item and Dock icon toggles already decide it. Reads the existing internal `firstLaunchCompleted`; no new key, migration or Restore Defaults entry. |
| Release date in About | Shown when packaged | No | Application metadata with one valid outcome. `scripts/package-app.sh` stamps the packaged commit's committer date into the bundle's `Info.plist` as `AppReleaseDate` (`YYYY-MM-DD`) through `scripts/stamp-app-metadata.sh`; `WindowHopKit/AppVersion` is the one reader of version, build and date for About, Updates and support reports, and formats the date in UTC with the current locale. A development build shows "Development build" and no date; never an install, modification or launch date. No persistence, migration or reset entry. |
| Transient preview failure retry | One retry per window per session | No | Internal error recovery with one valid outcome (#91): a tile whose capture failed for a reason that can pass on its own is captured once more after 500 ms in the same session, through the shared capture budget (`WindowHopKit/TileCaptureFlow.swift`, allowance in `PreviewLedger.claimRetry`). Stable failures never retry. No persistence, migration or reset entry. |
