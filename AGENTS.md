# WindowHop — rules for coding agents

## Project identity and policy

- Display name: `WindowHop`
- Code name: `WindowHop`
- Slug: `windowhop`
- Identifier name: `windowhop`
- Benefit-first description: Switch between windows, not just apps. Fast, native macOS
  window switcher with large app icons or live previews — free, GPL, no telemetry.
- Repository: `martonpaulo/windowhop` (public)
- Public identifiers: bundle identifier `com.martonpaulo.windowhop` (Decided on #43; the
  previous identifier survives only in `LegacyDomainMigration`); SwiftPM package, executable
  target, and app name `WindowHop`; library targets `WindowHopKit` (pure rules) and
  `WindowHopCore` (Engine, Input, UI, App)
- Landing page: <https://windowhop.martonpaulo.com/> (custom domain in `site/CNAME`),
  published from `site/` by `.github/workflows/deploy.yml`. It lives in this repository;
  there is no separate site repo. `docs/` holds developer documentation and is never published.
- License: `GPL-3.0-only`, with AltTab attribution recorded in `UPSTREAM.md`
- Copyright: © 2026 Marton Paulo. GPL-3.0. Derived from AltTab, © lwouis and contributors
  (`NSHumanReadableCopyright` in `Support/Info.plist` is the canonical string). Settings ›
  About credits the developer ("Made by Marton Paulo") and keeps the AltTab credit as
  text, without a link to the AltTab repository (Decided on #123).
- Development language: English.
- Product copy: English only, in `Support/Localizable.xcstrings`, read through
  `String(localized:)` (SwiftUI literals resolve through the same table). The compiled
  `Support/en.lproj/Localizable.strings` is committed and kept in sync by `make strings`,
  because the canonical `package-app.sh` copies `Support/*.lproj` and compiles no catalog
  (martonpaulo/skill-deck#333). Both files are generated from the sources: never edit them
  by hand. There is no second language; adding one is a migration, not an incidental
  change. This supersedes the earlier "authored inline, no localization layer" rule by the
  owner's 2026-09-17 decision in #39 (Decided on #39).
- Browser engine families: Chromium and WebKit for the website. `docs/website.md` owns
  the validation procedure and the distinction between static CI and browser checks.
- Agent guidance: two entrypoints. `AGENTS.md` is the one real file, which Codex reads
  directly; `CLAUDE.md` is a symlink to it for Claude. Do not create `GEMINI.md`,
  `.gemini/rules/agents.md`, or any other alias, and never commit `.claude/settings.local.json`.
- Branch policy: work directly on `main`. Use a branch and pull request only when the user
  asks for one; Dependabot PRs still merge through GitHub.
- Commit policy: automatic. When a task is complete and its validation has passed, commit it
  without being asked — Conventional Commits, one commit per concern, diff inspected first.
  Do not commit a task that is unfinished, unvalidated, or failing.
- Push policy: automatic. Push to `origin/main` right after creating those commits. `main`
  drives CI and the Pages deploy, so never push a red or unvalidated tree, and never
  force-push.
- Product versioning: SemVer `MAJOR.MINOR.PATCH`. The canonical source is
  `CFBundleShortVersionString` in `Support/Info.plist`; `CFBundleVersion` is derived as
  `MAJOR*10000 + MINOR*100 + PATCH`. Version increments are **not** automatic: they happen
  only during an explicitly requested release, together with the `CHANGELOG.md` entry, the
  `vX.Y.Z` tag, the appcast entry, and the published artifacts. Finishing a feature never
  bumps a version.
- Merge policy: merge commits only, every commit of the branch preserved. Never squash.
- Commit subject: a commit made for an issue ends with `(#<issue number>)`.
- Delete branches after merge: enabled on GitHub.
- Default-branch approving review: not required under the direct-to-`main` policy.
  Do not add a pull-request-only protection rule without reopening that policy.
- Default-branch required status check: none. `main` has no branch protection and no
  ruleset, because commits land on it directly; the gate is running `make check` (build,
  lint, test, validate, strings-check) before each push, and `Validate` on `main` right after it.
- Secret protection: GitHub secret scanning and push protection enabled. These are
  backstops, not substitutes for inspecting the exact publication payload.
- Release, signing, and secret-storage policy: direct download, outside the Mac App Store.
  No field below is secret.
  - Channel and artifacts: GitHub Releases. Each release publishes
    `WindowHop-<version>.dmg` (canonical; the landing page links it),
    `WindowHop-<version>-Installer.zip` (the DMG with its Finder icon preserved), and
    `WindowHop-<version>.zip` (Sparkle's signed update archive).
  - Signing identity: `Developer ID Application: Marton Paulo (TBN79KU9ML)`, one stable
    identity, checked against `Support/ReleaseCertificate.cer`.
  - Team ID: `TBN79KU9ML`.
  - Bundle identifier: `com.martonpaulo.windowhop`; the embedded Sparkle bundles are verified
    to be signed by the same team.
  - Build and package command: `scripts/package-app.sh` (the `.app` and the update ZIP), then
    `scripts/make-dmg.sh`; `scripts/verify-release-identity.sh` checks the result.
  - Entitlements and hardened runtime: no entitlements file (the stable empty set); hardened
    runtime on for every Developer ID signature.
  - Keychain profile: `skd-notary`, for local rehearsals only; CI notarizes with the team API
    key from the `NOTARY_API_KEY*` secrets.
  - Release workflow: `.github/workflows/release.yml`, run by a `vX.Y.Z` tag on the current
    `main` commit, pushed or dispatched by hand on that tag. It is the only thing that
    publishes; the local `scripts/` rehearse and diagnose, and never publish a release.
  - Update feed: Sparkle, from `appcast.xml` on `raw.githubusercontent.com`, written by
    `release.yml` only after the update ZIP is downloadable. Each item's release notes are
    the site's `/release-notes/X.Y.Z/` page, rendered from `CHANGELOG.md` at deploy time
    (`docs/website.md`, #128).
  - Publishing authority: the owner, by pushing the tag; only artifacts that passed
    verification in that run are published.
  - Secrets: `DEVELOPER_ID_CERT_P12`, `DEVELOPER_ID_CERT_PASSWORD`, `NOTARY_API_KEY`,
    `NOTARY_API_KEY_ID`, `NOTARY_API_ISSUER_ID`, and `SPARKLE_PRIVATE_KEY` in the GitHub
    secret store; the Sparkle EdDSA private key also lives in the login Keychain. No key
    material, certificate password, or signing log ever enters the repository.
- Skills baseline revision: `3845d858ebbf3af6e270816462bf3182206c40d9`
- Skills baseline applied: `2026-09-23`

Treat these values as stable project decisions. Change an established identifier, license,
visibility, branch policy, versioning model, localization strategy, landing-page contract, or
release policy only through an explicit task that describes the migration and downstream
effects.

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
  `CGVirtualDisplay` class to create a temporary 2x display (Decided on #116). AX attribute *strings* not in headers (e.g. `AXFullScreen`) are fine.
  For the same reason, so are the undeclared `com.apple.screenIsLocked` /
  `com.apple.screenIsUnlocked` names observed through the public
  `DistributedNotificationCenter` (`Engine/SessionMonitor.swift`); if they stop firing,
  behavior falls back to not knowing the lock state (Decided on #38).
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
  this), which copies its settings domain once (#43).
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
  `Tests/WindowHopKitTests/`, which depends only on the Kit.
  - **Kit import contract** (`scripts/validate.sh` enforces it): `Foundation`;
    `CoreGraphics` for value types only (`CGEventFlags`, `CGRect`, `CGWindowID`);
    `Observation` (the `@Observable` `Preferences`, #101); and `Synchronization`
    (a standard-library module, used by `ShortcutFormatter`'s `Mutex`). No AppKit, AX,
    `NSWorkspace`, ScreenCaptureKit or Sparkle. This diverges from the shared
    "a Kit imports only Foundation" rule, because the issue's "no AppKit, AX or Sparkle
    imports beyond value types" already admits CoreGraphics value types; wrapping
    `CGEventFlags` and `CGRect` in Kit-owned types was rejected as churn with no safety
    gain (#100).
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

## Instruction hierarchy and sources of truth

- Follow the direct task, the most specific applicable scoped instructions, this root file,
  and then general working agreements, in that order.
- Read applicable instructions before changing files.
- Code is evidence of current behavior. This file is normative for process. An approved
  specification is normative for desired behavior. Expose divergence among them; do not
  silently resolve every conflict in favor of one source.
- When two sources disagree — issues, comments, edits, this file, the agent's own memory, or
  the owner's current instruction — a newer trusted statement is the recommended side, never
  the decided one. Ask the owner about every divergence before acting on either side, and
  record the answer in the newer issue. The `skd-agent-context-validation` skill owns the
  precedence order and the ranking.
- Keep one canonical source for each rule. `docs/architecture.md`, `docs/testing.md`,
  `docs/feature-defaults.md`, and `docs/website.md` own their details; this file links to
  them instead of restating them.
- Do not turn analysis, research, or a read-only audit into implementation without
  authorization.
- Be direct and evidence-based. State assumptions, uncertainty, risks, tradeoffs, and
  blockers. Ask only when a material decision cannot be discovered safely.
- Give concise progress updates during long-running work.

## Long-running operations

- Use bounded yield, timeout, or status mechanisms and observable completion conditions.
  Keep progress commentary at least once per minute when the client supports it.
- Distinguish slow progress from a stall using output, state, resource activity, or a
  task-specific deadline; elapsed time alone is not evidence of a stall.
- Inspect current output before interruption or retry. Interrupt only when useful progress
  has stopped, a deadline expired, or continued cost or risk is no longer justified.
- After interruption, explain the preserved state and choose a narrower retry, a different
  approach, or an explicit blocker. Never repeat the same unchanged failure.
- Do not add polling services or infrastructure merely to monitor an operation.

## Before editing

1. Check applicable instructions, Git status, and the current branch. The user works on this
   machine between sessions, so re-verify Git state rather than assuming the last known one.
2. Search for the behavior, callers, tests, contracts, and nearby patterns before adding
   anything.
3. **Check the upstream before planning an issue.** AltTab solved most of these problems
   first, and its full history lives in this repository — read it directly with
   `git show 317a485b:src/...`, no network needed. It routinely contains a macOS quirk that
   is not in Apple's documentation. `UPSTREAM.md` owns the procedure and what to record.
4. Read only the files and chunks required to understand the affected behavior.
5. Distinguish verified facts, reasonable inferences, and unknowns.
6. Define the source of truth and ownership before changing data or state.
7. Make a short plan only for complex, risky, ambiguous, or multi-file work.

## Scope, reuse, and implementation

- Keep changes scoped to the requested result. Do not mix unrelated cleanup, redesign,
  dependency updates, broad refactors, or future work.
- Preserve behavior outside the task and preserve unrelated or uncommitted user changes.
- Search for existing components, services, types, helpers, tokens, configuration, tests, and
  platform capabilities before creating new ones.
- Follow the patterns this project already repeats — the layer boundaries above, `DesignTokens`,
  `ShortcutFormatter`, `Preferences.Defaults`, the pooled-tile panel, the `SwitcherState` machine.
  When a change would break one of them or establish a new pattern, stop and ask first, naming the
  existing pattern, the proposed one, and why the existing one does not fit. Deviating is allowed;
  deviating silently is not.
- Prefer the smallest correct, readable, reversible, and low-operational-cost solution.
- Maintain one owner and one source of truth for each business rule, state, mapping, default,
  and copy value.
- Keep business rules out of presentation, transport, CLI, and adapter layers — in this
  project that means `WindowHopKit`, not `UI/`, `Engine/`, or `Input/`.
- Derive values instead of storing synchronized copies. Model invalid states explicitly.
- Do not add dependencies, services, layers, caches, observers, timers, polling, or
  background jobs without a current requirement and a clear owner. See the idle-polling and
  single-dependency hard rules above.
- For large changes, use reviewable, executable increments. Do not fragment one coherent
  concern mechanically.
- Implement relevant errors, states, accessibility, and tests with the behavior rather than as
  unrelated follow-up work.

## Data, security, and destructive operations

- Distinguish canonical data, reconstructible cache, transient state, local preferences,
  durable intent, and operating-system artifacts. Window snapshots are cache and must never
  be persisted; `Preferences` is the only durable user state.
- Use stable application-owned identifiers. Validate data at input and persistence boundaries.
- Use atomic writes when partial failure could leave inconsistent state. Preserve unrelated
  fields during external updates.
- Request only necessary permissions and scopes. Keep credentials, tokens, private keys,
  signing material, and personal data out of the repository and logs.
- Use structured subprocess arguments and validate destinations, redirects, and untrusted
  inputs.
- Resolve an exact target before deletion, overwrite, interruption, or another hard-to-recover
  action. Ask again when the target is ambiguous or effects exceed the named scope.
- Never force-push and never perform broad cleanup without explicit authorization.
- The user may be running WindowHop from `/Applications` during a session. Check before
  killing a `WindowHop` process and leave pre-existing ones alone.

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

## Durable project learning

At completion, compare verified, project-specific, recurring lessons with their existing
canonical owner. Do nothing when already recorded. Required task documentation belongs in
the task; adjacent learning is proposal-only until explicitly approved.

An adjacent proposal names `Evidence`, `Canonical owner`, `Smallest change`, `Draft`, and
`Decision requested: Approve, reject, or revise.` Do not create another file when an existing
section or script can own it. Do not persist hypotheses, raw logs, personal data, transient
machine state, or issue-specific implementation details as general guidance. Behavior-changing
scripts or configuration require their own authorized scope.

## Output shape

Shape every message to the user so it can be acted on at once, including by a reader with ADHD.
Adapted from [ayghri/i-have-adhd](https://github.com/ayghri/i-have-adhd) (MIT, Ayoub Ghriss).

1. **Lead with the next action.** When the answer is a command, path or snippet, it comes first;
   prose follows, if at all.
2. **Number multi-step work.** One bounded action per step, and the fewest steps that still work.
3. **End with one concrete next action** the reader can do in under two minutes, when anything is
   left open.
4. **Suppress tangents.** Finish the first thing, then offer the second as a separate question.
5. **Restate the state every turn**: "Step 3 of 5 done: schema updated. Next: backfill." When the
   client has a task or plan tool, the checklist does the restating.
6. **Give time estimates in concrete units**, never "some work".
7. **Make completed work visible** in concrete terms: what now works and how to see it.
8. **State errors plainly**: the cause, then the fix.
9. **Keep lists short.** Group related items and rank the most relevant first, with at most five
   visible per group. Never drop a relevant item: this shapes presentation, not analysis.
10. **No preamble, no recap, no closing pleasantries.**

The shape gives way when:

- the user asks to explain or walk through something: explain fully, still without preamble;
- a destructive action is ahead: confirm first;
- repeated attempts keep failing: name the assumption that may be wrong and ask one diagnostic
  question;
- the request is really ambiguous: ask one short question;
- the user asks for options: give two to four, ranked, recommendation first;
- a required format applies: an attention card below, an execution plan, a completion report, or
  a machine-read output keeps its structure, and the shape applies to the prose around it.

## User attention

Use the client's structured-question facility when a response is required, together with one
concise attention card in the user's language. Surround the card with horizontal rules; name
the category (decision, approval, external action, or proposed issue), the evidence and impact,
the exact requested response, and a recommendation. A choice includes meaningful tradeoffs;
an approval names its target, change, reversibility, and recovery; an external action states
the observable condition for resuming. Without a question tool, use the card alone.

Keep unrelated work moving while a question is pending. A proposed follow-up is not permission
to publish an issue or change code. Do not ask again for a decision already recorded here.

## Configuration and repository hygiene

- Keep `.gitignore` covering secrets, local environments, logs, caches, build output, and
  generated artifacts that actually exist.
- The app has no runtime environment variables, so there is no `.env.example`. Diagnostics
  go to the unified log (`App/Log.swift`), and the release-script variables are shell inputs;
  the secrets and variables table in `CONTRIBUTING.md` lists them. Add an
  `.env.example` only if real configuration variables appear, with every supported name and a
  safe placeholder.
- Keep secrets in the GitHub secret store or the login Keychain, never in versioned files.

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

## Artifacts and processes

- Temporary is the default; retention is an explicit exception. Task logs belong in
  `artifacts/` (gitignored).
- Remove only temporary files created by the current task. Preserve deliverables, next-phase
  inputs, and failure evidence.
- Never delete pre-existing user artifacts, fixtures, baselines, or logs merely because they
  look temporary.
- Stop demo panels, servers, watchers, and other processes started by the task. Do not stop the
  user's pre-existing processes.

## Agent skill paths

- Product definition: `docs/product.md` — what WindowHop is for and what it will never do. A
  proposal that contradicts a non-goal there loses until that document changes.
- Domain glossary: `CONTEXT.md` (optional; create only when a term is genuinely ambiguous
  across `WindowHopKit`, `Engine/`, `Input/`, and `UI/`)
- Architecture decision records: `docs/adr/` (create only when a decision needs its rationale
  recorded; `docs/architecture.md` stays the description of what exists today)
- Handoffs: `.scratch/handoffs/`
- Prototypes: `.scratch/prototypes/` (gitignored, disposable)

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

## Completion report

Lead with the outcome, in the output shape above, and include:

- what changed and why;
- files touched;
- validation commands and actual results;
- warnings, failures, skips, manual gaps, and remaining risks;
- what was verified by running the application, and what remains unverified;
- each issue closed, with the resolving commit its closing comment names;
- temporary artifacts kept or removed;
- commit, branch, and push status;
- final worktree status and unrelated dirty files left untouched.
