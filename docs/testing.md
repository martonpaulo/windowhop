# Testing WindowHop

## Automated suite

```sh
swift build && swift test   # 143 unit and integration tests, zero warnings
scripts/validate.sh         # repository and documentation invariants
```

The suite covers both held and sticky session state machines; tab grouping; Settings
window lifecycle; title fallback; MRU; keyboard shortcuts; persistence and migration;
and the shared inclusion policy for minimized, hidden-app, PiP, other-Space, and
other-display windows.

Preview regressions pin:

- authorized, denied, restricted, not-determined, and revoked-during-use permission
  classification;
- loading, permission-required, unavailable, cached, and loaded states over one fixed
  canvas;
- stale asynchronous results to the stable window id and current session generation;
- borderless App Icons selection and the shared semantic preview selection plate in
  Light and Dark Mode;
- intentional semantic letterbox surfaces for wide and tall sources;
- the bottom-right app badge and exact `closeButton.center == canvas.origin` geometry;
- clip-safe 44 pt overlay hit areas, consistent row/column spacing, and overlay-only
  Settings geometry;
- expanded-preview target replacement, rapid navigation, same-app identities, closed
  targets, and cancellation invalidation without origin/activation state.

## Release and identity validators

```sh
scripts/verify-release-identity.sh build/WindowHop.app
scripts/verify-update-continuity.sh <previous.app> <candidate.app>
scripts/verify-dmg-branding.sh artifacts/WindowHop-1.2.0.dmg
```

`verify-release-identity.sh` fails unless the app has:

- bundle id `com.perso.windowhop` and Team ID `TBN79KU9ML`;
- the reviewed stable Developer ID Application leaf certificate;
- the exact expected designated requirement;
- hardened runtime and the expected entitlement set;
- a valid deep signature and no nested executable signed by another team.

`verify-update-continuity.sh` applies the same contract to both releases and compares
their effective designated requirements, identifiers, teams, and entitlements.
`verify-dmg-branding.sh` validates the image, Finder resource icon, mounted volume icon,
background, `.DS_Store`, app, and Applications alias. The official workflow then waits
for notarization, staples and validates app and DMG tickets, and runs Gatekeeper before
creating a release.

## Debug and visual harness

```sh
.build/debug/WindowHop --dump-windows
.build/debug/WindowHop --dump-permissions
.build/debug/WindowHop --demo-switcher [--dark] [--many]
.build/debug/WindowHop --render-ui <directory>
WINDOWHOP_DEBUG=1 .build/debug/WindowHop
```

`--render-ui` produces synthetic, privacy-safe PNGs for:

- App Icons and Window Previews in Light and Dark Mode;
- loaded, letterboxed, loading, unavailable, and permission-required previews;
- expanded preview in both appearances;
- multi-row overflow;
- every Settings pane.

Development comparison captures should retain the previous design plus the selected
borderless/near-borderless, separator, and focus-plate candidates under `artifacts/`.
Only the selected coherent implementation belongs in runtime code and README images.

## Sparkle end-to-end

`--updater-e2e <feed-url>` drives a real `SPUUpdater` with an auto-accepting user driver.
The established local fixture validates three paths:

1. an older build downloads, EdDSA-verifies, replaces in place, and relaunches a newer
   build;
2. the newer build reports no update against the same feed;
3. a corrupted `sparkle:edSignature` is rejected and leaves the installed app unchanged.

For release-candidate continuity, build two Developer ID-signed bundles, validate both
with `verify-update-continuity.sh`, sign the candidate ZIP with Sparkle's `sign_update`,
serve a local appcast, and run the old bundle's `--updater-e2e` binary. Never put an
ad-hoc or development-signed app in the update feed.

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
- [ ] Wide, tall, small-dialog, and display-ratio snapshots aspect-fit over the intentional
      surface without distortion, cropping, or transparent holes.
- [ ] Loading, permission-required, unavailable, and loaded cards retain identical canvas,
      badge, title, Close, selection, and hit-test geometry.
- [ ] Close is fully drawn and centered on the loaded canvas origin; the Settings control
      stays visually attached to the panel corner.
- [ ] VoiceOver announces selected title/app/tab count; keyboard focus, Increase Contrast,
      Reduce Transparency, Reduce Motion, and larger accessibility text remain usable.

### Permissions

- [ ] App Icons works without Screen Recording.
- [ ] Not-determined Window Previews shows Permission required before Loading, with one
      permission action for the panel.
- [ ] Denied/restricted state opens the correct Privacy & Security pane and never retries
      while unavailable.
- [ ] Returning after grant starts capture and replaces placeholders without movement.
- [ ] Revoking Screen Recording during a session returns to Permission required without a
      loop or stale preview substitution.
- [ ] Accessibility revocation restores native ⌘Tab fail-safe behavior.

### Installation, update, and TCC continuity

- [ ] The DMG file is branded in Finder icon, list, and column views; the mounted volume is
      branded on the Desktop and opens at the intended compact icon-view layout.
- [ ] Dragging the real app to the real Applications alias installs cleanly; labels and
      icons do not overlap on a second Mac/display scale.
- [ ] The 1.1.2 app and 1.2.0 candidate have identical effective designated requirements,
      Team ID, bundle/signing identifier, entitlements, and Developer ID leaf identity.
- [ ] Grant Accessibility and Screen Recording to 1.1.2, perform the automatic Sparkle
      1.1.2 → 1.2.0 update in place, and confirm both grants remain effective.
- [ ] Perform a signed 1.2.0 → test-update cycle and confirm the same grants remain.
- [ ] Replace 1.1.2 manually from the notarized DMG in Applications and confirm permissions
      remain associated with WindowHop.
- [ ] No updater helper or temporary app bundle requests application permissions.
- [ ] The notarized app/DMG validate and staple successfully; Gatekeeper accepts both; the
      updater detects 1.2.0 and rejects a tampered signature.

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
