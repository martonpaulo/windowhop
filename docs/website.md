# WindowHop website deployment

The static product site lives directly in `docs/` and is served at
<https://martonpaulo.github.io/windowhop/>. It has no backend, package manager, generated
bundle, analytics, or runtime dependency.

## Local preview

```sh
scripts/validate-site.sh
python3 -m http.server 8080 --directory docs
```

Open <http://127.0.0.1:8080/> in both acceptance engine families, **Chromium and WebKit**
(Safari is a WebKit validation target). Verify desktop/mobile widths, keyboard focus, Light
and Dark Mode, and Reduce Motion in each. `scripts/validate.sh` also runs the static-site
validator.

CI currently performs static site validation; it does not run either browser engine.
Use existing browser tooling for interaction and computed-style checks, and record the
browser/version and outcome for each engine. Visual appearance judgment remains human
verification. If an engine is unavailable, report that exact gap rather than treating a
Chromium pass as WebKit evidence. Adding an automated browser matrix or a browser dependency
requires a separate scoped change; do not install tooling merely to record this policy.

Project, release, download, license, issue, and attribution URLs are centralized in
`docs/scripts/main.js`. The version and installer filename must match `Support/Info.plist`.
Final user-facing images come from WindowHop's privacy-safe render harness; annotated
development references never belong in `docs/`.

## GitHub Pages

`.github/workflows/pages.yml` validates and uploads `docs/`, then deploys with GitHub's
official Pages actions whenever website content on `main` changes. The repository Pages
source must be **GitHub Actions**. The workflow uses only read access to repository content
plus the scoped `pages: write` and `id-token: write` permissions required for deployment.

No generated website files require manual editing after deployment. The release checklist
must confirm the public page, direct installer, release notes, source, issue, license, and
AltTab links before tagging a release.
