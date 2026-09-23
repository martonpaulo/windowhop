#!/usr/bin/env bash
# Run a test command and fail when it leaves new windowhop-tests-*.plist files in
# ~/Library/Preferences (#129).
#
# Why: a test suite named without a path lands in ~/Library/Preferences, and teardown
# cannot remove it. removePersistentDomain(forName:) only empties the domain, and cfprefsd
# writes the empty domain back to <suite>.plist after the test process exits, even when
# the file was deleted. Tests make their suites through TestDefaults
# (Tests/WindowHopTestSupport), which puts them under $TMPDIR instead; this check catches
# a test that bypasses it at run time, next to the static rule in scripts/validate.sh.
#
# Only files that did not exist before the run count, so files left by older runs never
# fail it. The script never deletes a file.
#
# Usage: scripts/check-test-defaults-leak.sh <command> [args...]
set -euo pipefail

if [[ $# -eq 0 ]]; then
  echo "usage: $0 <command> [args...]" >&2
  exit 64
fi

prefs="$HOME/Library/Preferences"
# cfprefsd writes a leaked suite between 0 and a few seconds after the process exits
settle_seconds=5

list() { find "$prefs" -maxdepth 1 -name 'windowhop-tests-*.plist' 2>/dev/null | sort || true; }

before="$(mktemp -t windowhop-leak-before)"
after="$(mktemp -t windowhop-leak-after)"
trap 'rm -f "$before" "$after"' EXIT

list >"$before"
status=0
"$@" || status=$?
sleep "$settle_seconds"
list >"$after"

leaked="$(comm -13 "$before" "$after")"
if [[ -n "$leaked" ]]; then
  count="$(printf '%s\n' "$leaked" | wc -l | tr -d ' ')"
  echo "" >&2
  echo "check-test-defaults-leak: '$*' left $count new file(s) in $prefs:" >&2
  printf '%s\n' "$leaked" | head -5 >&2
  echo "Make every test suite with TestDefaults (Tests/WindowHopTestSupport/TestDefaults.swift)." >&2
  [[ $status -ne 0 ]] || status=1
fi
exit "$status"
