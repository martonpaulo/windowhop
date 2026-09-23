#!/bin/bash
# Captures the published screenshots in site/screenshots/.
#
# Why a real on-screen capture instead of the offscreen `--render-ui` harness:
# `screencapture -l<windowid>` records the window as macOS actually composites
# it — rounded corners, the window's own drop shadow, and transparency around
# them — and at the display's backing scale. An offscreen bitmap has none of
# that: square corners, no shadow, no elevation. `--render-ui` stays the
# layout/regression harness; this script produces the images people look at.
#
# This is a driver over scripts/lib/capture.sh, skill-deck's canonical capture
# protocol, kept byte-identical: the demo prints SCALE, WINDOW_ID (and KEY for
# Settings) and READY, and the library refuses a non-Retina scale, captures that
# one window with its shadow, stops the demo and writes lossless WebP. What is
# captured, the published widths and the srcset variants stay here.
#
# Requirements:
#   * a 2x display for the demo windows; the library refuses anything less. When the
#     main display is 1x, this script creates a temporary 2x display
#     (scripts/capture-display.m) and the demos draw there, so the images are Retina
#     on any Mac. The display disappears when the script exits;
#   * Screen Recording permission for the terminal running this;
#   * the Xcode command line tools (clang) to build that display tool;
#   * `swift build` already done;
#   * `cwebp` and `dwebp` (brew install webp) for the WebP the site publishes.
#
# Usage: scripts/capture-screenshots.sh [output-directory]
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/lib/capture.sh

DISPLAY_PID=
cleanup() {
    capture_cleanup
    [ -z "$DISPLAY_PID" ] || kill "$DISPLAY_PID" 2>/dev/null || true
}
trap cleanup EXIT

OUTPUT=${1:-site/screenshots}
BINARY=.build/debug/WindowHop

[ -x "$BINARY" ] || { echo "$BINARY missing; run swift build first" >&2; exit 1; }
capture_preflight
command -v dwebp >/dev/null 2>&1 || { echo "dwebp is required (brew install webp)" >&2; exit 1; }

# Adds the temporary 2x display when the main display is 1x (see capture-display.m).
main_scale=$(swift -e 'import AppKit; print(Int(NSScreen.main?.backingScaleFactor ?? 1))' 2>/dev/null || echo 1)
if [ "$main_scale" -lt 2 ]; then
    mkdir -p artifacts
    clang -fobjc-arc -framework Foundation -framework CoreGraphics \
        scripts/capture-display.m -o artifacts/capture-display
    artifacts/capture-display > artifacts/capture-display.log 2>&1 &
    DISPLAY_PID=$!
    for _ in $(seq 1 50); do
        grep -q '^DISPLAY ' artifacts/capture-display.log && break
        kill -0 "$DISPLAY_PID" 2>/dev/null || break
        sleep 0.2
    done
    grep -q '^DISPLAY ' artifacts/capture-display.log || {
        cat artifacts/capture-display.log >&2
        echo "the temporary 2x display did not start" >&2
        exit 1
    }
    # let the window server settle the new arrangement before the first demo opens
    sleep 1
    echo "capturing on a temporary 2x display ($(cat artifacts/capture-display.log))"
fi

# Captures one demo window through the library, then caps its published width.
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
    capture_window --name "$name" --output-dir "$OUTPUT" -- "$BINARY" "$@" >/dev/null || return 1
    local image=$OUTPUT/$name.webp
    if [ "$max_width" != native ]; then
        local width
        width=$(sips -g pixelWidth "$image" | tail -1 | awk '{print $2}')
        if [ "$width" -gt "$max_width" ]; then
            # sips is built into macOS and its resampling is indistinguishable
            # here from ImageMagick's Lanczos; the result is re-encoded with the
            # library's lossless settings
            local png=$CAPTURE_DIR/$name-resampled.png
            dwebp -quiet "$image" -o "$png"
            sips --resampleWidth "$max_width" "$png" >/dev/null
            cwebp -quiet -lossless -exact -z 9 -metadata none "$png" -o "$image"
            rm -f "$png"
        fi
    fi
    printf '%-32s %s  %sKB\n' "$name.webp" \
        "$(sips -g pixelWidth -g pixelHeight "$image" | tail -2 | tr -d ' \n')" \
        "$(( $(stat -f%z "$image") / 1024 ))"
}

# Writes the narrower widths of an image the page serves through srcset, as
# <name>-<width>.webp next to <name>.webp. Each width is resampled once from the
# lossless capture. They are near-lossless rather than lossless because a
# resampled screenshot compresses so much worse losslessly that a smaller width
# can outweigh the full-size file; near-lossless keeps every pixel within a few
# levels of the resample, which leaves text edges visibly identical.
#
#   variants <name> <width...>
variants() {
    local name=$1
    shift
    local tmp
    tmp=$(mktemp -d)
    dwebp -quiet "$OUTPUT/$name.webp" -o "$tmp/full.png"
    local width
    for width in "$@"; do
        cp "$tmp/full.png" "$tmp/$width.png"
        sips --resampleWidth "$width" "$tmp/$width.png" >/dev/null
        cwebp -quiet -near_lossless 60 -z 9 -metadata none "$tmp/$width.png" -o "$OUTPUT/$name-$width.webp"
        printf '%-32s %sKB\n' "$name-$width.webp" "$(( $(stat -f%z "$OUTPUT/$name-$width.webp") / 1024 ))"
    done
    rm -rf "$tmp"
}

capture switcher-light            1660 --demo-switcher --columns 8
capture switcher-dark             1660 --demo-switcher --dark --columns 8
capture switcher-previews-light   native --demo-switcher --previews --columns 4
capture switcher-previews-dark    native --demo-switcher --previews --dark --columns 4
# The argument domain pins overlay scroll bars for this one process, so the operator's
# "Show scroll bars: Always" setting does not draw a scroller track into the image.
# The site shows the capture that matches the visitor's appearance, so both are taken.
capture settings-switcher-light   native --demo-settings switcher --light \
    -AppleShowScrollBars WhenScrolling
capture settings-switcher-dark    native --demo-settings switcher --dark \
    -AppleShowScrollBars WhenScrolling

# The hero's srcset and imagesrcset in site/index.html list exactly these widths.
variants switcher-previews-light 480 720 958 1200
variants switcher-previews-dark  480 720 958 1200

echo "captured into $OUTPUT"
