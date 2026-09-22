# WindowHop website deployment

The static product site lives directly in `site/` and is served at
<https://windowhop.martonpaulo.com/>. It has no backend, package manager, generated
bundle, analytics, or runtime dependency.

## Local preview

```sh
scripts/validate-site.sh
python3 -m http.server 8080 --directory site
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

Project, release, download, license, issue, and attribution URLs and the displayed version
live in the HTML (`site/index.html`, `site/404.html`), so every link works without
JavaScript; `site/scripts/main.js` only keeps the copyright year current over a static
fallback. `scripts/validate-site.sh` fails on any `href="#"` and whenever the download URL,
release-notes tag, or version text does not match `Support/Info.plist`, so a version bump
must update the HTML.
Final user-facing images come from WindowHop's privacy-safe render harness; annotated
development references never belong in `site/`. `docs/` holds developer documentation
and is never published.

## GitHub Pages

`.github/workflows/deploy.yml` waits for Validate to pass on `main`, uploads `site/` as it is,
then deploys that commit with GitHub's official Pages actions. The repository Pages
source must be **GitHub Actions**. The workflow uses only read access to repository content
plus the scoped `pages: write` and `id-token: write` permissions required for deployment.

No generated website files require manual editing after deployment. The release checklist
must confirm the public page, direct installer, release notes, source, issue, license, and
AltTab links before tagging a release.
