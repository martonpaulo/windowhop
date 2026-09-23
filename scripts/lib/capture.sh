#!/usr/bin/env bash
# Canonical screenshot protocol for the owner's macOS apps. Copy it unchanged to
# scripts/lib/capture.sh in each app that captures its own windows; project-setup alignment reports
# a drifted copy. It is a library: source it, never run it. It sets no option, changes no
# directory, installs no trap and runs nothing when sourced; its functions return 2 for a usage
# error and 1 for a failure, and never exit, so the driver decides what a failure means.
#
# The app captures itself: launched by the driver, it opens its window and prints, one per line,
#   SCALE <backing scale of the window's screen>
#   WINDOW_ID <the window's number>
#   KEY <true|false> ...        optional; when printed it must say true
#   READY                       once the window is open, key and settled
# and then waits to be stopped. The library waits for READY, requires a Retina scale, captures
# that window with `screencapture -l<id>` (never -o, which strips the shadow), stops the app, and
# converts to lossless WebP.
#
# A driver keeps what is captured and how the app is built; the protocol lives here:
#
#   cd "$(dirname "$0")/.."
#   . scripts/lib/capture.sh
#   trap capture_cleanup EXIT
#   capture_preflight
#   capture_window --name panel --output-dir site/screenshots -- .build/debug/<App> --capture panel
#
# Call capture_window directly, not inside $(...): its state lives in this shell. A launcher that
# is not the app process, such as `open -n <bundle> --stdout "$CAPTURE_LOG"` wrapped in a driver
# function, works because the handshake is read from $CAPTURE_LOG; such a driver redefines
# capture_stop after sourcing, to stop the real app.

# Checks for the tools a capture needs. Returns 1 and names each missing one.
capture_preflight() {
  local tool missing=0
  for tool in screencapture cwebp; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      if [[ $tool == cwebp ]]; then
        printf 'capture: cwebp is required (brew install webp)\n' >&2
      else
        printf 'capture: %s is required; captures run on a Mac\n' "$tool" >&2
      fi
      missing=1
    fi
  done
  return "$missing"
}

# capture_window --name <kebab-name> --output-dir <dir> [--timeout <seconds>] -- <command> [args...]
# Launches the command, captures the window it names and writes <dir>/<name>.webp, whose path it
# prints on stdout.
capture_window() {
  local name='' output_dir='' timeout=20
  while [[ $# -gt 0 ]]; do
    case $1 in
      --name | --output-dir | --timeout)
        if [[ $# -lt 2 ]]; then
          printf 'capture_window: %s needs a value\n' "$1" >&2
          return 2
        fi
        case $1 in
          --name) name=$2 ;;
          --output-dir) output_dir=$2 ;;
          --timeout) timeout=$2 ;;
        esac
        shift 2
        ;;
      --) shift; break ;;
      *) printf 'capture_window: unknown option %s\n' "$1" >&2; return 2 ;;
    esac
  done
  if [[ ! $name =~ ^[a-z0-9-]+$ ]]; then
    printf 'capture_window: --name must be lowercase letters, digits and hyphens, not "%s"\n' "$name" >&2
    return 2
  fi
  if [[ -z $output_dir ]]; then
    printf 'capture_window: --output-dir is required\n' >&2
    return 2
  fi
  if [[ ! $timeout =~ ^[1-9][0-9]*$ ]]; then
    printf 'capture_window: --timeout must be a whole number of seconds, not "%s"\n' "$timeout" >&2
    return 2
  fi
  if [[ $# -eq 0 ]]; then
    printf 'capture_window: give the command that launches the app after --\n' >&2
    return 2
  fi
  capture_preflight || return 1

  if [[ -z ${CAPTURE_DIR:-} || ! -d $CAPTURE_DIR ]]; then
    CAPTURE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/capture.XXXXXX") || return 1
  fi
  CAPTURE_LOG=$CAPTURE_DIR/$name.log
  : >"$CAPTURE_LOG" || return 1
  "$@" >>"$CAPTURE_LOG" 2>&1 &
  CAPTURE_PID=$!

  local waited=0
  until grep -Fxq READY "$CAPTURE_LOG"; do
    if (( waited >= timeout * 10 )); then
      printf 'capture: %s did not print READY within %ss; its output:\n' "$name" "$timeout" >&2
      cat "$CAPTURE_LOG" >&2
      capture_stop
      return 1
    fi
    sleep 0.1
    waited=$((waited + 1))
  done

  local scale window_id key
  scale=$(capture_field SCALE)
  window_id=$(capture_field WINDOW_ID)
  key=$(capture_field KEY)
  if [[ ! $scale =~ ^[0-9]+(\.[0-9]+)?$ ]] || (( ${scale%%.*} < 2 )); then
    printf 'capture: %s needs a Retina display; the window reports scale "%s"\n' "$name" "$scale" >&2
    capture_stop
    return 1
  fi
  if [[ ! $window_id =~ ^[0-9]+$ ]]; then
    printf 'capture: %s printed no usable WINDOW_ID ("%s")\n' "$name" "$window_id" >&2
    capture_stop
    return 1
  fi
  if [[ -n $key && $key != true ]]; then
    printf 'capture: %s was not key, so its controls would render inactive\n' "$name" >&2
    capture_stop
    return 1
  fi

  local png=$CAPTURE_DIR/$name.png
  rm -f "$png"
  # No -o: that flag is what removes the window's shadow.
  if ! screencapture -x -l"$window_id" -t png "$png"; then
    printf 'capture: screencapture failed for %s\n' "$name" >&2
    capture_stop
    return 1
  fi
  capture_stop
  if [[ ! -s $png ]]; then
    printf 'capture: screencapture wrote nothing for %s; is Screen Recording allowed?\n' "$name" >&2
    return 1
  fi

  local target=$output_dir/$name.webp partial=$output_dir/.$name.webp.partial
  mkdir -p "$output_dir" || return 1
  # -exact keeps the colour under transparent pixels, so the shadow's soft edge stays intact.
  if ! cwebp -quiet -lossless -exact -z 9 -metadata none "$png" -o "$partial"; then
    printf 'capture: cwebp failed for %s\n' "$name" >&2
    rm -f "$partial" "$png"
    return 1
  fi
  mv -f "$partial" "$target" || return 1
  rm -f "$png"
  printf '%s\n' "$target"
}

# Stops the launched process and waits for it. A driver whose launcher is not the app process
# redefines this after sourcing.
capture_stop() {
  if [[ -n ${CAPTURE_PID:-} ]]; then
    kill -TERM "$CAPTURE_PID" 2>/dev/null || true
    wait "$CAPTURE_PID" 2>/dev/null || true
    CAPTURE_PID=''
  fi
  return 0
}

# Stops the app and removes the working directory. Safe to call twice, and when nothing ran, so
# a driver can register it with `trap capture_cleanup EXIT`.
capture_cleanup() {
  capture_stop
  if [[ -n ${CAPTURE_DIR:-} ]]; then
    rm -rf "$CAPTURE_DIR"
    CAPTURE_DIR=''
  fi
  return 0
}

# The value of the last "<field> <value>" line in the app's output.
capture_field() {
  local line value=''
  while IFS= read -r line; do
    case $line in
      "$1 "*) value=${line#"$1 "}; value=${value%% *} ;;
    esac
  done <"$CAPTURE_LOG"
  printf '%s' "$value"
}
