# WindowHop working rules

The build, rules, architecture, interface, documentation, test and release sections, moved
unchanged out of `AGENTS.md` to keep it under the 24,000-byte budget ([#154](https://github.com/martonpaulo/windowhop/issues/154)).
`AGENTS.md` routes here before any edit; its route map names this file.

## Contents

- [Build and validate](#build-and-validate)
- [Hard rules](#hard-rules)
- [Architecture (see docs/architecture.md)](#architecture-see-docsarchitecturemd)
- [Sessions](#sessions)
- [User-facing feature defaults and configurability](#user-facing-feature-defaults-and-configurability)
- [Product interface and accessibility](#product-interface-and-accessibility)
- [Code, comments, and documentation](#code-comments-and-documentation)
- [Tests and validation](#tests-and-validation)
- [Git and releases](#git-and-releases)

## Build and validate

```sh
swift build && swift test        # must pass, zero warnings (Package.swift makes warnings errors)
make build && make test          # as CI runs them; also fail on any Sources/ or Tests/ `warning:` line
make validate                    # repository invariants (must pass); runs scripts/validate.sh
make strings                     # regenerate the String Catalog and en.lproj after a copy change
make strings-check               # fail when the catalog is out of date (CI build job)
make lint                        # SwiftLint + swift-format lint, strict (shared .swiftlint.yml/.swift-format)
make format                      # rewrite Sources/ and Tests/ with swift-format; run before committing
make check                       # build, lint, test, validate, strings-check: the gate before a commit
make help                        # every target: also app, dmg, icon, screenshots, keys, appcast, clean
make screenshots                 # published screenshots (2x; adds a temporary 2x display on a 1x Mac)
make app FORCE=1                 # .app with Sparkle + zip (scripts/package-app.sh; ad-hoc unless DEVELOPER_ID_IDENTITY)
make dmg FORCE=1                 # app, then the DMG (scripts/make-dmg.sh)
scripts/sign-update.sh --archive <zip>  # Sparkle EdDSA attributes (login Keychain key)
```

Runtime checks (Accessibility permission is inherited when run from a trusted terminal):

```sh
.build/debug/WindowHop --dump-windows           # real discovery works?
.build/debug/WindowHop --dump-previews          # entry → captured window pairing (no image)
.build/debug/WindowHop --render-ui /tmp/shots   # switcher + settings renders, light/dark/overflow
.build/debug/WindowHop --demo-switcher [--dark] [--many]  # on-screen panel demo
.build/debug/WindowHop --updater-e2e <feed-url> # headless Sparkle end-to-end (see docs/testing.md)
.build/debug/WindowHop                          # run it; diagnose input/session behavior with:
log stream --level debug --process WindowHop   # unified-log debug messages (Logger, subsystem = bundle id)
```

The release scripts, `scripts/validate-site.sh`, `scripts/social-card.sh` and
`scripts/lib/capture.sh` are byte-identical copies of skill-deck's `project-release` assets:
never edit them here; change the callers, or change them upstream and copy again.

Keep task logs in `artifacts/` (gitignored). Inspect a failed log before rerunning.

## Hard rules

- **Public Apple APIs only.** No private frameworks, no `_`-prefixed SPI, no
  `@_silgen_name`. One recorded exception outside the app: `scripts/capture-display.m`, local
  screenshot tooling that is never compiled into WindowHop, uses the private
  `CGVirtualDisplay` class to create a temporary 2x display (Decided on [#116](https://github.com/martonpaulo/windowhop/issues/116)). AX attribute *strings* not in headers (e.g. `AXFullScreen`) are fine.
  For the same reason, so are the undeclared `com.apple.screenIsLocked` /
  `com.apple.screenIsUnlocked` names observed through the public
  `DistributedNotificationCenter` (`Engine/SessionMonitor.swift`); if they stop firing,
  behavior falls back to not knowing the lock state (Decided on [#38](https://github.com/martonpaulo/windowhop/issues/38)).
- **Screen Recording is opt-in only**: ScreenCaptureKit may be used exclusively in
  `Engine/PreviewProvider.swift` (validate.sh enforces this), only during an open
  session in Window Previews mode, never idle-capturing, never persisting images.
  App Icons mode (the default) must always work without the permission.
- **No polling while idle.** Observe events (AXObserver, KVO, notifications). Bounded
  timers are allowed only while a session or the onboarding window is open.
- **The event-tap callback must stay tiny and synchronous** (`EventTap.handle`): decide
  consume/pass with plain comparisons, post to main, return. Never do AX/IO there.
- **Never consume `flagsChanged` events**, and never disable the native Cmd-Tab symbolic
  hotkey. Fail-safe = if WindowHop dies, native switching works untouched.
- **One entry per top-level window; tabs are never entries** (see TabGroupResolver).
  The own-process exclusion has exactly one exception: the registered Settings window.
- **Sparkle is the only runtime dependency**, and update checks are the only permitted
  network activity. No telemetry, no analytics, no accounts, no Pro/license code.
- The bundle identifier is `com.martonpaulo.windowhop` — everywhere, always. The previous
  identifier appears only in `WindowHopKit/LegacyDomainMigration.swift` (validate.sh enforces
  this), which copies its settings domain once ([#43](https://github.com/martonpaulo/windowhop/issues/43)).
- Closing a window always goes through the confirmation dialog (Cancel is default);
  Quit is graceful termination only; Force Quit requires its own second confirmation.
- **Appearance is fixed**: icon size is Large, the only appearance options are App Icons
  (default) and Window Previews, and theming is system Light/Dark only. No themes, no
  custom sizes, no layout or opacity options. This rule governs how the panel *looks*.
  Where the panel is drawn is display behavior, not appearance, and lives with the other
  display settings in Settings → Switcher (see `WindowHopKit/PanelPlacement.swift`).
- All shortcut strings render through `WindowHopKit/ShortcutFormatter` — never hardcode a
  second representation of the same key.
- All UI dimensions come from `UI/DesignTokens.swift` — no hardcoded sizes,
  insets, radii, or font sizes in views.
- Official releases are signed with one stable Apple-issued Developer ID Application
  identity (`DEVELOPER_ID_CERT_P12`), notarized and stapled, so the TCC Accessibility
  grant survives updates — never ship ad-hoc, self-signed, or unnotarized releases.

## Architecture (see docs/architecture.md)

- There are no singletons: `AppDelegate` is the composition root and passes every
  long-lived object through initializers (docs/architecture.md › Composition root).
- `WindowHopKit` (`Sources/WindowHopKit/`, the Core) — pure logic in its own target with
  no dependencies. All business rules live here (eligibility, MRU, title fallback,
  tab-group resolution, PiP detection, preview-result ledger, session state machine,
  shortcut model, settings defaults). New behavior rules go here **with unit tests** in
  `Tests/WindowHopKitTests/`, which depends only on the Kit (and the test-only
  `WindowHopTestSupport`, the one maker of `UserDefaults` suites in tests).
  - **Kit import contract** (`scripts/validate.sh` enforces it): `Foundation`;
    `CoreGraphics` for value types only (`CGEventFlags`, `CGRect`, `CGWindowID`);
    `Observation` (the `@Observable` `Preferences`, [#101](https://github.com/martonpaulo/windowhop/issues/101)); and `Synchronization`
    (a standard-library module, used by `ShortcutFormatter`'s `Mutex`). No AppKit, AX,
    `NSWorkspace`, ScreenCaptureKit or Sparkle. This diverges from the shared
    "a Kit imports only Foundation" rule, because the issue's "no AppKit, AX or Sparkle
    imports beyond value types" already admits CoreGraphics value types; wrapping
    `CGEventFlags` and `CGRect` in Kit-owned types was rejected as churn with no safety
    gain ([#100](https://github.com/martonpaulo/windowhop/issues/100)).
  - Every file outside the Kit imports it explicitly (`import WindowHopKit`), never
    through `@_exported import`.
- `WindowHopCore` (`Sources/WindowHopCore/`) holds `Engine/`, `Input/`, `UI/` and `App/`
  and depends on `WindowHopKit` and Sparkle; `Tests/WindowHopTests/` covers it.
- `Engine/` — AX integration: `TrackedApp`/`TrackedWindow`, `WindowStore` (main-thread
  source of truth), `AXNotificationRouter` (AX thread → reads queue → main).
- `Input/` — `EventTap` (tap thread; modes off/watching/sessionHeld/sessionSticky/
  passthrough) and `SwitcherController` (main-thread orchestration).
- `UI/` — AppKit switcher panel (horizontal large-icon tiles, pooled); SwiftUI
  Settings/onboarding; native shortcut recorder.
- `App/` — lifecycle and `UpdateManager` (Sparkle; only starts from a real bundle).

Threading: AX reads/actions on `BackgroundWork` queues, never the main thread; state
mutation and UI on main only. The Swift 6 language mode checks this: main-thread owners
are `@MainActor` (see docs/architecture.md › Concurrency).

## Sessions

Two explicit session modes share one pure state machine (`SwitcherState`):
- **held** (`⌘Tab`): modifier release activates; guarded by a session-scoped timer.
- **sticky** (`Open WindowHop` shortcut, or after a close confirmation): modifier
  release is meaningless; Return/Space/click/Escape end it.
Fixing one mode must not silently change the other — both are covered by tests.

## User-facing feature defaults and configurability

For every new user-facing behavior or presentation feature:

- Explicitly define its default value.
- Decide whether it should be configurable by the user and record that decision in
  implementation notes or product documentation.
- Prefer a Settings option when both enabled and disabled states are legitimate user
  preferences.
- Do not add settings for bug fixes, security behavior, internal implementation details,
  mandatory accessibility behavior, or features with only one valid outcome.
- Store defaults in `WindowHopKit/Preferences.Defaults`. Do not duplicate fallback values in
  views, services, tests, shortcut registration, or migration code.
- Persist configurable preferences through the existing typed `Preferences.Key`
  infrastructure and keep `Preferences` as the runtime source of truth.
- Preserve existing user choices during upgrades; migration may change a stored value
  only when the old representation is obsolete or invalid.
- Add every configurable preference to `Preferences.configurableKeys` so Restore Defaults
  picks it up, except a value that mirrors a system registration (launch at login), which
  the key-contract test lists explicitly. Reset must not change permissions, identity,
  build metadata, caches, system registrations, or non-preference user data.
- Add default, migration, persistence, runtime-update, and reset coverage as applicable.
- Update the Settings-related pull-request checklist whenever this contract evolves.

Features that are intentionally non-configurable must say why in the task implementation
notes. A missing configurability decision is a review failure.

## Product interface and accessibility

- Prefer native platform components and established macOS patterns. Custom UI must provide
  clear product value.
- Before creating or changing an interface, a style, or a visual asset, name what the product
  should communicate and how it should feel to the person using it, from `docs/product.md` and
  recorded brand decisions. Judge typography, colour, density, contrast, motion, imagery and
  copy tone by that intent, not only as layout mechanics. When no intent is recorded, state the
  one you infer and ask before a consequential visual change.
- Define layout, hierarchy, controls, loading, content, empty, error, retry, disabled,
  cancellation, and destructive states when applicable.
- Include keyboard navigation, focus, screen-reader labels, scalable text, contrast, reduced
  motion, and non-color status cues in the same change.
- Accessibility evidence is automated and inspectable: semantics, roles, names and states,
  focus and keyboard order, contrast, and automated audits. Manual screen-reader passes are
  not run; the owner accepts that gap, recorded once in `docs/product.md` under
  `## Accepted evidence gaps`. A missing screen-reader pass never blocks completion, and an
  old criterion that asks for one is struck with a link to that line.
- Keep visible copy in the String Catalog: every user-visible string goes through
  `String(localized:)` or a SwiftUI localizable literal, never a plain `String` literal.
  Log messages, harness output, defaults keys, identifiers, URLs, key glyphs and the bare
  product name stay plain. Interpolate an integer as `String(n)`, since `String(localized:)`
  formats numbers for the user's locale.
- Keep expensive work out of render paths and latency-sensitive paths. Prefer event-driven,
  on-demand, bounded, incremental, and cancelable work.
- Measure before claiming a performance problem, and optimize measured user-visible
  bottlenecks.
- Published screenshots come from `scripts/capture-screenshots.sh` and must never show the
  user's personal windows. It drives `--demo-switcher` / `--demo-settings` on screen and
  captures each window with `screencapture -l<windowid>`, which is what gives the published
  images their rounded corners, real glass material, drop shadow, and elevation. The capture
  is taken at the backing scale of the display the window is on, so it must be 2x: when the
  main display is 1x, the script creates a temporary 2x virtual display
  (`scripts/capture-display.m`) and the demos draw there. `--render-ui` stays the offscreen layout/regression harness — it has no
  shadow and no rounded corners, so it is not a source of published images.

## Code, comments, and documentation

- Conventional Commits; English in code, comments, commits, filenames, tests, configuration,
  and developer documentation.
- Write human-facing English (README, documentation, landing page, product copy, error
  messages) in plain international English that non-native readers understand: one precise
  verb instead of a phrasal verb (`investigate`, not `look into`), internationally known
  words, no idioms or slang, and short active sentences. Established technical terms
  (`log in`, `set up`, `roll back`), commands, identifiers and quoted text stay exactly as they
  are. Clarity comes first; never replace a clear everyday word with a rare formal one.
- Follow the existing formatter, naming, file layout, and architectural conventions.
- Prefer clear types, explicit ownership, and simple control flow over cleverness.
- Comments state constraints the code can't show (ported-rule provenance, macOS quirks). Link
  official documentation when an external rule or workaround must stay visible to prevent a
  regression.
- GPL-3.0 with AltTab attribution is non-negotiable; update `UPSTREAM.md` when porting
  upstream rules (include the upstream commit hash). Never remove upstream notices.
- Update the smallest canonical documentation section when a durable contract changes. Do not
  create empty documentation for possible future use.
- Record a consequential decision in the canonical document that owns the rule, with the
  deciding issue cited beside it as `Decided on #N`. Consequential means that reversing it
  later would cost real work or surprise a user: for example, what opens at launch, the
  supported OS floor, or a data-retention choice. No issue, wiki page or long-lived comment
  serves as a decision register.
- Index those decisions in the `## Decision index` of `docs/product.md`, one row per decision:
  the decision, its outcome, the canonical document, and the deciding issue. The index points
  to the rule and never restates it; an ADR in `docs/adr/` stays the owner of an architectural
  decision, and its row links the ADR.
- Keep the README easy to scan: benefit, behavior, requirements, install, usage, validation,
  privacy, limitations, landing page, download. It opens with the social card
  (`site/social-card.jpg`) and shows no screenshots; screenshots belong to the landing page.
  Use badges and statistics only when they improve comprehension and can stay current.
- Maintain `CHANGELOG.md` in Keep a Changelog format. User-visible changes go under
  `[Unreleased]` when they land, and the release renames that section to the version.
- Preserve the approved `WindowHop` README heading. Give every new or materially edited
  fenced block an explicit language; leave unrelated historical formatting alone.

## Tests and validation

- Add or update focused tests for changed behavior, regressions, persistence, migrations,
  validation, and critical accessibility. Business rules in `WindowHopKit` ship with unit tests.
  Every test uses Swift Testing (`import Testing`), never XCTest; `docs/testing.md` owns the
  rules for suites that share process-wide state.
- A behavioral bug fix includes a regression test proven to fail without the fix: run it
  against the unfixed code and see it fail before committing.
- Test observable contracts at stable seams; avoid tests that only mirror implementation
  details or framework behavior.
- Run the smallest relevant check during iteration. Inspect the first useful failure and make a
  relevant change before rerunning.
- Once stable, run `swift build && swift test` plus `make validate` — both must pass with
  zero warnings before a commit.
- When a change alters behavior, run the real app with its native diagnostics (the runtime
  check flags above, `log stream --level debug --process WindowHop`) and observe the changed
  behavior. Green tests are not seeing it run.
- Never claim a check passed unless it ran successfully. Report exact skips, blockers, residual
  risk, what was verified manually, and what remains unverified.
- A piped check reports the exit code of the last command, not its own: `swift test | tail -3`
  exits 0 when a test fails, and `set -e` does not catch it. Run a gating check unpiped; to
  trim its output, use `set -o pipefail`, or capture it to a file and check the status
  separately. Never chain `&&` off a piped check. A check whose exit code you did not observe
  has not run and is never reported as passing.
- Local browser checks of the website (`docs/website.md`) stay inside these limits:
  - during iteration, check one engine and only the affected pages;
  - run browser automation with one worker;
  - check `uptime` before launching a browser, and do not launch one while the 1-minute load
    average is above 8; wait for the load to fall;
  - run the full two-engine check only as the final step before commit.

## Git and releases

- Follow the branch, commit, push, and versioning policies recorded above.
- Check status and branch before editing and before the final report. Work only on task files
  and leave unrelated changes untouched.
- End a commit subject with its issue number when the commit belongs to one:
  `feat: add the export button (#54)`. Use the issue number, never the pull request's, and
  leave the suffix off when there is no issue.
- Merge a branch with all of its commits: `gh pr merge <number> --merge --delete-branch`.
  Never squash — it discards the one-commit-per-concern history and every issue suffix but one.
  This covers bot pull requests too.
- Inspect the diff before committing. Never commit secrets, caches, generated logs, temporary
  artifacts, or unrelated formatting churn.
- Inspect only the exact intended payload before each GitHub publication, including the
  outgoing commit range before pushing. Never publish credentials or sensitive personal data;
  a suspected value stops that mutation and is described without printing it. If a credential
  may already be public, stop its spread and require revocation or rotation before considering
  cleanup; deleting it from the latest tree does not remove the exposure.
- If a commit or push fails, report the exact failure without claiming success.
- Close an issue resolved as `completed` only with one signed closing comment on the issue that
  names the resolving commit, what was verified (checks, tests, manual runs), and what was not
  verified. `skd-github-publishing-conventions` owns the format.
- Release flow: bump the version and build number, move `CHANGELOG.md`'s `[Unreleased]` to
  `[X.Y.Z] - date` (and its link reference), build and validate
  from a clean tree, rehearse signing and notarization locally with `scripts/` when needed,
  then tag `vX.Y.Z` → `.github/workflows/release.yml`, which signs, notarizes, publishes, and
  commits the appcast entry. Verify the install and Sparkle update paths and the published
  download surfaces.
- Do not publish a release or change a version unless the task explicitly authorizes it.
- Pass `-R martonpaulo/windowhop` to `gh`; without it the wrong repository can be selected.
