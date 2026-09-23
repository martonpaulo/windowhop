# Contributing to WindowHop

Thanks for helping! WindowHop is a small, focused tool — contributions that keep it
small and focused are the most welcome.

## Report a bug

Open an [issue](https://github.com/martonpaulo/windowhop/issues) with your macOS version, the
WindowHop version from Settings → About, whether the switcher is in App Icons or Window Previews
mode, and what you did, expected, and got. For a missing window, say whether it is minimized,
hidden, on another Space, or on another display — those are excluded by default and configurable
under Settings → Switcher.

`log stream --level debug --process WindowHop`, run while you reproduce the problem, shows input and session
behavior, which is the most useful attachment for a switching or shortcut bug. Report a vulnerability through the private channel in
[SECURITY.md](SECURITY.md) rather than a public issue, and never paste certificate, notarization, or
Sparkle key material anywhere.

## Build and test

```sh
git clone https://github.com/martonpaulo/windowhop && cd windowhop
swift build            # debug build
swift test             # unit tests (must pass)
make validate          # repository invariants (must pass)
make format            # format Sources/ and Tests/ with swift-format before committing
make check             # build, lint, test and validate: run it before committing
scripts/package-app.sh # assemble build/WindowHop.app
```

Requires macOS 26+ and Xcode 26+ command line tools (Swift 6.2; the package builds in the
Swift 6 language mode). No paid Apple account is needed.

## Commands

| Command | What it does |
| --- | --- |
| `swift test` | Run the unit suite, which must pass with zero warnings |
| `make check` | Build, lint, test and validate: the gate before a commit, and what CI runs |
| `make lint` | SwiftLint and swift-format lint with the shared `.swiftlint.yml` and `.swift-format`; any finding fails |
| `make format` | Rewrite `Sources/` and `Tests/` with swift-format |
| `make validate` | Check the repository invariants (runs `scripts/validate.sh`): layering, ScreenCaptureKit confinement, docs, site |
| `make strings` | Regenerate the English String Catalog (`Support/Localizable.xcstrings`) and its compiled `Support/en.lproj` after a copy change; `make strings-check` fails when they are out of date |
| `make help` | List every target (the default goal) |
| `make build` | Build the debug binary; `CONFIGURATION=release` for the release build |
| `make app [FORCE=1]` | Assemble `build/WindowHop.app` with Sparkle embedded, plus its zip, through `scripts/package-app.sh` (`--help` lists every option, such as `--version X.Y.Z --build-number N`) |
| `make dmg [FORCE=1]` | `make app`, then the branded DMG from `build/WindowHop.app` through `scripts/make-dmg.sh` |
| `make icon` | Regenerate the committed art: app icon, favicons, installer icon and DMG background |
| `make screenshots` | Capture the published screenshots, at 2x, which needs Screen Recording permission (a 1x Mac gets a temporary 2x display) |
| `make keys` | One-time: make sure the login Keychain holds the Sparkle key and `SUPublicEDKey` matches it |
| `make appcast VERSION=… BUILD_NUMBER=… ARCHIVE=… SIGNATURE=…` | Add one release entry to `appcast.xml` for Sparkle (a rehearsal or a recovery; the release workflow does it) |
| `make clean` | Remove `.build`, `build` and `artifacts` |
| `scripts/sign-update.sh --archive <zip>` | Sign an update archive with the resolved Sparkle `sign_update` and print its appcast attributes |
| `scripts/validate-site.sh` | Check the site's host, canonical URL, `robots.txt` and sitemap (skill-deck's canonical copy; `make validate` adds WindowHop's own site checks) |
| `scripts/social-card.sh` | Render `design/social-card/social-card.html` to `site/social-card.jpg` (needs Node and ImageMagick) |
| `scripts/verify-release-identity.sh [--app <App.app>]` | Check the signed app against the recorded release identity |
| `scripts/verify-dmg-branding.sh --dmg <path.dmg>` | Check the DMG branding release gate |
| `scripts/verify-update-continuity.sh` | Check the Sparkle update-continuity release gate |
| `scripts/publish-release.sh --tag … --notes-file … --artifact …` | Run the publication step the tag workflow performs |

The debug binary's runtime check flags are documented in [`docs/testing.md`](docs/testing.md).

## Secrets and variables

The app itself reads none of these: every secret below belongs to the release pipeline (`.github/workflows/release.yml`), which runs only on a `vX.Y.Z` tag, pushed or dispatched by hand by someone with write access, and so is never exposed to pull requests or fork workflows.

| Name | Where | What for |
| --- | --- | --- |
| `DEVELOPER_ID_CERT_P12` | Actions secret, `release.yml` | Required for a release. Base64 of the Apple-issued Developer ID Application certificate |
| `DEVELOPER_ID_CERT_PASSWORD` | Actions secret, `release.yml` | Required for a release. The import password for that P12 |
| `NOTARY_API_KEY` | Actions secret, `release.yml` | Required for a release. The team App Store Connect API key (`.p8`, Developer role) used by `scripts/notarize.sh` |
| `NOTARY_API_KEY_ID` | Actions secret, `release.yml` | Required for a release. That key's Key ID |
| `NOTARY_API_ISSUER_ID` | Actions secret, `release.yml` | Required for a release. The App Store Connect Issuer ID |
| `NOTARY_PROFILE` | Local shell, `scripts/notarize.sh` | Optional. The Keychain profile for a local rehearsal; defaults to `skd-notary` |
| `SPARKLE_PRIVATE_KEY` | Actions secret, `release.yml`, mirroring the login Keychain | Required for a release. The EdDSA key that signs the update archive |
| `DEVELOPER_ID_IDENTITY` | Local shell, `scripts/package-app.sh` | Optional. Names the approved Developer ID identity; without it, packaging is ad-hoc signed |

## Official releases

Local packaging may use the script's ad-hoc signature. A `vX.Y.Z` tag is an official
release and intentionally fails unless it points at the current `main` commit and the
repository has all of these Actions secrets:

- `DEVELOPER_ID_CERT_P12` — base64-encoded Apple-issued Developer ID Application P12
- `DEVELOPER_ID_CERT_PASSWORD` — that P12's import password
- `NOTARY_API_KEY` — contents of the team App Store Connect API key (`.p8`, Developer role)
- `NOTARY_API_KEY_ID` — that key's Key ID
- `NOTARY_API_ISSUER_ID` — the App Store Connect Issuer ID
- `SPARKLE_PRIVATE_KEY` — EdDSA key used only for the update archive

The release workflow runs only on a `vX.Y.Z` tag, pushed or dispatched by hand, so release
secrets are not exposed to pull requests or fork workflows. `scripts/notarize.sh` submits each artifact; on a Mac the same script uses
the `skd-notary` Keychain profile, so a local rehearsal runs the release code. It waits for Apple to accept both the app archive and DMG, staples and
validates both tickets, and runs Gatekeeper checks before publishing. Never tag a release
to test credentials; use the local packaging commands and Apple tooling directly.

## Ground rules

- **Public Apple APIs only.** No private frameworks or `_`-prefixed SPI. The one recorded
  exception is local screenshot tooling, `scripts/capture-display.m`, which is never built into the app.
- **Screen Recording stays opt-in.** ScreenCaptureKit is confined to
  `Engine/PreviewProvider.swift`, runs only during an open Window Previews session,
  and never persists snapshots. App Icons must work without permission.
- **No polling while idle** — observe events. Bounded timers only during a session
  or while the onboarding window is open.
- **One entry per top-level window.** Tabs are never separate entries.
- **No new dependencies.** Sparkle (updates) is the single approved runtime dependency.
- Business rules live in `Sources/WindowHopKit/` as pure code **with tests** in `Tests/WindowHopKitTests/`.
- Every user-facing feature must declare its default and configurability decision. New
  preferences use typed centralized defaults and participate in Restore Defaults; see
  [the defaults contract](docs/feature-defaults.md).
- See [AGENTS.md](AGENTS.md) and [docs/architecture.md](docs/architecture.md) for the
  complete product, layering, and threading rules.

## Branches, commits and pull requests

1. The owner commits validated work directly to `main`; outside contributors work on a branch and
   open a pull request.
2. Keep changes focused; unrelated refactors make review slow.
3. Run `make format`, then `make check`: the build, SwiftLint and swift-format lint, the tests and
   `make validate` must pass, with zero warnings. Install SwiftLint with `brew install swiftlint`;
   swift-format comes with Xcode.
4. Use [Conventional Commits](https://www.conventionalcommits.org) (`feat:`, `fix:`, `docs:`, …),
   one concern per commit, and end a commit made for an issue with `(#<issue number>)`.
5. Update documentation when behavior changes, and never bump the version or edit `appcast.xml` as
   part of an ordinary change — releases are their own deliberate step.

Be respectful and assume good faith: behaviour that makes the project unpleasant for others is not
welcome, whatever its technical merit.

## Out of scope

Search or type-to-filter, window tiling or layout management, app launching,
themes, telemetry, and anything that requires an
online account. Issues asking for these will be closed with a pointer here.

## License

By contributing you agree your work is licensed under GPL-3.0, the project license.
