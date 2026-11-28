#!/usr/bin/env bash
# Canonical Keep a Changelog release-notes script for the owner's macOS apps. Copy it unchanged to
# scripts/release-notes.sh in each app; bench-setup alignment reports a drifted copy.
#
# --version X.Y.Z prints that version's notes on stdout, for publish-release.sh --notes-file. A
# version section starts at `## [X.Y.Z]`, found by exact string equality so 1.1.1 never matches
# 1.1.10, and ends at the next `## ` heading or at the `[x.y.z]: url` link list closing the file.
# Blank lines around the body are trimmed.
#
# --check validates the changelog's shape for make validate: exactly one `## [Unreleased]` above
# every version heading, every version heading written `## [X.Y.Z] - YYYY-MM-DD`, and the newest
# version equal to CFBundleShortVersionString in Support/Info.plist.
#
# --json prints every released entry, newest first, as a JSON array of
# {"version": "X.Y.Z", "date": "YYYY-MM-DD", "body": "<trimmed Markdown>"}, for
# render-release-notes.sh, so every consumer reads the changelog with this one parser.
#
# Exit 0 = notes printed or the changelog passed; 1 = missing or empty notes, or a failed check;
# 2 = usage error.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib/cli.sh"
cd "$(dirname "$0")/.."

usage() {
  cat <<'USAGE'
usage: scripts/release-notes.sh (--version <X.Y.Z> | --check | --json) [--changelog <path>]
  --version <X.Y.Z>    print that version's release notes on stdout
  --check              check the changelog's shape against Support/Info.plist
  --json               print every released entry as JSON on stdout, newest first
  --changelog <path>   the changelog to read (default CHANGELOG.md)
  --help               show this help
USAGE
}


mode=''
version=''
changelog=CHANGELOG.md
set_mode() { [[ -z $mode ]] || fail_usage 'give exactly one of --version, --check and --json'; mode=$1; }
while [[ $# -gt 0 ]]; do
  case $1 in
    --version) need_value "$@"; set_mode version; version=$2; shift 2 ;;
    --check) set_mode check; shift ;;
    --json) set_mode json; shift ;;
    --changelog) need_value "$@"; changelog=$2; shift 2 ;;
    --help) usage; exit 0 ;;
    *) fail_usage "unknown option $1" ;;
  esac
done
[[ -n $mode ]] || fail_usage 'give exactly one of --version, --check and --json'
if [[ $mode == version && ! $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  fail_usage "--version must be X.Y.Z, not $version"
fi
[[ -f $changelog ]] || { echo "error: $changelog not found" >&2; exit 1; }

python3 - "$mode" "$version" "$changelog" <<'PY'
import json
import os
import plistlib
import re
import sys

mode, version, changelog = sys.argv[1:4]
PLIST = "Support/Info.plist"
VERSION_HEADING = re.compile(r"## \[([0-9]+\.[0-9]+\.[0-9]+)\]")
DATED_HEADING = re.compile(r"## \[[0-9]+\.[0-9]+\.[0-9]+\] - ([0-9]{4}-[0-9]{2}-[0-9]{2})")
LINK_DEFINITION = re.compile(r"\[[^\]]+\]: ")


def parse(text):
    """Returns (headings, entries).

    headings: every `## ` line as (line number, text), in file order.
    entries: every released version as (version, date, body_lines), newest first, where date is
    None when the heading is not `## [X.Y.Z] - YYYY-MM-DD`.
    """
    lines = [line.rstrip("\r") for line in text.split("\n")]
    headings = [(number, line) for number, line in enumerate(lines, 1) if line.startswith("## ")]
    entries = []
    for index, line in enumerate(lines):
        heading = VERSION_HEADING.match(line)
        if not heading:
            continue
        body = []
        for following in lines[index + 1:]:
            if following.startswith("## ") or LINK_DEFINITION.match(following):
                break
            body.append(following)
        while body and not body[0].strip():
            body.pop(0)
        while body and not body[-1].strip():
            body.pop()
        dated = DATED_HEADING.fullmatch(line)
        entries.append((heading.group(1), dated.group(1) if dated else None, body))
    return headings, entries


with open(changelog, encoding="utf-8") as handle:
    headings, entries = parse(handle.read())

if mode == "json":
    if not entries:
        sys.stderr.write("No released version in %s.\n" % changelog)
        sys.exit(1)
    released = [{"version": v, "date": d, "body": "\n".join(body)} for v, d, body in entries]
    sys.stdout.write(json.dumps(released, ensure_ascii=False, indent=1) + "\n")
    sys.exit(0)

if mode == "version":
    for entry_version, _date, body in entries:
        # String equality, never a prefix or a pattern: 1.1.1 must not find 1.1.10.
        if entry_version == version:
            if body:
                sys.stdout.write("\n".join(body) + "\n")
                sys.exit(0)
            break
    sys.stderr.write("No release notes for %s in %s.\n" % (version, changelog))
    sys.exit(1)

# --check
problems = []
unreleased = [number for number, line in headings if line == "## [Unreleased]"]
versions = [(number, line) for number, line in headings if VERSION_HEADING.match(line)]
if not unreleased:
    problems.append("no ## [Unreleased] heading; keep exactly one above every version")
elif len(unreleased) > 1:
    problems.append("%d ## [Unreleased] headings (lines %s); keep exactly one"
                    % (len(unreleased), ", ".join(str(number) for number in unreleased)))
if unreleased and versions and unreleased[0] > versions[0][0]:
    problems.append("## [Unreleased] (line %d) is below the version heading on line %d; it goes above every version"
                    % (unreleased[0], versions[0][0]))
for number, line in headings:
    if line.startswith("## [") and line != "## [Unreleased]" and not DATED_HEADING.fullmatch(line):
        problems.append("line %d: %r is not ## [X.Y.Z] - YYYY-MM-DD" % (number, line))
if not os.path.isfile(PLIST):
    problems.append("%s not found; run this from an app repository" % PLIST)
    app_version = None
else:
    with open(PLIST, "rb") as handle:
        app_version = plistlib.load(handle).get("CFBundleShortVersionString")
    if not isinstance(app_version, str) or not app_version:
        problems.append("%s has no CFBundleShortVersionString" % PLIST)
        app_version = None
if not entries:
    problems.append("no released version heading; the newest one must equal the app version")
elif app_version is not None and entries[0][0] != app_version:
    problems.append("the newest version is %s but %s says %s; they must be equal"
                    % (entries[0][0], PLIST, app_version))
if problems:
    for problem in problems:
        sys.stderr.write("%s: %s\n" % (changelog, problem))
    sys.exit(1)
sys.stderr.write("%s: [Unreleased] above %d versions, newest %s matches %s.\n"
                 % (changelog, len(entries), entries[0][0], PLIST))
PY
