#!/usr/bin/env bash
# Validates site/ before GitHub Pages deploy.
set -euo pipefail
cd "$(dirname "$0")/.."
DOCS=site
fail() { echo "validate-site: $1" >&2; exit 1; }
[ -f "$DOCS/CNAME" ] || fail "missing $DOCS/CNAME"
HOST=$(tr -d '[:space:]' < "$DOCS/CNAME")
[[ "$HOST" =~ ^[a-z0-9-]+\.martonpaulo\.com$ ]] || fail "CNAME host '$HOST' is not a martonpaulo.com subdomain"
URL="https://$HOST/"
[ -f "$DOCS/index.html" ] || fail "missing $DOCS/index.html"
[ -f "$DOCS/.nojekyll" ] || fail "missing $DOCS/.nojekyll"
grep -q "<link rel=\"canonical\" href=\"$URL\">" "$DOCS/index.html" || fail "index.html canonical must be $URL"
grep -q "<meta property=\"og:url\" content=\"$URL\">" "$DOCS/index.html" || fail "index.html og:url must be $URL"
grep -qi 'noindex' "$DOCS/index.html" && fail "index.html must not contain noindex"
grep -q "Sitemap: ${URL}sitemap.xml" "$DOCS/robots.txt" || fail "robots.txt must reference ${URL}sitemap.xml"
grep -q "<loc>$URL</loc>" "$DOCS/sitemap.xml" || fail "sitemap.xml must list $URL"
grep -q 'Disallow: /$' "$DOCS/robots.txt" && fail "robots.txt must not disallow the whole site"
echo "validate-site: OK ($URL)"
