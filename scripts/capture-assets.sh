#!/usr/bin/env bash
# capture-assets.sh — regenerate the README scene captures in assets/.
#
# Renders each scene through the web gallery in headless Chrome, using the
# gallery's embed mode (#embed=1, bare terminal window) and deterministic
# fixed-time mode (#t=<secs>), so every capture is reproducible and shows
# the scene mid-animation WITH the simulated terminal text — i.e. what the
# project actually looks like in use.
#
# Maintainer task, not CI: needs a local Chrome. Override the binary with
# CHROME=/path/to/chrome if needed.
#
#   scripts/capture-assets.sh [scene ...]     # default: all six

set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
PORT="${PORT:-8649}"
# 1200x750 canvas (16:10) + 31px titlebar.
WIN="1200,781"

if [[ ! -x "$CHROME" && -z "$(command -v "$CHROME" 2>/dev/null)" ]]; then
    echo "capture-assets.sh: Chrome not found at '$CHROME' (set CHROME=...)" >&2
    exit 1
fi

# Per-scene hash params: settings each scene looks best under, with a fixed
# iTime chosen so animated effects are mid-action (the thunderstorm t lands
# inside a firing lightning slot — re-verify if the scene's hash changes).
params_for() {
    case "$1" in
        clear-day)    echo "time=28800&t=2" ;;          # 08:00 morning sun
        clear-night)  echo "moon=0.5&t=4" ;;            # full moon
        cloudy)       echo "day=1&t=6" ;;
        rain)         echo "day=1&t=5" ;;
        snow)         echo "day=1&t=7" ;;
        thunderstorm) echo "day=0&t=${GW_STORM_T:-45.06}" ;;  # mid-flash
        *)            echo "capture-assets.sh: unknown scene: $1" >&2; return 1 ;;
    esac
}

SCENES=("$@")
[[ ${#SCENES[@]} -gt 0 ]] || SCENES=(clear-day clear-night cloudy rain snow thunderstorm)

SITE="$(mktemp -d "${TMPDIR:-/tmp}/gw-capture.XXXXXX")"
cleanup() {
    [[ -n "${SERVER_PID:-}" ]] && kill "$SERVER_PID" 2>/dev/null
    rm -rf "$SITE"
}
trap cleanup EXIT

"$REPO_ROOT/scripts/build-site.sh" "$SITE" >/dev/null
python3 -m http.server "$PORT" --directory "$SITE" >/dev/null 2>&1 &
SERVER_PID=$!
disown   # keep bash from reporting the cleanup kill at exit
sleep 1

mkdir -p "$REPO_ROOT/assets"
for s in "${SCENES[@]}"; do
    p="$(params_for "$s")"
    out="$REPO_ROOT/assets/$s.png"
    "$CHROME" --headless --disable-gpu-sandbox \
        --window-size="$WIN" --hide-scrollbars \
        --virtual-time-budget=4000 \
        --screenshot="$out" \
        "http://localhost:$PORT/#scene=$s&embed=1&$p" 2>/dev/null
    echo "captured $out"
done
