#!/bin/bash
# Captures the published screenshots in docs/screenshots/.
#
# Why a real on-screen capture instead of the offscreen `--render-ui` harness:
# `screencapture -l<windowid>` records the window as macOS actually composites
# it — rounded corners, the window's own drop shadow, and transparency around
# them — and at the display's backing scale. An offscreen bitmap has none of
# that: square corners, no shadow, no elevation. `--render-ui` stays the
# layout/regression harness; this script produces the images people look at.
#
# Requirements:
#   * a Retina (2x) display, or the images come out at half resolution;
#   * Screen Recording permission for the terminal running this;
#   * `swift build` already done.
#
# Usage: scripts/capture-screenshots.sh [output-directory]
set -euo pipefail
cd "$(dirname "$0")/.."

OUTPUT=${1:-docs/screenshots}
BINARY=.build/debug/WindowHop
mkdir -p "$OUTPUT"

[ -x "$BINARY" ] || { echo "$BINARY missing; run swift build first" >&2; exit 1; }

# Runs the demo binary with the given arguments, waits for it to print its
# window number, captures that window with its shadow, and stops it.
capture() {
    local name=$1
    shift
    local log
    log=$(mktemp)
    "$BINARY" "$@" > "$log" 2>&1 &
    local pid=$!
    trap 'kill "$pid" 2>/dev/null || true; rm -f "$log"' RETURN

    local window_number="" attempt=0
    while [ $attempt -lt 60 ]; do
        # pipefail would abort the whole script on the not-yet-printed case
        window_number=$(grep -oE 'window number ([0-9]+)' "$log" | tail -1 | awk '{print $3}') || true
        [ -n "$window_number" ] && break
        attempt=$((attempt + 1))
        sleep 0.25
    done
    if [ -z "$window_number" ]; then
        echo "$name: the demo never reported a window number" >&2
        cat "$log" >&2
        return 1
    fi
    # let the panel finish its fade/layout before the shutter
    sleep 1.2
    # -o would drop the shadow, -l picks exactly this window, so nothing of the
    # operator's own desktop can appear in a published image
    screencapture -x -l"$window_number" -t png "$OUTPUT/$name.png"
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    printf '%-32s %s\n' "$name.png" "$(sips -g pixelWidth -g pixelHeight "$OUTPUT/$name.png" \
        | tail -2 | tr -d ' \n')"
}

capture switcher-light            --demo-switcher --columns 8
capture switcher-dark             --demo-switcher --dark --columns 8
capture switcher-previews-light   --demo-switcher --previews --columns 4
capture switcher-previews-dark    --demo-switcher --previews --dark --columns 4
capture switcher-expanded-light   --demo-switcher --previews --expanded --columns 4
capture settings-general          --demo-settings general
capture settings-windows          --demo-settings windows
capture settings-appearance       --demo-settings appearance

echo "captured into $OUTPUT"
