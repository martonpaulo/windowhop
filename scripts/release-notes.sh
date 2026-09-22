#!/usr/bin/env bash
# Prints the release notes of one version from CHANGELOG.md.
#
# CHANGELOG.md follows Keep a Changelog (https://keepachangelog.com/en/1.1.0/):
# a version section starts at `## [X.Y.Z] - YYYY-MM-DD` and ends at the next
# `## ` heading or at the link reference definitions closing the file. The body
# is printed without its surrounding blank lines.
#
# Usage: scripts/release-notes.sh --version X.Y.Z [--changelog PATH]
# Exit 0 = notes printed on stdout; 1 = no such version, or its body is empty;
# 2 = usage error.
set -euo pipefail

usage() {
    echo "Usage: $0 --version X.Y.Z [--changelog PATH]" >&2
    exit 2
}

VERSION=""
CHANGELOG="$(dirname "$0")/../CHANGELOG.md"
while [ $# -gt 0 ]; do
    case "$1" in
        --version) [ $# -ge 2 ] || usage; VERSION="$2"; shift 2 ;;
        --changelog) [ $# -ge 2 ] || usage; CHANGELOG="$2"; shift 2 ;;
        *) usage ;;
    esac
done
[ -n "$VERSION" ] || usage
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Not a X.Y.Z version: $VERSION" >&2; exit 2; }
[ -f "$CHANGELOG" ] || { echo "Changelog not found: $CHANGELOG" >&2; exit 1; }

# index() compares literally, so the version's dots are not regex wildcards; the
# closing bracket keeps 1.1.1 from matching 1.1.10.
NOTES=$(awk -v v="$VERSION" '
    !found && index($0, "## [" v "]") == 1 { found = 1; next }
    found && (/^## / || /^\[[^]]+\]: /) { exit }
    found { lines[++n] = $0 }
    END {
        first = 1; while (first <= n && lines[first] ~ /^[[:space:]]*$/) first++
        last = n;  while (last >= first && lines[last] ~ /^[[:space:]]*$/) last--
        for (i = first; i <= last; i++) print lines[i]
    }
' "$CHANGELOG")

if [ -z "$NOTES" ]; then
    echo "No release notes for $VERSION in $CHANGELOG." >&2
    exit 1
fi
printf '%s\n' "$NOTES"
