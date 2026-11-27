# WindowHop — rules for coding agents

## Project identity and policy

- Display name: `WindowHop`
- Code name: `WindowHop`
- Slug: `windowhop`
- Identifier name: `windowhop`
- Icon: `site/apple-touch-icon.png`
- Benefit-first description: Switch between windows, not just apps. Fast, native macOS
  window switcher with large app icons or live previews — free, GPL, no telemetry.
- Repository: `martonpaulo/windowhop` (public)
- Public identifiers: bundle identifier `com.martonpaulo.windowhop` (Decided on [#43](https://github.com/martonpaulo/windowhop/issues/43); the
  previous identifier survives only in `LegacyDomainMigration`); SwiftPM package, executable
  target, and app name `WindowHop`; library targets `WindowHopKit` (pure rules) and
  `WindowHopCore` (Engine, Input, UI, App)
- Landing page: <https://windowhop.martonpaulo.com/> (custom domain in `site/CNAME`),
  published from `site/` by `.github/workflows/deploy.yml`. It lives in this repository;
  there is no separate site repo. `docs/` holds developer documentation and is never published.
- License: `GPL-3.0-only`, with AltTab attribution recorded in `UPSTREAM.md`
- Copyright: © 2026 Marton Paulo. GPL-3.0. Derived from AltTab, © lwouis and contributors
  (`NSHumanReadableCopyright` in `Support/Info.plist` is the canonical string). Settings ›
  About credits the developer only through that copyright line, in its footer, with no
  separate header credit (Decided on [#132](https://github.com/martonpaulo/windowhop/issues/132), superseding the header credit of [#123](https://github.com/martonpaulo/windowhop/issues/123)), and keeps
  the AltTab credit as text, without a link to the AltTab repository (Decided on [#123](https://github.com/martonpaulo/windowhop/issues/123)).
- Development language: English.
- Product copy: English only, in `Support/Localizable.xcstrings`, read through
  `String(localized:)` (SwiftUI literals resolve through the same table). The compiled
  `Support/en.lproj/Localizable.strings` is committed and kept in sync by `make strings`,
  because the canonical `package-app.sh` copies `Support/*.lproj` and compiles no catalog
  ([martonpaulo/skill-deck#333](https://github.com/martonpaulo/skill-deck/issues/333)). Both files are generated from the sources: never edit them
  by hand. There is no second language; adding one is a migration, not an incidental
  change. This supersedes the earlier "authored inline, no localization layer" rule by the
  owner's 2026-09-17 decision in [#39](https://github.com/martonpaulo/windowhop/issues/39) (Decided on [#39](https://github.com/martonpaulo/windowhop/issues/39)).
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
  - Homebrew: the cask `martonpaulo/tap/windowhop` in the public `martonpaulo/homebrew-tap`
    repository (`brew install --cask martonpaulo/tap/windowhop`). `release.yml` bumps its
    version and sha256 when the optional `HOMEBREW_TAP_TOKEN` secret exists; otherwise bump
    them by hand after the release. The cask is `auto_updates`, so Sparkle updates an install
    from an older cask.
  - Update feed: Sparkle, from `appcast.xml` on `raw.githubusercontent.com`, written by
    `release.yml` only after the update ZIP is downloadable. Each item's release notes are
    the site's `/release-notes/X.Y.Z/` page, rendered from `CHANGELOG.md` at deploy time
    (`docs/website.md`, [#128](https://github.com/martonpaulo/windowhop/issues/128)).
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

## Route map

Before editing under a path, read the file its row names. A module with rules of its own keeps them in its own `AGENTS.md` of at most 150 lines, beside a `CLAUDE.md` symlink, and has a row here; this file stays at most 200 lines.

| Path | Read first |
| :--- | :--- |
| any path: build, rules, architecture, interface, docs, tests, Git and releases | `docs/patterns.md` |

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
- References and inspirations: `docs/references.md`, the index of the upstream and reference
  implementations (recorded in `UPSTREAM.md`), design inspirations and technical sources.
  Consult it before diagnosing a hard bug, choosing a module boundary, or deciding a UX
  pattern, and add a row when a new source is consulted.
- Domain glossary: `CONTEXT.md` (optional; create only when a term is genuinely ambiguous
  across `WindowHopKit`, `Engine/`, `Input/`, and `UI/`)
- Architecture decision records: `docs/adr/` (create only when a decision needs its rationale
  recorded; `docs/architecture.md` stays the description of what exists today)
- Handoffs: `.scratch/handoffs/`
- Prototypes: `.scratch/prototypes/` (gitignored, disposable)

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
