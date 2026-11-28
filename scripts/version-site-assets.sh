#!/usr/bin/env bash
# Canonical asset-version step for the owner's hand-written product sites. Copy it unchanged to
# scripts/version-site-assets.sh in each app with a site/; bench-setup alignment reports a
# drifted copy.
#
# A browser must never pair new HTML with a cached old stylesheet or script, so a changed file needs
# a new address. In every *.html of a staged copy of the site, each root-relative address under
# /styles/, /scripts/, /assets/ or /screenshots/ (in src, href, srcset and imagesrcset, every srcset
# candidate included) becomes <path>?v=<first 8 hex of the file's md5>, replacing any earlier ?v=,
# so a second run changes nothing. An address with a scheme or a host is left alone, and addresses
# inside CSS and JavaScript are not rewritten. The deploy runs it last on its staged copy, so no
# version is ever committed (#358).
#
#   --site <dir>   version the staged copy in <dir>; never the tracked site/ itself
#   --check        version a temporary copy of site/ and report what cannot be versioned: a committed
#                  ?v=, an address with no file, or a relative address into one of the four folders
#
# Writes only the staged directory it is given. Stdout stays empty; everything else goes to stderr.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib/cli.sh"
cd "$(dirname "$0")/.."

usage() {
  cat <<'USAGE'
usage: scripts/version-site-assets.sh (--site <staged-dir> | --check)
  --site <staged-dir>   add ?v=<md5> to every local asset address in a staged copy of site/
  --check               check that site/ can be versioned, on a temporary copy
  --help                show this help
USAGE
}


site=''
check=0
while [[ $# -gt 0 ]]; do
  case $1 in
    --site) need_value "$@"; site=$2; shift 2 ;;
    --check) check=1; shift ;;
    --help) usage; exit 0 ;;
    *) fail_usage "unknown option $1" ;;
  esac
done
if [[ -n $site && $check == 1 ]]; then fail_usage 'give --site or --check, not both'; fi
if [[ -z $site && $check == 0 ]]; then fail_usage 'give --site <staged-dir> or --check'; fi

if (( check )); then
  [[ -d site ]] || { echo "error: site/ not found" >&2; exit 1; }
  copy=$(mktemp -d "${TMPDIR:-/tmp}/version-site-assets.XXXXXX")
  trap 'rm -rf "$copy"' EXIT
  cp -R site/. "$copy/"
  mode=check
  target=$copy
else
  [[ -d $site ]] || { echo "error: $site is not a directory" >&2; exit 1; }
  target=$(cd "$site" && pwd -P)
  if [[ -d site && $target == "$(cd site && pwd -P)" ]]; then
    fail_usage 'version a staged copy of site/, never site/ itself'
  fi
  mode=site
fi

python3 - "$target" "$mode" <<'PY'
import hashlib
import os
import re
import sys

site, mode = sys.argv[1], sys.argv[2]
FOLDERS = ("styles/", "scripts/", "assets/", "screenshots/")
ATTRIBUTE = re.compile(r'(\b(?:src|href|srcset|imagesrcset)=")([^"]*)(")')
problems = []
digests = {}


def report(problem):
    """--check reports what cannot be versioned; the deploy leaves it to the site check."""
    if mode == "check":
        problems.append(problem)


def is_srcset(name):
    return name.rstrip('="').endswith("srcset")


def version(page, address):
    """Returns the versioned address, or the address unchanged when it is not a local asset."""
    path, _, query = address.partition("?")
    fragment = ""
    if "#" in path:
        path, fragment = path.split("#", 1)
        fragment = "#" + fragment
    if path.startswith("//") or re.match(r"^[a-zA-Z][a-zA-Z0-9+.-]*:", path):
        return address
    if not path.startswith("/"):
        segments = [segment for segment in path.split("/") if segment not in ("", ".", "..")]
        if len(segments) > 1 and segments[0] + "/" in FOLDERS:
            report("%s: %s is relative; use a root-relative address" % (page, address))
        return address
    if not path.lstrip("/").startswith(FOLDERS):
        return address
    if re.search(r"(^|&)v=", query):
        report("%s: %s carries a committed version; the deploy adds it" % (page, address))
    file = os.path.join(site, path.lstrip("/"))
    if not os.path.isfile(file):
        report("%s: %s has no file" % (page, address))
        return address
    if path not in digests:
        with open(file, "rb") as handle:
            digests[path] = hashlib.md5(handle.read()).hexdigest()[:8]
    kept = "&".join(part for part in query.split("&") if part and not part.startswith("v="))
    return "%s?%sv=%s%s" % (path, kept + "&" if kept else "", digests[path], fragment)


def rewrite(page, match):
    name, value, close = match.group(1), match.group(2), match.group(3)
    if is_srcset(name):
        candidates = []
        for candidate in value.split(","):
            stripped = candidate.strip()
            if not stripped:
                continue
            url, _, descriptor = stripped.partition(" ")
            candidates.append((version(page, url) + (" " + descriptor.strip() if descriptor else "")))
        value = ", ".join(candidates)
    else:
        value = version(page, value.strip())
    return name + value + close


pages = []
for root, dirs, files in os.walk(site):
    dirs.sort()
    for filename in sorted(files):
        if filename.endswith(".html"):
            pages.append(os.path.join(root, filename))
for path in pages:
    page = os.path.relpath(path, site)
    with open(path, encoding="utf-8") as handle:
        text = handle.read()
    text = ATTRIBUTE.sub(lambda match: rewrite(page, match), text)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(text)

if problems:
    sys.stderr.write("".join("version-site-assets: %s\n" % problem for problem in problems))
    sys.exit(1)
if mode == "site":
    sys.stderr.write("version-site-assets: %d files across %d pages\n" % (len(digests), len(pages)))
PY
