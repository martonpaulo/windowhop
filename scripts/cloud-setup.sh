#!/usr/bin/env bash
# Prepare a Claude Code cloud session for this repository with Skill Deck's engine (skill-deck#914).
# The packages and the Mac-only paths are in .github/cloud.json.
#
#   bash scripts/cloud-setup.sh            # set the session up (as root)
#   bash scripts/cloud-setup.sh --dry-run  # print each step's command and change nothing
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
parent="$(dirname "$root")"
deck="${SKILL_DECK:-$parent/workbench}"
if [[ -z "${SKILL_DECK:-}" && ! -d "$deck" ]]; then
  deck="$parent/skill-deck"
fi
engine="$deck/skills/bench-setup/scripts/cloud_setup.py"
if [[ ! -f "$engine" ]]; then
  echo "cloud-setup: no Skill Deck at $deck; attach martonpaulo/workbench to the session" >&2
  exit 2
fi
exec python3 "$engine" run --root "$root" "$@"
