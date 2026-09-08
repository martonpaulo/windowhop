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
#   * `swift build` already done;
#   * `cwebp` (brew install webp) for the lossless WebP the site publishes.
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
#
#   capture <name> <max-width|native> <demo arguments...>
#
# `max-width` caps the published pixel width. A capture is taken at the
# display's backing scale, which is the right size only if the image is shown
# at half those pixels somewhere. The switcher panel is 1206 pt wide, so its
# capture is 2412 px, while the site shows it in a 434 pt slot and the README at
# about 830 pt — more than 5x and 1.5x oversampled. Capping it at twice the
# largest slot keeps it sharp everywhere and stops the page paying for pixels
# nobody displays. `native` means the image is already at or below 2x of its
# largest slot.
capture() {
    local name=$1 max_width=$2
    shift 2
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
    if [ "$max_width" != native ]; then
        local width
        width=$(sips -g pixelWidth "$OUTPUT/$name.png" | tail -1 | awk '{print $2}')
        if [ "$width" -gt "$max_width" ]; then
            # sips is built into macOS and its resampling is indistinguishable
            # here from ImageMagick's Lanczos, so the script stays dependency-free
            sips --resampleWidth "$max_width" "$OUTPUT/$name.png" >/dev/null
        fi
    fi
    # Published as lossless WebP: identical pixels, about a third of the bytes.
    # The alpha the shadow needs survives, and every macOS 14 browser reads it.
    cwebp -quiet -lossless -z 9 -metadata none "$OUTPUT/$name.png" -o "$OUTPUT/$name.webp"
    rm -f "$OUTPUT/$name.png"
    printf '%-32s %s  %sKB\n' "$name.webp" \
        "$(sips -g pixelWidth -g pixelHeight "$OUTPUT/$name.webp" | tail -2 | tr -d ' \n')" \
        "$(( $(stat -f%z "$OUTPUT/$name.webp") / 1024 ))"
}

capture switcher-light            1660 --demo-switcher --columns 8
capture switcher-dark             1660 --demo-switcher --dark --columns 8
capture switcher-previews-light   native --demo-switcher --previews --columns 4
capture switcher-previews-dark    native --demo-switcher --previews --dark --columns 4
capture switcher-expanded-light   native --demo-switcher --previews --expanded --columns 4
capture settings-general          native --demo-settings general
capture settings-windows          native --demo-settings windows
capture settings-appearance       native --demo-settings appearance

echo "captured into $OUTPUT"
