# WindowHop — rules for coding agents

## Project identity and policy

- Project name: `WindowHop`
- Public name: `WindowHop`
- Benefit-first description: Switch between windows, not just apps. Fast, native macOS
  window switcher with large app icons or live previews — free, GPL, no telemetry.
- Repository: `martonpaulo/windowhop` (public)
- Public identifiers: bundle identifier `com.perso.windowhop`; SwiftPM package, executable
  target, and app name `WindowHop`; library target `WindowHopCore`
- Landing page: <https://martonpaulo.github.io/windowhop/>, published from `docs/` by
  `.github/workflows/pages.yml`. It lives in this repository; there is no separate site repo.
- License: `GPL-3.0-only`, with AltTab attribution recorded in `UPSTREAM.md`
- Copyright: GPL-3.0. Derived from AltTab, © lwouis and contributors
  (`NSHumanReadableCopyright` in `Support/Info.plist` is the canonical string).
- Development language: English.
- Product copy: English only, authored inline. There is no localization layer, no `.lproj`
  bundle, and no fallback locale; adding one is a migration, not an incidental change.
- Browser engine families: Chromium and WebKit for the website. `docs/website.md` owns
  the validation procedure and the distinction between static CI and browser checks.
- Agent automation: `disabled`. Implementation and review run only when requested;
  do not install an automated issue-intake or execution integration.
- Agent guidance: `AGENTS.md` is canonical; Codex reads it directly and
  `CLAUDE.md -> AGENTS.md` is the Claude adapter. Gemini and Antigravity require explicit
  client selection and functional readback before configuration. The legacy
  `.gemini/rules/agents.md` link is retained, not treated as verified active guidance.
- Branch policy: work directly on `main`. Use a branch and pull request only when the user
  asks for one; bot PRs (Dependabot, ImgBot) still merge through GitHub.
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
- Secret protection: GitHub secret scanning and push protection enabled. These are
  backstops, not substitutes for inspecting the exact publication payload.
- Release, signing, and secret-storage policy: distributed as a signed, notarized, stapled
  `.app` in a DMG plus ZIP on GitHub Releases, updated in place by Sparkle from
  `appcast.xml` on `raw.githubusercontent.com`. Tag `vX.Y.Z` triggers
  `.github/workflows/release.yml`; local equivalents live in `scripts/`. Signing uses one
  stable identity from the `DEVELOPER_ID_CERT_P12` / `DEVELOPER_ID_CERT_PASSWORD` GitHub
  secrets; the Sparkle EdDSA private key lives in the login Keychain and the
  `SPARKLE_PRIVATE_KEY` secret. No key material, certificate password, or signing log ever
  enters the repository.
- Skills baseline revision: `7cfc324fcded57145c36cc678977c070ed800692`
- Skills baseline applied: `2026-09-08`

Treat these values as stable project decisions. Change an established identifier, license,
visibility, branch policy, versioning model, localization strategy, landing-page contract, or
release policy only through an explicit task that describes the migration and downstream
effects.

## Build and validate

```sh
swift build && swift test        # must pass, zero warnings
scripts/validate.sh              # repository invariants (must pass)
scripts/capture-screenshots.sh   # published screenshots (Retina display required)
scripts/package-app.sh [ver] [build]  # release .app with Sparkle embedded + zip
scripts/make-dmg.sh [ver]        # DMG (expects build/WindowHop.app)
```

Runtime checks (Accessibility permission is inherited when run from a trusted terminal):

```sh
.build/debug/WindowHop --dump-windows           # real discovery works?
.build/debug/WindowHop --dump-previews          # entry → captured window pairing (no image)
.build/debug/WindowHop --render-ui /tmp/shots   # switcher + settings renders, light/dark/overflow
.build/debug/WindowHop --demo-switcher [--dark] [--many]  # on-screen panel demo
.build/debug/WindowHop --updater-e2e <feed-url> # headless Sparkle end-to-end (see docs/testing.md)
WINDOWHOP_DEBUG=1 .build/debug/WindowHop        # diagnose input/session behavior
```

Keep task logs in `artifacts/` (gitignored). Inspect a failed log before rerunning.

## Hard rules

- **Public Apple APIs only.** No private frameworks, no `_`-prefixed SPI, no
  `@_silgen_name`. AX attribute *strings* not in headers (e.g. `AXFullScreen`) are fine.
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
- The bundle identifier is `com.perso.windowhop` — everywhere, always.
- Closing a window always goes through the confirmation dialog (Cancel is default);
  Quit is graceful termination only; Force Quit requires its own second confirmation.
- **Appearance is fixed**: icon size is Large, the only appearance options are App Icons
  (default) and Window Previews, and theming is system Light/Dark only. No themes, no
  custom sizes, no layout or opacity options. This rule governs how the panel *looks*.
  Where the panel is drawn is display behavior, not appearance, and lives with the other
  display settings in Settings → Windows (see `Core/PanelPlacement.swift`).
- All shortcut strings render through `Core/ShortcutFormatter` — never hardcode a
  second representation of the same key.
- All UI dimensions come from `UI/DesignTokens.swift` — no hardcoded sizes,
  insets, radii, or font sizes in views.
- Official releases are signed with one stable Apple-issued Developer ID Application
  identity (`DEVELOPER_ID_CERT_P12`), notarized and stapled, so the TCC Accessibility
  grant survives updates — never ship ad-hoc, self-signed, or unnotarized releases.

## Architecture (see docs/architecture.md)

