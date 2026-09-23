#!/bin/bash
# Writes WindowHop's installer download total into a staged copy of the site.
#
#   scripts/render-download-count.sh <staged-site-dir>
#
# The deploy workflow copies site/ to a temporary directory and runs this on the
# copy, so the number is plain text in the published HTML: the page makes no
# request to show it and it reads the same with JavaScript off. Never point this
# at site/ itself; the committed page keeps the element empty and hidden.
#
# Counted: every release's WindowHop-<version>.dmg and WindowHop-<version>-Installer.zip,
# the two things a person downloads to install. Not counted: WindowHop-<version>.zip,
# the Sparkle update archive, because an in-place update is an existing install
# (docs/product.md), and checksums.txt.
#
# Any failure to get a number (no gh, no token, API error, a total of zero) leaves
# the element hidden and exits 0: a missing count must never block a deploy.
set -euo pipefail

site_dir=${1:?usage: render-download-count.sh <staged-site-dir>}
page="$site_dir/index.html"
placeholder='<p class="download-count" id="download-count" hidden></p>'
repo=${WINDOWHOP_REPOSITORY:-martonpaulo/windowhop}

test -f "$page" || { echo "no index.html in $site_dir" >&2; exit 1; }
grep -Fq "$placeholder" "$page" || {
  echo "$page has no empty download-count element to fill" >&2
  exit 1
}

skip() { echo "download count omitted: $1"; exit 0; }

command -v gh >/dev/null 2>&1 || skip "gh is not installed"
counts=$(gh api --paginate "repos/$repo/releases" \
  --jq '.[].assets[] | select(.name | test("^WindowHop-[0-9.]+(-Installer\\.zip|\\.dmg)$")) | .download_count') \
  || skip "GitHub API request failed"

total=0
while IFS= read -r count; do
  [ -n "$count" ] || continue
  [[ "$count" =~ ^[0-9]+$ ]] || skip "unexpected API value: $count"
  total=$((total + count))
done <<< "$counts"
[ "$total" -gt 0 ] || skip "no installer downloads reported"

# 1234567 -> 1,234,567, independent of the runner's locale.
digits=$total grouped=""
while [ ${#digits} -gt 3 ]; do
  grouped=",${digits: -3}$grouped"
  digits=${digits:0:${#digits}-3}
done
grouped="$digits$grouped"
if [ "$total" -eq 1 ]; then noun="time"; else noun="times"; fi

filled="<p class=\"download-count\" id=\"download-count\">Downloaded $grouped $noun</p>"
# A literal substring replace: awk's index() takes no pattern, and bash's own
# ${var/old/new} treats quotes in the replacement differently across versions.
awk -v old="$placeholder" -v new="$filled" '{
  i = index($0, old)
  if (i) $0 = substr($0, 1, i - 1) new substr($0, i + length(old))
  print
}' "$page" > "$page.tmp" && mv "$page.tmp" "$page" || exit 1
echo "download count: $grouped"
