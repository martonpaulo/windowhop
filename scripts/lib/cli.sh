# shellcheck shell=bash
# The command-line helpers every release script sources (#1678), so a fix lands once. A script
# defines usage() and sources this file right after `set -euo pipefail`:
#   . "$(dirname "${BASH_SOURCE[0]}")/lib/cli.sh"

# PlistBuddy, replaceable for tests, and the app's Info.plist, relative to the repository root.
PLIST_BUDDY=${PLIST_BUDDY:-/usr/libexec/PlistBuddy}
PLIST=Support/Info.plist

# A usage error: the message, then the usage, exit 2.
fail_usage() { echo "error: $1" >&2; usage >&2; exit 2; }
# An option that needs a value: $1 the option, $2 what follows it.
need_value() { [[ $# -ge 2 && -n $2 && $2 != --* ]] || fail_usage "$1 needs a value"; }
# A failure: the message, exit 1.
die() { echo "error: $1" >&2; exit 1; }
