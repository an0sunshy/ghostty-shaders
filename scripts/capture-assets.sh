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
#   scripts/capture-assets.sh [scene ...]     # default: every scene under shaders/

set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
# shellcheck source=scene-discovery.sh disable=SC1091
. "$REPO_ROOT/scripts/scene-discovery.sh"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
PORT="${PORT:-8649}"
# 1200x750 canvas (16:10) + the 31px titlebar (pinned explicitly in
# web/style.css so a style tweak can't silently crop these captures).
WIN="1200,781"

if [[ ! -x "$CHROME" && -z "$(command -v "$CHROME" 2>/dev/null)" ]]; then
    echo "capture-assets.sh: Chrome not found at '$CHROME' (set CHROME=...)" >&2
    exit 1
fi

shoot() {  # shoot <output.png> <hash-params> [window-size]
    "$CHROME" --headless --disable-gpu-sandbox \
        --window-size="${3:-$WIN}" --hide-scrollbars \
        --virtual-time-budget=4000 \
        --screenshot="$1" \
        "http://localhost:$PORT/#$2" 2>/dev/null
}

# Lightning timestamp for the thunderstorm capture. Only ~30% of the scene's
# 15-second slots fire (hash-gated in thunderstorm.glsl), so a baked-in t
# silently produces a flash-less frame the day anyone retunes the scene's
# timing. Unless GW_STORM_T pins one, sweep the first 12 slots at small size
# and keep the brightest frame — PNG byte size is the luminance proxy (a
# flash adds gradient entropy to an otherwise near-black image).
storm_t() {
    if [[ -n "${GW_STORM_T:-}" ]]; then
        echo "$GW_STORM_T"
        return
    fi
    local best="0.06" best_size=0 k t shot size
    for k in 0 1 2 3 4 5 6 7 8 9 10 11; do
        t="$(awk -v k="$k" 'BEGIN{printf "%.2f", k*15+0.06}')"
        shot="$SITE/storm-sweep-$t.png"
        shoot "$shot" "scene=thunderstorm&embed=1&day=0&t=$t" "400,261"
        size="$(wc -c <"$shot")"
        if (( size > best_size )); then best_size=$size; best=$t; fi
    done
    echo "storm sweep: brightest frame at t=$best" >&2
    echo "$best"
}

# Per-scene hash params: settings each scene looks best under, with a fixed
# iTime chosen so animated effects are mid-action. A new scene must get an
# entry here (the error arm keeps a missing one loud, not silently skipped).
params_for() {
    case "$1" in
        clear-day)    echo "time=28800&t=2" ;;          # 08:00 morning sun
        clear-night)  echo "moon=0.5&t=4" ;;            # full moon
        cloudy)       echo "day=1&t=6" ;;
        rain)         echo "day=1&t=5" ;;
        snow)         echo "day=1&t=7" ;;
        thunderstorm) echo "day=0&t=$(storm_t)" ;;
        *)            echo "capture-assets.sh: no params_for entry for scene: $1" >&2; return 1 ;;
    esac
}

# Default scene list comes from the filesystem (the source of truth), so a
# new scene can't be silently left out of the README assets — it fails on
# the missing params_for entry instead.
SCENES=("$@")
if [[ ${#SCENES[@]} -eq 0 ]]; then
    while IFS= read -r name; do
        SCENES+=("$name")
    done < <(scene_names "$REPO_ROOT/shaders")
fi

SITE="$(mktemp -d "${TMPDIR:-/tmp}/gw-capture.XXXXXX")"
cleanup() {
    # errexit applies inside an EXIT trap: a failed kill (server already
    # dead, e.g. port collision at startup) must not abort before the rm.
    if [[ -n "${SERVER_PID:-}" ]]; then
        kill "$SERVER_PID" 2>/dev/null || true
    fi
    rm -rf "$SITE"
}
trap cleanup EXIT

"$REPO_ROOT/scripts/build-site.sh" "$SITE" >/dev/null
python3 -m http.server "$PORT" --directory "$SITE" >/dev/null 2>&1 &
SERVER_PID=$!
disown   # keep bash from reporting the cleanup kill at exit

# Health-check before shooting anything: a dead server (port already in
# use) or a foreign one serving stale content would otherwise yield
# error-page screenshots while the script reports success and exits 0.
ok=0
for _ in 1 2 3 4 5 6 7 8 9 10; do
    if curl -fsS -o /dev/null "http://localhost:$PORT/scenes/${SCENES[0]}.glsl" 2>/dev/null; then
        ok=1
        break
    fi
    sleep 0.3
done
if [[ $ok -ne 1 ]]; then
    echo "capture-assets.sh: site server failed to serve on port $PORT (already in use?)" >&2
    exit 1
fi

mkdir -p "$REPO_ROOT/assets"
for s in "${SCENES[@]}"; do
    p="$(params_for "$s")"
    out="$REPO_ROOT/assets/$s.png"
    shoot "$out" "scene=$s&embed=1&$p"
    echo "captured $out"
done
