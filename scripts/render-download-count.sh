#!/bin/bash
# Writes WindowHop's installer download total and GitHub star count into a staged
# copy of the site: "Downloaded N times" in the download section, and the same two
# numbers in one line under the hero's buttons.
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
# that number out, and an element with no number stays hidden; the script exits 0
# either way: a missing count must never block a deploy.
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

stats_placeholder='<p class="hero-stats" id="hero-stats" hidden></p>'
grep -Fq "$stats_placeholder" "$page" || {
  echo "$page has no empty hero-stats element to fill" >&2
  exit 1
}

# A literal substring replace: awk's index() takes no pattern, and bash's own
# ${var/old/new} treats quotes in the replacement differently across versions.
replace() {
  awk -v old="$1" -v new="$2" '{
    i = index($0, old)
    if (i) $0 = substr($0, 1, i - 1) new substr($0, i + length(old))
    print
  }' "$page" > "$page.tmp" && mv "$page.tmp" "$page"
}

# 1234567 -> 1,234,567, independent of the runner's locale.
group() {
  local digits=$1 grouped=""
  while [ ${#digits} -gt 3 ]; do
    grouped=",${digits: -3}$grouped"
    digits=${digits:0:${#digits}-3}
  done
  echo "$digits$grouped"
}

# Prints the installer download total, or nothing.
downloads() {
  local counts count total=0
  counts=$(gh api --paginate "repos/$repo/releases" \
    --jq '.[].assets[] | select(.name | test("^WindowHop-[0-9.]+(-Installer\\.zip|\\.dmg)$")) | .download_count') \
    || { echo "download count omitted: GitHub API request failed" >&2; return 0; }
  while IFS= read -r count; do
    [ -n "$count" ] || continue
    [[ "$count" =~ ^[0-9]+$ ]] || { echo "download count omitted: unexpected API value" >&2; return 0; }
    total=$((total + count))
  done <<< "$counts"
  [ "$total" -gt 0 ] || { echo "download count omitted: no installer downloads reported" >&2; return 0; }
  echo "$total"
}

# Prints the repository's star count, or nothing.
stars() {
  local count
  count=$(gh api "repos/$repo" --jq '.stargazers_count') \
    || { echo "star count omitted: GitHub API request failed" >&2; return 0; }
  [[ "$count" =~ ^[0-9]+$ ]] && [ "$count" -gt 0 ] \
    || { echo "star count omitted: no stars reported" >&2; return 0; }
  echo "$count"
}

command -v gh >/dev/null 2>&1 || { echo "counts omitted: gh is not installed"; exit 0; }
total=$(downloads)
star_count=$(stars)

parts=()
if [ -n "$total" ]; then
  grouped=$(group "$total")
  if [ "$total" -eq 1 ]; then noun="time"; else noun="times"; fi
  replace "$placeholder" "<p class=\"download-count\" id=\"download-count\">Downloaded $grouped $noun</p>"
  if [ "$total" -eq 1 ]; then noun="download"; else noun="downloads"; fi
  parts+=("<span class=\"pill\"><svg viewBox=\"0 0 16 16\" width=\"14\" height=\"14\" aria-hidden=\"true\" focusable=\"false\"><path d=\"M8 2v8m0 0 3.5-3.5M8 10 4.5 6.5M3 13h10\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.6\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/></svg>$grouped $noun</span>")
  echo "download count: $grouped"
fi
if [ -n "$star_count" ]; then
  grouped=$(group "$star_count")
  if [ "$star_count" -eq 1 ]; then noun="star"; else noun="stars"; fi
  parts+=("<a class=\"pill\" href=\"https://github.com/$repo/stargazers\" rel=\"noopener\"><svg viewBox=\"0 0 16 16\" width=\"14\" height=\"14\" aria-hidden=\"true\" focusable=\"false\"><path d=\"m8 1.8 1.9 3.9 4.3.6-3.1 3 .7 4.3L8 11.6l-3.8 2 .7-4.3-3.1-3 4.3-.6z\" fill=\"currentColor\"/></svg>$grouped $noun on GitHub</a>")
  echo "star count: $grouped"
fi
# The same two numbers as JSON, for the README's shields.io badges: the downloads
# badge must match the site's count, which GitHub's own total does not (it also
# counts Sparkle's update archives). A missing number is left out.
{
  printf '{'
  [ -n "$total" ] && printf '"downloads": %s' "$total"
  [ -n "$total" ] && [ -n "$star_count" ] && printf ', '
  [ -n "$star_count" ] && printf '"stars": %s' "$star_count"
  printf '}\n'
} > "$site_dir/stats.json"

if [ ${#parts[@]} -gt 0 ]; then
  joined=$(printf '%s' "${parts[0]}"; [ ${#parts[@]} -gt 1 ] && printf '%s' "${parts[1]}")
  replace "$stats_placeholder" "<p class=\"hero-stats\" id=\"hero-stats\">$joined</p>"
fi
