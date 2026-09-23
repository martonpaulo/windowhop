#!/usr/bin/env bash
# Run a build or test command and fail when it prints a compiler warning from this
# project's own sources, even when the command itself exits 0.
#
# Why: some Swift 6 diagnostics (for example "mutation of captured var in
# concurrently-executing code") stay warnings under `.treatAllWarnings(as: .error)`, so
# `swift build` succeeds while the log still holds `warning:` lines. Only lines that point
# into Sources/ or Tests/ count; dependencies' build logs (Sparkle, SwiftPM itself) do not.
#
# Usage: scripts/fail-on-warnings.sh <command> [args...]
# The full log is kept in artifacts/ (gitignored) for inspection.
set -euo pipefail

if [[ $# -eq 0 ]]; then
  echo "usage: $0 <command> [args...]" >&2
  exit 64
fi

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$repo_root/artifacts"
log="$repo_root/artifacts/$(basename "$1")-$(date +%Y%m%d-%H%M%S)-$$.log"

status=0
"$@" 2>&1 | tee "$log" || status=$?
if [[ $status -ne 0 ]]; then
  echo "fail-on-warnings: '$*' exited $status (log: $log)" >&2
  exit "$status"
fi

# A compiler diagnostic line looks like `<path>:<line>:<col>: warning: <message>`. The
# compiler colours it even into a pipe, so strip ANSI colour (CSI) and hyperlink (OSC 8)
# sequences first. Paths under .build/ (dependency checkouts, generated code) are not ours.
pattern="^([^:]*/)?(Sources|Tests)/[^:]+:[0-9]+(:[0-9]+)?: warning:"
if warnings="$(perl -pe 's/\e\[[0-9;]*[A-Za-z]//g; s/\e\].*?\e\\//g' "$log" \
  | grep -E "$pattern" | grep -v '/\.build/' | sort -u)"; then
  count="$(printf '%s\n' "$warnings" | wc -l | tr -d ' ')"
  echo "" >&2
  echo "fail-on-warnings: $count compiler warning(s) in project sources (log: $log):" >&2
  printf '%s\n' "$warnings" >&2
  # An incremental build does not replay an up-to-date file's warnings, so the next run
  # would pass. Touching the offending files makes them recompile, keeping the failure
  # until the warning is fixed.
  printf '%s\n' "$warnings" | sed -E 's/:[0-9]+(:[0-9]+)?: warning:.*$//' | sort -u \
    | while IFS= read -r file; do [[ -f "$file" ]] && touch "$file"; done
  exit 1
fi
