# Testing WindowHop

## Automated suite

```sh
swift build && swift test   # 626+ unit and integration tests, zero warnings
make validate               # repository and documentation invariants
make strings-check          # the String Catalog matches the sources (CI build job)
make lint                   # SwiftLint and swift-format lint, warnings as errors (CI build job)
```

The suite covers both held and sticky session state machines; tab grouping; Settings
window lifecycle; title fallback; MRU; keyboard shortcuts; persistence and migration;
the shared inclusion policy for minimized, hidden-app, PiP, other-Space, and
other-display windows; centralized defaults/reset coverage; and complete event-tap
sequence ownership.

Every test uses [Swift Testing](https://developer.apple.com/documentation/testing)
(`import Testing`, `@Test`, `#expect`, `#require`); there is no XCTest. Run one suite
or one test by its identifier:

```sh
swift test list                                 # every test identifier
swift test --filter SwitcherStateTests          # one suite
swift test --filter PreferencesTests/defaultValues   # one test
```

Swift Testing runs suites in parallel, where XCTest ran one test at a time:

- A suite that drives AppKit or other process-wide state (windows and key status,
  `UserDefaults.standard`, the default notification center, the main run loop) is nested
  in `SharedAppState` (`Tests/WindowHopTests/SharedAppState.swift`), which is
  `.serialized`: its suites run one test at a time, setup to teardown.
- `ShortcutFormatter.keyLabels` is process-wide. A test that installs a layout runs on
  the main actor and restores the ANSI table before it returns, and every suite that
  reads printable-key labels runs on the main actor, so no test sees another's layout.
- Setup is the suite's `init`; teardown is the `deinit` of a `final class` suite.
- A test that needs a display uses the `.needsDisplay` trait; Reduce Motion skips are
  `.disabled(if:)` traits; a condition known only inside the test calls `Test.cancel`.

AX observer lifecycle changes also run under the Thread Sanitizer:

```sh
swift test --sanitize=thread   # must report no "WARNING: ThreadSanitizer"
```

`TrackedAppLifecycleTests` overlaps start/stop requests on real observers (it observes
Finder and skips without it); `ObserverLifecycleTests` pins the generation rules.

Preview regressions pin:

- authorized, denied, restricted, not-determined, and revoked-during-use permission
  classification;
- loading, permission-blocked, unavailable, cached, and loaded skeleton/image states over one fixed
  canvas;
- stale asynchronous results to the stable window id and current session generation;
- window↔snapshot matching: Chromium-style decorated titles, same-app windows sharing
  one frame, invisible helper windows, and indistinguishable windows that must stay
  without a preview instead of receiving a guess;
- one shared Settings pane size, so selecting a pane never resizes the window;
- the Settings window position restored across launches with the selected pane's size kept, and a
  saved frame on a vanished display recovered onto the main display;
- borderless App Icons selection and the shared semantic preview selection plate in
  Light and Dark Mode;
- intentional semantic letterbox surfaces for wide and tall sources;
- the bottom-right app badge and exact `closeButton.center == canvas.origin` geometry;
- clip-safe 44 pt overlay hit areas, consistent row/column spacing, compact hidden metadata,
  and contextual overlay-only Settings geometry;
- expanded-preview target replacement, rapid navigation, same-app identities, closed
  targets, and cancellation invalidation without origin/activation state.

## Release and identity validators

```sh
scripts/verify-release-identity.sh --app build/WindowHop.app
scripts/verify-update-continuity.sh <previous.app> <candidate.app>
scripts/verify-dmg-branding.sh --dmg artifacts/WindowHop-1.3.1.dmg
```

`verify-release-identity.sh` fails unless the app has:

- bundle id `com.martonpaulo.windowhop` and Team ID `TBN79KU9ML`;
- the reviewed stable Developer ID Application leaf certificate
  (`Support/ReleaseCertificate.cer`);
- the exact expected designated requirement;
- hardened runtime and the expected entitlement set;
- a valid deep signature and no nested executable signed by another team.

`verify-update-continuity.sh` applies the same contract to both releases and compares
their effective designated requirements, identifiers, teams, and entitlements.
`tests/scripts/verify-update-continuity-tests.sh` (run by `make validate`) covers it with a
fake `codesign`.

The first release after the identifier move (#43) is the one exception. Its previous
release is signed with the old identifier, so the plain comparison fails by design. For
that release only, run:

```sh
scripts/verify-update-continuity.sh --identifier-transition <old> com.martonpaulo.windowhop \
    <previous.app> <candidate.app>
```

`<old>` is `LegacyDomainMigration.legacyDomainName`. The previous app must pass the full
release-identity contract under `<old>`, the candidate under the new identifier, and the
two designated requirements may differ only in the `identifier "…"` clause. The mode does
not keep the TCC grant: users grant Accessibility (and Screen Recording, in Window
Previews mode) again after that update. Before that release, also prove with the Sparkle
end-to-end fixture below that an old-identifier build installs the new-identifier update.
`verify-dmg-branding.sh` validates the image, Finder resource icon, mounted volume icon,
background, `.DS_Store`, app, and Applications alias. The official workflow then waits
for notarization, staples and validates app and DMG tickets, and runs Gatekeeper before
creating a release.

## Debug and visual harness

```sh
.build/debug/WindowHop --dump-windows
.build/debug/WindowHop --dump-permissions
.build/debug/WindowHop --dump-previews
.build/debug/WindowHop --demo-switcher [--dark] [--many]
.build/debug/WindowHop --demo-settings [pane]
.build/debug/WindowHop --render-ui <directory>
.build/debug/WindowHop
log stream --level debug --process WindowHop   # in a second terminal
```

`--dump-previews` prints the real switcher-entry → window-server-window pairing the next
session would capture from, without requesting, keeping, or writing any image. It is the
fastest check for "this window shows another window's preview": stack several windows of
one browser at the same size and confirm every line resolves to its own title.

`--render-ui` produces synthetic, privacy-safe PNGs for:

- App Icons and Window Previews in Light and Dark Mode;
- loaded, letterboxed, loading, unavailable, and permission-blocked previews;
- expanded preview in both appearances;
- multi-row overflow;
- every Settings pane (content only).

The published Settings images instead capture the real window, because its toolbar exists
only on a real window:

```sh
build/WindowHop.app/Contents/MacOS/WindowHop --demo-settings switcher  # prints WINDOW_ID <n>, then READY
screencapture -x -l<n> site/screenshots/settings-windows.png
```

`--demo-settings` shows the running user's real preferences, so set the documented
defaults before capturing and restore them afterwards.

Development comparison captures should retain the previous design plus the selected
borderless/near-borderless, separator, and focus-plate candidates under `artifacts/`.
Only the selected coherent implementation belongs in runtime code and published images.

## Sparkle end-to-end

`--updater-e2e <feed-url>` drives a real `SPUUpdater` with an auto-accepting user driver.
The established local fixture validates three paths:

1. an older build downloads, EdDSA-verifies, replaces in place, and relaunches a newer
   build;
2. the newer build reports no update against the same feed;
3. a corrupted `sparkle:edSignature` is rejected and leaves the installed app unchanged.

For release-candidate continuity, build two Developer ID-signed bundles, validate both
with `verify-update-continuity.sh`, sign the candidate ZIP with
`scripts/sign-update.sh --archive <zip>`, which runs the resolved package's `sign_update`
(the same release as the embedded framework; never a separately downloaded copy), serve a local appcast, and run the old
bundle's `--updater-e2e` binary. Never put an ad-hoc or development-signed app in the
update feed.

## Published screenshots

`scripts/capture-screenshots.sh` produces everything under `site/screenshots/`. It is a
driver over `scripts/lib/capture.sh`, skill-deck's canonical capture protocol, kept
byte-identical. It launches `--demo-switcher` / `--demo-settings`, which print the handshake
`SCALE <backing scale>`, `WINDOW_ID <n>` (Settings adds `KEY true|false`) and then `READY`
once the window has settled; the library refuses a scale below 2 or a Settings window that
is not key, captures that one window with `screencapture -l<n>`, stops the demo and writes
lossless WebP. The driver then caps the published width and writes the srcset variants.

Capturing an on-screen window is what makes those images look like macOS: `screencapture`
records the window as the compositor draws it, so the PNG keeps the rounded corners, the
real glass material, the window's own drop shadow, and transparent elevation around it, at
the display's backing scale. The offscreen `--render-ui` harness cannot: it rasterizes the
view tree into a flat bitmap with square corners, no shadow, and the non-glass fallback
background. `--render-ui` remains the layout and regression harness; it is not a source of
published images.

Requirements and constraints:

- **The capture is 2x on any Mac.** A capture inherits the backing scale of the display the
  window is on, so a 1x screen would halve every published image. When the main display is
  1x, the script builds and starts `scripts/capture-display.m`: a temporary HiDPI virtual
  display, extended to the right of the main display with `kCGConfigureForAppOnly`, so the
  arrangement reverts and the display disappears when the script exits. The demos move their
  window to the display with the highest backing scale before they announce `SCALE`, so the
  window server composites them at 2x with their real material and shadow. The tool uses the
  private `CGVirtualDisplay` class, a recorded exception limited to capture tooling
  (AGENTS.md › Public Apple APIs only, #116); it needs clang from the command line tools.
- Screen Recording permission for the process running the script.
- `-l<windowid>` captures exactly the demo's own window, so no personal window can appear;
  `-o` is deliberately not passed, because it would drop the shadow.
- `--columns` pins the switcher grid, so wrapping does not follow whatever display the
  operator happens to use.
- The Settings demo re-activates its window before announcing readiness; a capture taken
  while it is not key documents a greyed-out title bar and inactive controls.
- The Settings captures pass `--light` or `--dark`, which pins the window's appearance.
  Without it the window follows the operator's system setting, so the published images would
  change with whoever ran the script. Every published image exists in both appearances, and
  the site shows the one that matches the visitor's. For the same reason
  they pass `-AppleShowScrollBars WhenScrolling`, an argument-domain override for that one
  process, so an operator's "Show scroll bars: Always" does not draw a scroller track.
- The Settings demo hides the window title (`titleVisibility = .hidden`): published images keep the
  traffic lights and the toolbar, and the product name is already beside every image.
- The `width`/`height` attributes in `site/index.html` are the captured pixels halved. Update
  them whenever the captures change size, or the site reserves the wrong box and the hero
  image lands misaligned.
- Each capture declares a **maximum published width**, or `native`. A capture is taken at
  the display's backing scale, which is only the right size if the image is shown at half
  those pixels somewhere. The switcher panel is 1206 pt wide, so its capture is 2412 px,
  while the site shows it in a 434 pt slot and the README at about 830 pt. Capping it at
  twice the largest slot keeps it sharp everywhere and stops visitors paying for pixels
  nobody displays. Resampling uses `sips`, which is built into macOS and indistinguishable
  here from ImageMagick's Lanczos.
- Screenshots are published as **lossless WebP**, converted by the script with
  `cwebp -lossless`. The pixels are identical to the PNG, the alpha the shadow depends on
  survives, and the set drops from about 2.9 MB to 1.2 MB. Every browser on the supported
  macOS versions reads WebP, and GitHub renders it in the README, so no PNG fallback is kept
  — a second copy would only be an unreferenced file the repository validator rejects.
- The hero is also published in narrower widths, `switcher-previews-{light,dark}-<width>.webp`
  (480, 720, 958, 1200), which the site's `srcset` and preload `imagesrcset` list next to the
  full-size file so a phone does not download 1916 px to draw about 350. The script resamples
  them from the lossless capture and encodes them `-near_lossless 60`: plain lossless makes a
  resampled screenshot so much larger that a narrower width can outweigh the full one.
  `make validate` checks that every `srcset` candidate exists.

## Release publication order

The updater feed may only ever advertise files that already exist, so
publication is strictly ordered:

1. `scripts/publish-release.sh --tag <tag> --notes-file <notes> --artifact <file>…` stages
   every artifact in a **draft** release, verifies the complete set against the local files
   by name, byte count and SHA-256 digest (GitHub's stored `digest`), publishes, and verifies
   the draft state and the assets once more against the now-public release.
2. Only then does `scripts/make-appcast.sh` add the entry and push it to `main`.

Both steps are idempotent under retry, and neither is idempotent by assumption:

- A complete, matching public release is a read-only no-op. An **incomplete** one — a
  missing asset, one whose size differs, or a same-size asset with other bytes — fails and
  is left to an operator. An asset GitHub reports no digest for cannot be verified and also
  fails. A public asset is never overwritten.
- An incomplete **draft** is completed rather than recreated.
- A `gh` failure that is not "release not found" (auth, network) is fatal, never read as
  "no release yet".
- An unreadable draft state is fatal, never read as public, both before any write and
  after publishing; a release still a draft after publishing also fails. Either way the
  appcast step never runs.
- An existing appcast entry for the version is a no-op only when its build number,
  enclosure URL, signature and length all match. Any mismatch fails and prints the
  conflicting entry.

Because the feed is written last, every failure before it leaves `main` unmoved, so the
workflow's `tag commit == current origin/main` gate still holds for a normal rerun.

The release scripts are byte-identical copies of skill-deck's `project-release` assets, and
skill-deck's own suites own their behavior. `scripts/validate.sh` checks that each copy parses
and answers `--help`; `check_repository_conventions.py` reports a drifted copy.
`tests/scripts/publish-release-tests.sh`, which `scripts/validate.sh` also runs, pins the
publication counterexamples WindowHop's audit found against the real script and a fake
`gh` — no network, no token, no signing material, no real release.

### Release rehearsal

An ad-hoc rehearsal of every local step, with no secret and no publication:

```sh
scripts/package-app.sh --force                     # ad-hoc: DEVELOPER_ID_IDENTITY unset
scripts/make-dmg.sh --force
scripts/verify-dmg-branding.sh --dmg artifacts/WindowHop-<version>.dmg
scripts/sign-update.sh --archive artifacts/WindowHop-<version>.zip   # login-Keychain key
```

Then run `scripts/make-appcast.sh --version … --build-number … --archive … --signature …`
in a scratch copy of the repository and check that `appcast.xml` gained one well-formed
entry. Signed, notarized publication is proven only by a real tag.

## Manual release checklist

Run from a clean copy under Applications with real Accessibility and, where applicable,
Screen Recording permission.

### Navigation

- [ ] ⌘Tab opens immediately, cycles and wraps; Shift reverses; arrow navigation follows
      rows; modifier release confirms the selected real window.
- [ ] Escape or outside click closes WindowHop and leaves focus, stacking, Space, and MRU
      unchanged.
- [ ] Return, Space, and tile click activate exactly the selected real window.
- [ ] Pausing 3 seconds enlarges the latest preview inside WindowHop without activating,
      raising, focusing, reordering, or moving the target window.
- [ ] Rapid navigation cancels stale dwell work; navigating away closes the enlarged view;
      a closed target selects a valid neighbor without crashing.
- [ ] Sticky mode ignores modifier release and confirms/cancels only through its explicit
      controls.
- [ ] The configured ⌘Tab sequence never leaks key-down or key-up events to the native
      app switcher during forward/reverse, rapid, repeated, cancel, or Settings flows.
- [ ] Disable/enable, shortcut reassignment, relaunch, sleep, and wake leave one active
      event tap with no obsolete chord interception.
- [ ] Disable during a close confirmation, re-enable: the next ⌘Tab and Open WindowHop
      sessions are visible.
- [ ] With Show Dock icon on, the menu bar offers WindowHop › Services, Hide WindowHop (⌘H),
      Hide Others (⌥⌘H), Show All, Window › Zoom (dimmed for Settings), and Help › Report an
      Issue…; ⌘C ⌘V ⌘A work in a Settings text field and ⌘W closes Settings in both Dock
      icon modes.
- [ ] WindowHop › About WindowHop opens Settings on the About pane (also when Settings is
      already open on another pane); its version, build, release date and copyright line
      match the bundle's `Info.plist`.

### Window inclusion

- [ ] Current defaults show normal windows on all visited Spaces/displays while excluding
      minimized, hidden-app, and PiP windows.
- [ ] Each opt-in takes effect without relaunch and does not duplicate tab groups or admit
      menus, tooltips, system overlays, or WindowHop helper UI.
- [ ] Identical-title windows stay distinct; Safari tab counts remain metadata, not entries.
- [ ] Other-Space and other-display toggles rebuild the list correctly.

### Visuals and accessibility

- [ ] App Icons has no unselected border; its selected state is one rounded background in
      Light and Dark Mode.
- [ ] Preview surfaces remain legible over bright/dark content; selection uses one semantic
      plate with no stacked gray/blue frames and no layout shift.
- [ ] Wide, tall, small-dialog, and display-ratio snapshots cover their card without
      distortion or empty bands; only the canvas has rounded corners (#127).
- [ ] Loading, permission-blocked, unavailable, and loaded cards retain identical canvas,
      badge, title, Close, selection, and hit-test geometry.
- [ ] Close is fully drawn and centered on the loaded canvas origin; the Settings control
      stays hidden in unhovered cycling, appears on panel hover, and remains visible for a
      persistent session without reflow.
- [ ] VoiceOver announces selected title/app/tab count; keyboard focus, Increase Contrast,
      Reduce Transparency, Reduce Motion, and larger accessibility text remain usable.
- [ ] Every Settings pane keeps the same window size and position, and the position survives
      relaunch; nothing is clipped, and a pane taller than the canvas scrolls instead of
      growing the window. Moved to a second display that is then disconnected, Settings
      reopens centered on the main display.
- [ ] With three or more windows of one Chromium browser — same size, and again with two of
      them stacked at the same position — each card shows its own window, and a window that
      cannot be told apart shows the skeleton rather than another window's content.

### Permissions

- [ ] App Icons works without Screen Recording.
- [ ] Not-determined Window Previews shows a static fallback rather than Loading, with one
      permission action for the panel and no per-card permission text.
- [ ] Denied/restricted state opens the correct Privacy & Security pane and never retries
      while unavailable.
- [ ] Returning after grant starts capture and replaces placeholders without movement.
- [ ] Revoking Screen Recording during a session returns to the static fallback without a
      loop or stale preview substitution.
- [ ] Accessibility revocation restores native ⌘Tab fail-safe behavior.
- [ ] With the menu bar item shown, Disable, then revoke Accessibility: the item's shape and
      its accessibility label (Accessibility Inspector) change to paused, then to
      Accessibility access needed, before its menu is opened.
- [ ] Settings → General → Launch at login follows the real login item: turn it on and off
      and check System Settings › General › Login Items each time. With Settings left open,
      remove WindowHop in Login Items and return: the toggle is off without a click. When
      macOS asks for approval, the toggle stays on, the pane says approval is pending, and
      Open Login Items Settings… opens that pane. A bare `swift build` product shows the
      toggle dimmed with the Applications-folder explanation.

### Installation, update, and TCC continuity

- [ ] The DMG file is branded in Finder icon, list, and column views; the mounted volume is
      branded on the Desktop and opens at the intended compact icon-view layout.
- [ ] Dragging the real app to the real Applications alias installs cleanly; labels and
      icons do not overlap on a second Mac/display scale.
- [ ] The 1.2.0 app and 1.3.1 candidate have identical effective designated requirements,
      Team ID, bundle/signing identifier, entitlements, and Developer ID leaf identity.
- [ ] Grant Accessibility and Screen Recording to 1.2.0, perform the automatic Sparkle
      1.2.0 → 1.3.1 update in place, and confirm both grants remain effective.
- [ ] Perform a signed 1.3.1 → test-update cycle and confirm the same grants remain.
- [ ] Replace 1.2.0 manually from the notarized DMG in Applications and confirm permissions
      remain associated with WindowHop.
- [ ] No updater helper or temporary app bundle requests application permissions.
- [ ] The notarized app/DMG validate and staple successfully; Gatekeeper accepts both; the
      updater detects 1.3.1 and rejects a tampered signature.

### Bundle identifier move (the first release after #43 only)

These replace the "grants remain" items above for that one release.

- [ ] `verify-update-continuity.sh --identifier-transition` passes for the last
      old-identifier release and the candidate; the plain mode fails for the same pair.
- [ ] A local Sparkle appcast updates the signed old-identifier release to the candidate.
      If Sparkle refuses the new identifier, stop: do not tag.
- [ ] After that update, onboarding asks for Accessibility; granting it makes ⌘Tab work.
      Window Previews asks for Screen Recording again. The old WindowHop entries in
      Privacy & Security can be removed.
- [ ] Every setting chosen in the old release (shortcuts, appearance, window filters,
      icons, update checks, Settings position and pane) is unchanged, and a second launch
      keeps later changes.
- [ ] With Launch at login on in the old release, the candidate is registered in System
      Settings › General › Login Items after one launch, with no stale second entry.
- [ ] `spctl -a -vvv` and `codesign -dvvv` on the notarized app show
      `com.martonpaulo.windowhop`.

## Historical integration evidence

### 1.2.0 candidate — 2026-07-18, macOS 26.5, Apple Silicon

- 143 tests and repository validation passed with zero warnings/failures.
- The signed 1.1.2 baseline and signed 1.2.0/10200 candidate passed the exact certificate,
  designated-requirement, Team ID, identifier, entitlement, hardened-runtime, and nested
  signature continuity validators.
- In a controlled same-path replacement, 1.1.2 discovered real windows before replacement;
  1.2.0 then reported Accessibility and Screen Recording as authorized and continued real
  discovery. The user's installed app was not modified.
- A real local Sparkle appcast updated the temporary signed 1.1.2 bundle to 1.2.0/10200;
  EdDSA verification, extraction, replacement, relaunch, final identity, and both TCC grants
  passed. A second signed 1.2.0/10200 → 10201 test-update cycle passed the same checks.
- The signed DMG passed image/branding/layout validation; its mounted app passed deep
  identity checks; a clean temporary install launched the real discovery harness; and the
  release artifact rendered all 13 privacy-safe UI captures.
- Apple notarization, stapling, Gatekeeper, public updater detection, and final downloadable
  asset checks remain release-workflow gates and are not claimed by this local candidate run.

On macOS 26.5/Apple Silicon, live development previously verified native-switcher
suppression without modifying the system symbolic hotkey, real activation on confirm,
Escape cancellation with focus unchanged, 0.0% idle CPU, and the three-path Sparkle
fixture above. A 120-tile synthetic panel first opened in about 100 ms and subsequently
updated in 1–3 ms. These historical numbers are context, not a substitute for the release
checklist above.
