# Upstream: AltTab

WindowHop is derived from **AltTab** — <https://github.com/lwouis/alt-tab-macos> —
by Louis Pontoise (lwouis) and contributors, licensed GPL-3.0.

## Base revision

- Tag: `v10.12.0`
- Commit: `317a485bcb090bf2b29e3f78872218f0099e1d62`
- Why this one: it is the last stable tag before the Pro/licensing/trial code introduced
  in `v11.0.0` (`9147a4a8`, "feat: introducing alt-tab pro!"), and the last release whose
  engine is Accessibility-based. v11.x reworked window tracking onto private SkyLight/CGS
  WindowServer APIs (`SLSRegisterNotifyProc` etc.), which WindowHop's public-API-only rule
  excludes.

The full upstream history up to that commit is preserved in this repository
(`git log 317a485b` and earlier), so reading the base revision needs no remote. A checkout
has only `origin` by default; the `upstream` remote is optional and only needed to review
later AltTab history (see "Evaluating upstream fixes later"):

```sh
git remote add upstream https://github.com/lwouis/alt-tab-macos
```

## Retained (ported into new sources, same GPL license)

| Upstream (v10.12.0) | WindowHop | What was kept |
|---|---|---|
| `src/logic/WindowDiscriminator.swift` | `WindowHopKit/WindowEligibility.swift` | window vs non-window rules incl. app-specific quirks |
| `src/logic/Window.swift` (`bestEffortTitle`) | `WindowHopKit/TitleResolver.swift` | title fallback order |
| `src/logic/Windows.swift` (`updateLastFocusOrder`) | `WindowHopKit/MRUOrder.swift` | window-level MRU semantics |
| `src/logic/Application.swift` | `Engine/TrackedApp.swift` | per-app AXObserver, launch-readiness retry pattern |
| `src/logic/events/AccessibilityEvents.swift` | `Engine/AXNotificationRouter.swift` | notification routing, batched attribute reads |
| `src/api-wrappers/AXUIElement.swift` | `Engine/AXHelpers.swift` | batched attributes, safe casting, subscription semantics, tab-group counting |
| `src/logic/TabGroup.swift` | `WindowHopKit/TabGroupResolver.swift` + `WindowHopKit/TabObservation.swift` + `Engine/AXHelpers.swift` (`tabObservation`) | AXTabGroup/AXTabButton detection; tab-sibling resolution so tabs never become entries; an incomplete tab-bar read is unknown, not standalone (upstream `8c8d2836`, ported without its private window scanner; WindowHop issue #46); a detached tab leaves its group on public facts — the active tab's standalone read, or focus plus a different frame — where upstream `0af8eb3d` confirms detachment with private `CGSCopySpaces*` Space facts, evaluated and not ported (WindowHop issue #82) |
| `src/logic/events/KeyboardEvents.swift` | `Input/EventTap.swift` | tap re-enable on `tapDisabledBy*`, dedicated input thread |
| `src/logic/BackgroundWork.swift` | `Engine/BackgroundWork.swift` | dedicated run-loop threads, AX off the main thread |
| `src/logic/events/RunningApplicationsEvents.swift` | `Engine/WindowStore.swift` | KVO on `NSWorkspace.runningApplications` |
| `src/logic/SystemPermissions.swift` | `Engine/AccessibilityPermission.swift` | permission gating; polling reduced to onboarding-window-only |
| Window/screen coordinate conversion (`Window.isOnScreen`) | `Engine/TrackedWindow.swift` | Quartz↔Cocoa frame conversion |
| `src/ui/App.swift` (`showUiOrCycleSelection`), `src/logic/Preferences.swift` (`windowDisplayDelay`) | `WindowHopKit/Preferences.swift` (`SwitcherRevealDelay`) + `Input/SwitcherController.swift` (`scheduleReveal`) | reveal delay before drawing the switcher (upstream default 100 ms), with a quick release ending the session before anything is shown; exposed as presets and applied to held sessions only (WindowHop issue #32) |
| `src/ui/MainMenu.swift` (`appMenuItem`, `helpMenuItem`) | `UI/MainMenuBuilder.swift` | Services submenu registered through `NSApp.servicesMenu`, Show All in the app menu, a Help menu registered through `NSApp.helpMenu`; installed only while the Dock icon setting makes the app regular, and Help holds Report an Issue… instead of a help book WindowHop does not ship (WindowHop issue #64) |
| `src/logic/Screens.swift` (`withMouse()`, `uuid()`) | `Engine/DisplayRegistry.swift` | pointer-display detection via `NSMouseInRect`; stable display identity via `CGDisplayCreateUUIDFromDisplayID` with the nil checks those implicitly-unwrapped APIs actually need; the documented unreliability of `NSScreen.main` |
| `Pods/ShortcutRecorder/Library/SRRecorderControl.m` (`viewWillMoveToWindow:`) | `UI/ShortcutRecorderControl.swift` | recording ends when the recorder's window resigns key, with the observer scoped to the current window; WindowHop also ends it on window close (WindowHop issue #50) |
| `src/logic/events/InputSourceEvents.swift` (`kTISNotifySelectedKeyboardInputSourceChanged`, `317a485b`) | `Engine/KeyboardLayout.swift` + `UI/ShortcutRecorderControl.swift` | the distributed input-source-change notification as the trigger to relabel shortcuts; WindowHop observes it only while the recorder is in a window and translates with `kUCKeyTranslateNoDeadKeysMask`, where upstream's recorder passes the bit index (WindowHop issue #79) |
| `src/ui/generic-components/CustomRecorderControlTestable.swift` (`MacOsShortcuts`, `ReservedMacosShortcut`, `isShortcutAcceptable`, `317a485b`) | `WindowHopKit/ShortcutConflicts.swift` | the hard-set Escape chords (⌥⌘⎋, ⌥⇧⌘⎋, ⌃⌥⇧⌘⎋) are rejected, and re-recording the current chord is accepted first; WindowHop reads the Game Overlay ⌘⎋ and other enabled system shortcuts from `CopySymbolicHotKeys` instead of a fixed table, and adds the standard app commands (WindowHop issue #56) |
| `Pods/ShortcutRecorder/Library/SRRecorderControl.m` (`accessibilityValue`, `setObjectValue:`, `beginRecording`) | `UI/ShortcutRecorderControl.swift` (`refreshTitle`) | the accessibility value names the chord in words (a word for no chord) and title/value changes are posted when the chord or recording state changes; WindowHop says "Recording" while recording and exposes the validation message as help (WindowHop issue #78) |
| `src/events/ScreenLockEvents.swift`, `src/events/SleepWakeEvents.swift`, `src/switcher/state/Applications.swift` (`confirmAbsentFromApp`), after the base (`97ec5cb1`, `e32b48e1`) | `WindowHopKit/SessionAvailability.swift` + `WindowHopKit/SpaceMembership.swift` + `Engine/SessionMonitor.swift` + `Engine/WindowStore.swift` (`refreshInventory`) | a locked screen makes every app publish zero windows, so nothing is concluded from AX while locked and one re-enumeration runs on unlock and on wake; observed through the same `com.apple.screenIsLocked` / `screenIsUnlocked` distributed notifications. WindowHop also covers fast user switching and system sleep, voids reads that span a dark period, and does not seed the lock state from `CGSessionCopyCurrentDictionary`'s undocumented `CGSSessionScreenIsLocked` key (WindowHop issue #38) |

## Corrected (ported rule intentionally diverges from upstream)

- Window focus. Before `3f5ea251` (2019-12-27) AltTab fronted a window with
  `app.activate(options: [.activateIgnoringOtherApps])` plus `kAXRaiseAction`; that commit
  moved to the private `_SLPSSetFrontProcessWithOptions`, which fronts a process *for one
  window*. WindowHop's public substitute used the settable `kAXFrontmostAttribute` on the
  application, which a two-display probe (WindowHop issue #41, 2026-09-23, macOS 26) showed
  fronts every window of the app on every display. `WindowActions.activate` now makes the
  window main, raises it and calls `NSRunningApplication.activate()`, which fronts only the
  main and key windows; the AX attribute remains a fall-back, used only when the app is
  still not focused 150 ms later (`WindowHopKit/ActivationFallback`).

- `src/logic/TabGroup.swift` (`updateState`) clears the group membership of *every*
  same-app window that is not in the refreshed group. When one app owns two native tab
  groups, refreshing either one dissolves the other and its inactive tabs reappear as
  separate entries. `WindowHopKit/TabGroupResolver.resolve` narrows that cleanup to windows whose
  recorded membership actually contains the refreshing window (WindowHop issue #18).
- `src/logic/TabGroup.swift` (`updateState`) takes the first same-app window whose title
  matches a tab title, so an independent window sharing an inactive tab's title can be
  hidden while the real tab stays visible. `WindowHopKit/TabGroupResolver.resolve` ranks
  candidates by AX frame (the geometry rule upstream relies on in `ae89aefa`, relaxed to
  a ranking because merged tabs report stale pre-merge frames) and by recorded
  membership, and leaves tied candidates visible (WindowHop issue #45).

## Removed

- Pro/licensing/trial/upgrade code (never present in v10.12.0; the base was chosen for that).
- Upstream's thumbnail engine, including its private `CGSHWCaptureWindowList` capture path.
  Window previews were removed with it, then reintroduced as WindowHop's own opt-in Window
  Previews mode: public ScreenCaptureKit only, confined to `Engine/PreviewProvider.swift`,
  capturing only during an open session and gated on the Screen Recording permission. No
  upstream capture code was ported; upstream's public `SCScreenshotManager` path
  (`src/logic/events/WindowCaptureEvents.swift`) is a legitimate reference for preview fixes.
- Search/typing filter, trackpad/scrollwheel gestures, drag-and-drop onto tiles,
  window tiling hooks, app launching, Dock/context-menu integrations.
- AppCenter (crash telemetry), SwiftyBeaver (logging), LetsMove, ShortcutRecorder —
  third-party dependencies. Sparkle was initially removed too, then reintroduced
  cleanly via Swift Package Manager as WindowHop's only dependency (updates only;
  WindowHop's shortcut recorder is its own small AppKit control).
- All private API usage:
  - `CGSSetSymbolicHotKeyEnabled` (disabling native Cmd-Tab) → replaced by a consuming
    CGEvent tap, which is fail-safe by construction.
  - `_SLPSSetFrontProcessWithOptions` / `SLPSPostEventRecordTo` (focus) → replaced by
    AX raise + settable `kAXFrontmostAttribute` + `NSRunningApplication.activate()`.
  - `_AXUIElementGetWindow`, `_AXUIElementCreateWithRemoteToken` (window ids, brute-force
    discovery) → replaced by AXUIElement identity plus re-enumeration on Space changes.
  - `CGSCopySpaces*` and Spaces bookkeeping → replaced by a per-window current-Space flag
    maintained from public enumeration.
- Localization files (first release is English), preferences UI framework (~40 settings
  reduced to 8), update/feedback/crash windows, CI/release tooling, CocoaPods.

## Consulting the upstream when planning

Check AltTab **before planning any issue that touches window discovery, screens, input,
focus, permissions, or AX behavior**. It shipped these problems years ago and its source
records macOS quirks that Apple's documentation does not.

The base revision's full tree is in this repository, so no network or checkout is needed:

```sh
git show 317a485b:src/logic/Screens.swift        # read one upstream file
git grep -l -i "<term>" 317a485b -- src          # find where upstream handles something
```

What to do with what you find:

- **A quirk or workaround** — port the *rule* into the matching WindowHop file with a comment
  naming the constraint, and add a row to the Retained table below.
- **A feature WindowHop removed on purpose** — leave it removed. The Removed list is a set of
  decisions, not a backlog.
- **A different default** — note it in the issue and let the owner decide. AltTab's default is
  evidence, not authority.

Record ported rules in the Retained table and cite the upstream commit hash in the commit
message. Never copy code verbatim without checking it still applies to a public-API-only,
AX-based engine.

## Evaluating upstream fixes later

1. Add the optional `upstream` remote if the checkout lacks it (command above),
   `git fetch upstream`, and review `git log upstream/master -- src/` since `v10.12.0`.
2. Only consider areas WindowHop kept: eligibility quirks (`WindowDiscriminator`/
   `WindowFilterResolver`), title/tab detection, AX subscription robustness, permission
   handling, and previews when the fix uses public ScreenCaptureKit. Ignore fixes for
   search, gestures, Pro, updates, and the v11 WindowServer engine or any other private
   API (including `CGSHWCaptureWindowList` capture).
3. Port the *rule*, not the code: add it to the matching WindowHop file with a test where
   feasible, and note the upstream commit hash in the commit message.

## Other sources

AltTab is the only project WindowHop is derived from. The sources below are consulted next
to it; none is a dependency, and none is attributed as an ancestor. Surveyed for
[#36](https://github.com/martonpaulo/windowhop/issues/36) between 2026-09-22 and
2026-09-23: licenses were read from each repository's license file, private-API use from a
`git grep` for `CGS`/`SLS`/`SLPS`/`SkyLight`/`_AXUIElement`/`@_silgen_name` at the pinned
revision. No fetched code was built or executed.

**Verdicts.** *Port rule*: re-implement a behavior rule, with provenance. *Reuse code*:
code may be incorporated with its notices (requires a GPL-3.0-compatible license and no
private API). *Reference only*: read for evidence and counterexamples; copy nothing.
*Excluded*: private-API or SIP-dependent engine, or a product non-goal; not consulted for
planning.

### AltTab forks

Selection: of AltTab's ~875 forks (upstream `v11.7.1`, `56891e08`, on 2026-09-22), the 100
most-starred and 35 most recently pushed were listed, and 13 default branches (plus one
feature branch) were compared with upstream by commits ahead/behind. Recent activity with
commits ahead found the only useful leads; the most-starred forks were mostly build, Pro, or
distribution changes. Every fork carries AltTab's GPL-3.0 `LICENCE.md` and v11's private
WindowServer engine, so none qualifies for *reuse code*.

| Fork | Revision, reviewed on | Unique contribution | Areas | Verdict | Issues |
| --- | --- | --- | --- | --- | --- |
| [gnufied/alt-tab-macos](https://github.com/gnufied/alt-tab-macos) | [`2f707f76`](https://github.com/gnufied/alt-tab-macos/commit/2f707f76cee4165d71560acbabf45fcbe8e3d26a), 2026-09-22 | Recorder-aware shortcut matching; key-up cleanup after an interrupted tap | `Input/`, `UI/` | Port rule | [#83](https://github.com/martonpaulo/windowhop/issues/83), [#84](https://github.com/martonpaulo/windowhop/issues/84) |
| [Qiushi0919/alt-tab-macos](https://github.com/Qiushi0919/alt-tab-macos) (`feature/multi-display-switcher`) | [`bb59dea1`](https://github.com/Qiushi0919/alt-tab-macos/commit/bb59dea18f676cefc4f7783bfdad5557e426fa25), 2026-09-22 | Mixed-scale multi-display capture scenario; its panel mirroring is private and non-interactive | `Engine/`, `UI/` | Reference only | [#33](https://github.com/martonpaulo/windowhop/issues/33) |
| [TroopJostle/alt-tab-community](https://github.com/TroopJostle/alt-tab-community) | `eb8524ed`, 2026-09-22 | Display UUID fallback (already ported); [focus patch](https://github.com/TroopJostle/alt-tab-community/commit/3e638464a02fe033cab8d39d0043de5a1266a920) uses private `SLPSPostEventRecordTo` | `Engine/` | Reference only | none |
| [XOR-op/alt-tab-macos](https://github.com/XOR-op/alt-tab-macos) | `d2316aa4`, 2026-09-22 | Keeps a good thumbnail over a degenerate capture; AeroSpace workspace integration (out of scope) | `Engine/` | Reference only | [#89](https://github.com/martonpaulo/windowhop/issues/89) |
| [InSasquatchCountry/alt-tab-macos](https://github.com/InSasquatchCountry/alt-tab-macos) | `14acc0ce`, 2026-09-22 | 0 commits ahead; nothing to port | none | Reference only | none |
| [filipef101/alt-tab-macos-free](https://github.com/filipef101/alt-tab-macos-free), [Korel/alt-tab-macos](https://github.com/Korel/alt-tab-macos), [vemonet/alt-tab-macos-free](https://github.com/vemonet/alt-tab-macos-free) | `1287294d`, `32c522d1`, `48ad1ee8`; 2026-09-22 | Pro removal, build and distribution changes; no engine fix | none | Excluded (Pro/distribution only) | none |

Upstream commits after the base revision that the same pass mapped to WindowHop issues:
`8c8d2836` ([#46](https://github.com/martonpaulo/windowhop/issues/46)), `ae89aefa`
([#45](https://github.com/martonpaulo/windowhop/issues/45),
[#47](https://github.com/martonpaulo/windowhop/issues/47)), `4c49801f`
([#81](https://github.com/martonpaulo/windowhop/issues/81)), `0af8eb3d`
([#82](https://github.com/martonpaulo/windowhop/issues/82)), `97ec5cb1` and `e32b48e1`
([#38](https://github.com/martonpaulo/windowhop/issues/38),
[#49](https://github.com/martonpaulo/windowhop/issues/49)), `70fa760c`
([#85](https://github.com/martonpaulo/windowhop/issues/85),
[#86](https://github.com/martonpaulo/windowhop/issues/86)).

### Similar switchers and preview tools

| Repository | License (from file) | Reviewed revision | Private API | Areas | Verdict | Issues |
| --- | --- | --- | --- | --- | --- | --- |
| [rokartur/BetterCmdTab](https://github.com/rokartur/BetterCmdTab) | GPL-3.0 | `145da642`, 2026-08-28 | Partial (focus, Spaces, symbolic-hotkey disable) | `WindowHopKit`, `Engine/`, `Input/`, `UI/` | Reference only (private API; pure-rule tests are license-compatible counterexamples) | [#45](https://github.com/martonpaulo/windowhop/issues/45), [#79](https://github.com/martonpaulo/windowhop/issues/79), [#84](https://github.com/martonpaulo/windowhop/issues/84), [#85](https://github.com/martonpaulo/windowhop/issues/85), [#86](https://github.com/martonpaulo/windowhop/issues/86), [#87](https://github.com/martonpaulo/windowhop/issues/87), [#90](https://github.com/martonpaulo/windowhop/issues/90) |
| [ejbills/DockDoor](https://github.com/ejbills/DockDoor) | GPL-3.0-or-later (GitHub reports NOASSERTION) | `48483a77`, 2026-09-18 | Partial (window identity, capture, focus) | `WindowHopKit`, `Engine/`, `UI/` | Reference only | [#45](https://github.com/martonpaulo/windowhop/issues/45), [#79](https://github.com/martonpaulo/windowhop/issues/79), [#85](https://github.com/martonpaulo/windowhop/issues/85), [#86](https://github.com/martonpaulo/windowhop/issues/86), [#89](https://github.com/martonpaulo/windowhop/issues/89) |
| [MystikoLab/sxitch](https://github.com/MystikoLab/sxitch) | Apache-2.0 | `800929f0`, 2026-09-19 | No | `Input/`, `UI/` | Port rule | [#56](https://github.com/martonpaulo/windowhop/issues/56), [#72](https://github.com/martonpaulo/windowhop/issues/72), [#74](https://github.com/martonpaulo/windowhop/issues/74), [#92](https://github.com/martonpaulo/windowhop/issues/92) |
| [Sanyam-G/switch](https://github.com/Sanyam-G/switch) | FSL-1.1-MIT (not GPL-compatible until each version converts) | `4cffdf72`, 2026-09-22 | Partial (Spaces, focus) | `Engine/` | Reference only (license) | [#41](https://github.com/martonpaulo/windowhop/issues/41), [#91](https://github.com/martonpaulo/windowhop/issues/91) |
| [FuzzyIdeas/lowtechguys](https://github.com/FuzzyIdeas/lowtechguys) | None found (website source, not rcmd's engine) | `a395fd54`, 2026-08-19 | n/a | docs, site | Reference only (no license) | [#34](https://github.com/martonpaulo/windowhop/issues/34), [#72](https://github.com/martonpaulo/windowhop/issues/72) |

### Window managers, automation tools, and AX libraries

| Repository | License (from file) | Reviewed revision | Private API | Areas | Verdict | Issues |
| --- | --- | --- | --- | --- | --- | --- |
| [nikitabobko/AeroSpace](https://github.com/nikitabobko/AeroSpace) | MIT | `5f08f9c0`, 2026-09-21 | Partial (`_AXUIElementGetWindow` only) | `WindowHopKit`, `Engine/` | Reference only for code (private API); its `axDumps/` corpus is imported as test data (see below); latest-wins cancellable focus job corroborates [#41](https://github.com/martonpaulo/windowhop/issues/41) | [#41](https://github.com/martonpaulo/windowhop/issues/41), [#90](https://github.com/martonpaulo/windowhop/issues/90), [#115](https://github.com/martonpaulo/windowhop/issues/115) |
| [mrkai77/Loop](https://github.com/mrkai77/Loop) | GPL-3.0 | `df26d565`, 2026-09-06 | Yes (SkyLight, `@_silgen_name`) | `Input/` | Reference only; its event tap re-enables only after `tapDisabledByTimeout`, not `tapDisabledByUserInput`, and tears down after a restart cascade | [#84](https://github.com/martonpaulo/windowhop/issues/84) |
| [rxhanson/Rectangle](https://github.com/rxhanson/Rectangle) | MIT (GitHub reports NOASSERTION because of the Spectacle notice) | `12a9bc79`, 2026-09-16 | Partial (`_AXUIElementGetWindow`) | `Engine/` | Reference only (window management is a non-goal; `AXEnhancedUserInterface` handling matters only when setting frames) | none |
| [Hammerspoon/hammerspoon](https://github.com/Hammerspoon/hammerspoon) | MIT | `23e387e2`, 2026-07-08 | Partial (`_AXUIElementGetWindow`, `CGSSetDebugOptions`, Spaces) | `Engine/` | Reference only (`hs.window.filter` default app skip lists and allowed roles) | none |
| [tmandry/Swindler](https://github.com/tmandry/Swindler) | MIT | `bf2c42f1`, 2022-09-05 (last push 2023-12-31) | No | `Engine/` | Reference only (unmaintained, PromiseKit-based; public-API Space identity via per-display tracker windows and fake-AX test doubles) | none |
| [ianyh/Amethyst](https://github.com/ianyh/Amethyst) | MIT | `6508ee2c`, 2026-08-19 | Yes (`CGSCopySpaces*`, `_SLPSSetFrontProcessWithOptions`) | none | Excluded (tiling non-goal; private Spaces and focus) | none |
| [asmvik/yabai](https://github.com/asmvik/yabai) | MIT | `dd845723`, 2026-06-14 | Yes (SkyLight; scripting addition needs SIP partially disabled) | none | Excluded (private API, SIP) | none |

### Imported test data

`Tests/WindowHopTests/Fixtures/AeroSpaceAXDumps/` is AeroSpace's `axDumps/` directory copied
verbatim from `5f08f9c0c9daea6bb0f652da71d80a02e0b3f6cf` (2026-09-21): 125 real AX attribute
dumps labeled `window`, `dialog` or `popup`. It is MIT-licensed data, Copyright (c) 2023
Nikita Bobko; the license travels with it as `LICENSE.txt` in that directory. No AeroSpace
code is imported or ported. `AeroSpaceAXDumpCorpusTests` maps each dump to `WindowFacts`
and the Picture-in-Picture facts and asserts WindowHop's decision; every disagreement with a
label is recorded there with its reason
([#115](https://github.com/martonpaulo/windowhop/issues/115)). To refresh, copy the directory
from a newer revision, re-pin it here, and re-read each changed decision.

## Consulting other sources when planning

1. **When.** For the same areas as the AltTab rule — window discovery, screens, input, focus,
   permissions, AX behavior — and for previews, check AltTab first, then the rows above whose
   Areas column matches. Prefer the issues already linked in a row over a fresh read.
2. **License gate.** Before copying anything, read the source's license file at the pinned
   revision; GitHub metadata alone is not enough. Only MIT, BSD, Apache-2.0, and GPL-3.0
   (or later) code may be incorporated, with its notices. FSL, GPL-2.0-only, proprietary, or
   unlicensed code is *reference only*, whatever the repository's visibility or price.
3. **Private-API gate.** A source that uses SkyLight, `CGS*`, `SLS*`, `SLPS*`, `_AX*` or
   `@_silgen_name` is never *reuse code*; its public-API rules may still be re-implemented.
4. **Recording a port.** Add a Retained-table row naming the source file and revision (for a
   non-AltTab source, name the repository), comment the constraint at the port site, and cite
   the source commit hash in the commit message. Incorporated code keeps its original
   copyright and license notice.
5. **Updating this catalog.** Re-pin a row (revision, date, license, private-API check) when
   it is consulted for a new issue; add a source only with the same fields; a proposed
   improvement becomes its own issue and is linked from its row.
