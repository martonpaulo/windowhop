# Contributing to WindowHop

Thanks for helping! WindowHop is a small, focused tool — contributions that keep it
small and focused are the most welcome.

## Report a bug

Open an [issue](https://github.com/martonpaulo/windowhop/issues) with your macOS version, the
WindowHop version from Settings → About, whether the switcher is in App Icons or Window Previews
mode, and what you did, expected, and got. For a missing window, say whether it is minimized,
hidden, on another Space, or on another display — those are excluded by default and configurable
under Settings → Windows.

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
scripts/package-app.sh # assemble build/WindowHop.app
```

Requires macOS 26+ and Xcode 26+ command line tools (Swift 6.2; the package builds in the
Swift 6 language mode). No paid Apple account is needed.

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

- **Public Apple APIs only.** No private frameworks or `_`-prefixed SPI.
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
3. `swift test` and `make validate` must pass, with zero warnings.
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