- `Core/` — pure logic, no AppKit/AX imports beyond value types. All business rules live
  here (eligibility, MRU, title fallback, tab-group resolution, PiP detection,
  preview-result ledger, session state machine, shortcut model, settings defaults).
  New behavior rules go here **with unit tests**.
- `Engine/` — AX integration: `TrackedApp`/`TrackedWindow`, `WindowStore` (main-thread
  source of truth), `AXNotificationRouter` (AX thread → reads queue → main).
- `Input/` — `EventTap` (tap thread; modes off/watching/sessionHeld/sessionSticky/
  passthrough) and `SwitcherController` (main-thread orchestration).
- `UI/` — AppKit switcher panel (horizontal large-icon tiles, pooled); SwiftUI
  Settings/onboarding; native shortcut recorder.
- `App/` — lifecycle and `UpdateManager` (Sparkle; only starts from a real bundle).

Threading: AX reads/actions on `BackgroundWork` queues, never the main thread; state
mutation and UI on main only.

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
- Store defaults in `Core/Preferences.Defaults`. Do not duplicate fallback values in
  views, services, tests, shortcut registration, or migration code.
- Persist configurable preferences through the existing typed `Preferences.Key`
  infrastructure and keep `Preferences` as the runtime source of truth.
- Preserve existing user choices during upgrades; migration may change a stored value
  only when the old representation is obsolete or invalid.
- Add every configurable preference to `Preferences.configurableKeys` so Restore Defaults
  picks it up. Reset must not change permissions, identity, build metadata, caches, or
  non-preference user data.
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
  project that means `Core/`, not `UI/`, `Engine/`, or `Input/`.
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
- Define layout, hierarchy, controls, loading, content, empty, error, retry, disabled,
  cancellation, and destructive states when applicable.
- Include keyboard navigation, focus, screen-reader labels, scalable text, contrast, reduced
  motion, and non-color status cues in the same change.
- Keep visible copy centralized and consistent with the English-only copy strategy.
- Keep expensive work out of render paths and latency-sensitive paths. Prefer event-driven,
  on-demand, bounded, incremental, and cancelable work.
- Measure before claiming a performance problem, and optimize measured user-visible
  bottlenecks.
- Published screenshots come from `scripts/capture-screenshots.sh` and must never show the
  user's personal windows. It drives `--demo-switcher` / `--demo-settings` on screen and
  captures each window with `screencapture -l<windowid>`, which is what gives the published
  images their rounded corners, real glass material, drop shadow, and elevation. Run it on a
  Retina display: the capture is taken at the display's backing scale, so a 1x screen halves
  the resolution. `--render-ui` stays the offscreen layout/regression harness — it has no
  shadow and no rounded corners, so it is not a source of published images.

## Code, comments, and documentation

- Conventional Commits; English in code, comments, commits, filenames, tests, configuration,
  and developer documentation.
- Follow the existing formatter, naming, file layout, and architectural conventions.
- Prefer clear types, explicit ownership, and simple control flow over cleverness.
- Comments state constraints the code can't show (ported-rule provenance, macOS quirks). Link
  official documentation when an external rule or workaround must stay visible to prevent a
  regression.
- GPL-3.0 with AltTab attribution is non-negotiable; update `UPSTREAM.md` when porting
  upstream rules (include the upstream commit hash). Never remove upstream notices.
- Update the smallest canonical documentation section when a durable contract changes. Do not
  create empty documentation for possible future use.
- Keep the README easy to scan: benefit, behavior, requirements, install, usage, validation,
  privacy, limitations, landing page, download. Use badges, real screenshots, and statistics
  only when they improve comprehension and can stay current.
- Maintain `CHANGELOG.md` — every public release gets a user-facing entry.
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
- The project has no runtime environment variables, so there is no `.env.example`. Add one
  only if real variables appear, with every supported name and a safe placeholder.
- Keep secrets in the GitHub secret store or the login Keychain, never in versioned files.

## Tests and validation

- Add or update focused tests for changed behavior, regressions, persistence, migrations,
  validation, and critical accessibility. Business rules in `Core/` ship with unit tests.
- Test observable contracts at stable seams; avoid tests that only mirror implementation
  details or framework behavior.
- Run the smallest relevant check during iteration. Inspect the first useful failure and make a
  relevant change before rerunning.
- Once stable, run `swift build && swift test` plus `scripts/validate.sh` — both must pass with
  zero warnings before a commit.
- Never claim a check passed unless it ran successfully. Report exact skips, blockers, residual
  risk, and manual gaps.

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
  across `Core/`, `Engine/`, `Input/`, and `UI/`)
- Architecture decision records: `docs/adr/` (create only when a decision needs its rationale
  recorded; `docs/architecture.md` stays the description of what exists today)
- Prototypes: `artifacts/prototypes/` (gitignored, disposable)

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
- Release flow: bump the version and build number, update `CHANGELOG.md`, build and validate
  from a clean tree, sign and notarize, verify the install and Sparkle update paths, then tag
  `vX.Y.Z` → `.github/workflows/release.yml` (or the local `scripts/`), commit the appcast
  entry, and verify the published download surfaces.
- Do not publish a release or change a version unless the task explicitly authorizes it.
- Pass `-R martonpaulo/windowhop` to `gh`; without it the wrong repository can be selected.

## Completion report

Lead with the outcome and include:

- what changed and why;
- files touched;
- validation commands and actual results;
- warnings, failures, skips, manual gaps, and remaining risks;
- temporary artifacts kept or removed;
- commit and push status;
- final worktree status and unrelated dirty files left untouched.
