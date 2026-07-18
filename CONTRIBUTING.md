# Contributing to WindowHop

Thanks for helping! WindowHop is a small, focused tool — contributions that keep it
small and focused are the most welcome.

## Build and test

```sh
git clone https://github.com/martonpaulo/windowhop && cd windowhop
swift build            # debug build
swift test             # unit tests (must pass)
scripts/validate.sh    # repository invariants (must pass)
scripts/package-app.sh # assemble build/WindowHop.app
```

Requires macOS 14+ and Xcode 16+ command line tools. No paid Apple account is needed.

## Official releases

Local packaging may use the script's ad-hoc signature. A `vX.Y.Z` tag is an official
release and intentionally fails unless it points at the current `main` commit and the
repository has all of these Actions secrets:

- `DEVELOPER_ID_CERT_P12` — base64-encoded Apple-issued Developer ID Application P12
- `DEVELOPER_ID_CERT_PASSWORD` — that P12's import password
- `NOTARIZATION_APPLE_ID` — Apple Developer account email
- `NOTARIZATION_PASSWORD` — app-specific password for the Apple ID
- `NOTARIZATION_TEAM_ID` — Apple Developer team identifier
- `SPARKLE_PRIVATE_KEY` — EdDSA key used only for the update archive

The tag workflow is push-only, so release secrets are not exposed to pull requests or
fork workflows. It waits for Apple to accept both the app archive and DMG, staples and
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
- Business rules live in `Sources/WindowHopCore/Core/` as pure code **with tests**.
- Every user-facing feature must declare its default and configurability decision. New
  preferences use typed centralized defaults and participate in Restore Defaults; see
  [the defaults contract](docs/feature-defaults.md).
- See [AGENTS.md](AGENTS.md) and [docs/architecture.md](docs/architecture.md) for the
  complete product, layering, and threading rules.

## Pull requests

1. Keep changes focused; unrelated refactors make review slow.
2. `swift test` and `scripts/validate.sh` must pass.
3. Use [Conventional Commits](https://www.conventionalcommits.org) (`feat:`, `fix:`, `docs:`, …).
4. Update documentation when behavior changes.

## Out of scope

Search or type-to-filter, window tiling or layout management, app launching,
themes, telemetry, and anything that requires an
online account. Issues asking for these will be closed with a pointer here.

## License

By contributing you agree your work is licensed under GPL-3.0, the project license.
