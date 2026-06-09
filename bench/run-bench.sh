#!/usr/bin/env bash
# run-bench.sh — measure the GPU cost of every ghostty-weather scene as a
# percentage of the display's per-frame budget, and gate on a threshold.
#
# Builds the headless glsl_bench harness (if needed), benchmarks a trivial
# passthrough baseline plus all 6 scenes at the given resolution, and prints a
# table of ms/frame and % of the frame budget. Exits non-zero if any scene
# exceeds the budget threshold — usable as a CI / pre-commit gate.
#
# The frame budget is 1000 / refresh_hz ms (8.33 ms at 120 Hz). "% budget" is
# how much of a single frame's wall-clock one full-screen shader pass consumes
# at the target resolution; the cap keeps the always-on effect from eating the
# GPU time the rest of the system (and other windows) need.
#
# Tunables (env):
#   GHOSTTY_WEATHER_BENCH_W / _H      resolution (default 3456 x 2234, the
#                                      built-in Retina panel — worst case)
#   GHOSTTY_WEATHER_REFRESH_HZ        refresh rate (default 120 = ProMotion)
#   GHOSTTY_WEATHER_BUDGET_PCT        pass/fail threshold (default 5.0)
#   GHOSTTY_WEATHER_BENCH_FRAMES      frames per trial (default 400)
#   GHOSTTY_WEATHER_BENCH_TRIALS      trials, median reported (default 7)
#
# macOS only — uses CGL/OpenGL. (See glsl_bench.c for the Metal-proxy caveat.)

set -euo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
SCENES_DIR="$SCRIPT_DIR/../shaders/scenes"
BIN="$SCRIPT_DIR/glsl_bench"
SRC="$SCRIPT_DIR/glsl_bench.c"

W="${GHOSTTY_WEATHER_BENCH_W:-3456}"
H="${GHOSTTY_WEATHER_BENCH_H:-2234}"
REFRESH="${GHOSTTY_WEATHER_REFRESH_HZ:-120}"
THRESH="${GHOSTTY_WEATHER_BUDGET_PCT:-5.0}"
FRAMES="${GHOSTTY_WEATHER_BENCH_FRAMES:-400}"
TRIALS="${GHOSTTY_WEATHER_BENCH_TRIALS:-7}"

if [[ "$(uname)" != "Darwin" ]]; then
    echo "run-bench.sh: macOS only (needs CGL/OpenGL)." >&2
    exit 1
fi

# Build if the binary is missing or older than its source.
if [[ ! -x "$BIN" || "$SRC" -nt "$BIN" ]]; then
    echo "building glsl_bench..." >&2
    clang -O2 -DGL_SILENCE_DEPRECATION "$SRC" -framework OpenGL -o "$BIN"
fi

BUDGET_MS=$(awk -v r="$REFRESH" 'BEGIN{ printf "%.4f", 1000.0/r }')

echo
echo "ghostty-weather scene compute benchmark"
echo "  resolution : ${W} x ${H}  ($(awk -v w="$W" -v h="$H" 'BEGIN{printf "%.1f", w*h/1e6}') Mpx)"
echo "  refresh    : ${REFRESH} Hz   frame budget : ${BUDGET_MS} ms"
echo "  threshold  : ${THRESH}% of budget   (${FRAMES} frames x ${TRIALS} trials, median)"
echo
printf "  %-14s %12s %12s %10s   %s\n" "scene" "median(ms)" "min(ms)" "%budget" "verdict"
printf "  %-14s %12s %12s %10s   %s\n" "--------------" "----------" "--------" "-------" "-------"

# Baseline first (passthrough), then every scene, sorted.
SCENES=$(find "$SCENES_DIR" -maxdepth 1 -name '*.glsl' -exec basename {} .glsl \; | sort)

over_count=0
run_one() {
    local label="$1" arg="$2"
    local out median min pct verdict
    out=$("$BIN" "$arg" "$W" "$H" "$FRAMES" "$TRIALS" 2>/dev/null) || {
        printf "  %-14s %12s\n" "$label" "ERROR"
        return 1
    }
    median=$(printf '%s\n' "$out" | sed -n 's/.*median_ms=\([0-9.]*\).*/\1/p')
    min=$(printf '%s\n' "$out" | sed -n 's/.*min_ms=\([0-9.]*\).*/\1/p')
    pct=$(awk -v m="$median" -v b="$BUDGET_MS" 'BEGIN{ printf "%.2f", m/b*100 }')
    if [[ "$label" == "baseline" ]]; then
        verdict="(reference)"
    elif awk -v p="$pct" -v t="$THRESH" 'BEGIN{ exit !(p > t) }'; then
        verdict="OVER"
        over_count=$((over_count + 1))
    else
        verdict="ok"
    fi
    printf "  %-14s %12s %12s %9s%%   %s\n" "$label" "$median" "$min" "$pct" "$verdict"
}

run_one "baseline" "--baseline"
while IFS= read -r s; do
    [[ -n "$s" ]] || continue
    run_one "$s" "$SCENES_DIR/$s.glsl"
done <<< "$SCENES"

echo
if [[ "$over_count" -gt 0 ]]; then
    echo "RESULT: $over_count scene(s) exceed ${THRESH}% of the frame budget." >&2
    exit 1
fi
echo "RESULT: all scenes within ${THRESH}% of the frame budget."
