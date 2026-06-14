#!/usr/bin/env bash
# run-bench.sh — measure the GPU cost of every ghostty-shaders scene as a
# percentage of the display's per-frame budget, and gate on a threshold.
#
# Builds the headless glsl_bench harness (if needed), benchmarks a trivial
# passthrough baseline plus every scene at the given resolution, and prints a
# table of ms/frame, % of the frame budget, and a baseline-normalized ratio
# (scene median / baseline median). The ratio cancels runner-speed variance,
# so it is comparable across machines and CI runners in a way absolute ms is
# not. Exits non-zero if any scene exceeds the budget threshold OR regresses
# against a committed baseline (bench/baseline.json) — usable as a CI gate.
#
# The frame budget is 1000 / refresh_hz ms (8.33 ms at 120 Hz). "% budget" is
# how much of a single frame's wall-clock one full-screen shader pass consumes
# at the target resolution; the cap keeps the always-on effect from eating the
# GPU time the rest of the system (and other windows) need.
#
# Tunables (env):
#   GHOSTTY_SHADERS_BENCH_W / _H      resolution (default 3456 x 2234, the
#                                      built-in Retina panel — worst case)
#   GHOSTTY_SHADERS_REFRESH_HZ        refresh rate (default 120 = ProMotion)
#   GHOSTTY_SHADERS_BUDGET_PCT        pass/fail threshold (default 5.0)
#   GHOSTTY_SHADERS_BENCH_FRAMES      frames per trial (default 400)
#   GHOSTTY_SHADERS_BENCH_TRIALS      trials, median reported (default 7)
#   GHOSTTY_SHADERS_BENCH_JSON        if set, write a JSON array of results here
#   GHOSTTY_SHADERS_REGRESSION_PCT    max allowed slowdown vs baseline.json
#                                      before FAIL (default 50)
#
# Flags:
#   --update-baseline   (re)write bench/baseline.json from this run, exit 0
#                       without gating.
#
# macOS only — uses CGL/OpenGL. (See glsl_bench.c for the Metal-proxy caveat.)
# On non-Darwin hosts this is a clean no-op (prints a note, exits 0) so CI lint
# lanes and Linux contributors do not fail.

set -euo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
SHADERS_DIR="$SCRIPT_DIR/../shaders"
# shellcheck source=../scripts/scene-discovery.sh disable=SC1091
. "$SCRIPT_DIR/../scripts/scene-discovery.sh"
BIN="$SCRIPT_DIR/glsl_bench"
SRC="$SCRIPT_DIR/glsl_bench.c"
BASELINE_FILE="$SCRIPT_DIR/baseline.json"

W="${GHOSTTY_SHADERS_BENCH_W:-3456}"
H="${GHOSTTY_SHADERS_BENCH_H:-2234}"
REFRESH="${GHOSTTY_SHADERS_REFRESH_HZ:-120}"
THRESH="${GHOSTTY_SHADERS_BUDGET_PCT:-5.0}"
FRAMES="${GHOSTTY_SHADERS_BENCH_FRAMES:-400}"
TRIALS="${GHOSTTY_SHADERS_BENCH_TRIALS:-7}"
JSON_OUT="${GHOSTTY_SHADERS_BENCH_JSON:-}"
REGRESSION_PCT="${GHOSTTY_SHADERS_REGRESSION_PCT:-50}"

UPDATE_BASELINE=0
for arg in "$@"; do
    case "$arg" in
        --update-baseline) UPDATE_BASELINE=1 ;;
        *) echo "run-bench.sh: unknown argument: $arg" >&2; exit 2 ;;
    esac
done

if [[ "$(uname)" != "Darwin" ]]; then
    echo "run-bench.sh: benchmark requires macOS/CGL; skipping."
    exit 0
fi

# Build if the binary is missing or older than its source.
if [[ ! -x "$BIN" || "$SRC" -nt "$BIN" ]]; then
    echo "building glsl_bench..." >&2
    clang -O2 -DGL_SILENCE_DEPRECATION "$SRC" -framework OpenGL -o "$BIN"
fi

BUDGET_MS=$(awk -v r="$REFRESH" 'BEGIN{ printf "%.4f", 1000.0/r }')

echo
echo "ghostty-shaders scene compute benchmark"
echo "  resolution : ${W} x ${H}  ($(awk -v w="$W" -v h="$H" 'BEGIN{printf "%.1f", w*h/1e6}') Mpx)"
echo "  refresh    : ${REFRESH} Hz   frame budget : ${BUDGET_MS} ms"
echo "  threshold  : ${THRESH}% of budget (default; collections/<c>.conf budget_pct overrides)   (${FRAMES} frames x ${TRIALS} trials, median)"
echo
printf "  %-14s %12s %12s %10s %8s   %s\n" "scene" "median(ms)" "min(ms)" "%budget" "ratio" "verdict"
printf "  %-14s %12s %12s %10s %8s   %s\n" "--------------" "----------" "--------" "-------" "-----" "-------"

# Baseline first (passthrough), then every scene, sorted.
SCENES=$(scene_names "$SHADERS_DIR")

# Accumulators, kept as parallel newline-delimited lists (bash-portable, no
# associative arrays needed). Each line: "<label> <median> <min> <pct> <ratio>".
RESULTS=""
BASELINE_MEDIAN=""
over_count=0

# Per-collection budget: collections/<name>.conf may set `budget_pct = N` so an
# opt-in art collection (e.g. poems, selected by hand) gets a higher ceiling than
# the always-on weather default. Falls back to the global THRESH when unset.
# Same conf format the dispatcher's collection_desc() reads.
collection_budget() {
    local conf="$SCRIPT_DIR/../collections/$1.conf" v=""
    [[ -f "$conf" ]] && v=$(sed -nE 's/^[[:space:]]*budget_pct[[:space:]]*=[[:space:]]*([0-9.]+).*/\1/p' "$conf" | head -1)
    printf '%s' "${v:-$THRESH}"
}

# Measure one target. Stores median/min/pct/ratio into RESULTS; the baseline
# call must run first so BASELINE_MEDIAN is set for the ratio of every scene.
# $3 = budget % for this scene's collection (defaults to the global THRESH).
run_one() {
    local label="$1" arg="$2" thr="${3:-$THRESH}"
    local out median min pct ratio verdict
    out=$("$BIN" "$arg" "$W" "$H" "$FRAMES" "$TRIALS" 2>/dev/null) || {
        printf "  %-14s %12s\n" "$label" "ERROR"
        return 1
    }
    median=$(printf '%s\n' "$out" | sed -n 's/.*median_ms=\([0-9.]*\).*/\1/p')
    min=$(printf '%s\n' "$out" | sed -n 's/.*min_ms=\([0-9.]*\).*/\1/p')
    pct=$(awk -v m="$median" -v b="$BUDGET_MS" 'BEGIN{ printf "%.2f", m/b*100 }')

    if [[ "$label" == "baseline" ]]; then
        BASELINE_MEDIAN="$median"
        ratio="1.00"
        verdict="(reference)"
    else
        ratio=$(awk -v m="$median" -v b="$BASELINE_MEDIAN" \
            'BEGIN{ if (b > 0) printf "%.2f", m/b; else printf "n/a" }')
        if awk -v p="$pct" -v t="$thr" 'BEGIN{ exit !(p > t) }'; then
            verdict="OVER (>${thr}%)"
            over_count=$((over_count + 1))
        else
            verdict="ok"
        fi
    fi

    printf "  %-14s %12s %12s %9s%% %8s   %s\n" "$label" "$median" "$min" "$pct" "$ratio" "$verdict"
    RESULTS="${RESULTS}${label} ${median} ${min} ${pct} ${ratio}"$'\n'
}

run_one "baseline" "--baseline"
while IFS= read -r s; do
    [[ -n "$s" ]] || continue
    sp="$(scene_path "$SHADERS_DIR" "$s")"
    coll="$(basename "$(dirname "$sp")")"
    run_one "$s" "$sp" "$(collection_budget "$coll")"
done <<< "$SCENES"

echo

# --- Write JSON output if requested -----------------------------------------
write_json() {
    local dest="$1"
    {
        printf '[\n'
        local first=1
        while IFS=' ' read -r label median min pct ratio; do
            [[ -n "$label" ]] || continue
            [[ "$first" -eq 1 ]] || printf ',\n'
            first=0
            printf '  {"scene": "%s", "median_ms": %s, "min_ms": %s, "pct_budget": %s, "ratio_to_baseline": %s}' \
                "$label" "$median" "$min" "$pct" "$ratio"
        done <<< "$RESULTS"
        printf '\n]\n'
    } > "$dest"
}

# --- --update-baseline: write baseline.json and exit without gating ----------
if [[ "$UPDATE_BASELINE" -eq 1 ]]; then
    write_json "$BASELINE_FILE"
    echo "baseline written to $BASELINE_FILE (gating skipped)."
    exit 0
fi

if [[ -n "$JSON_OUT" ]]; then
    write_json "$JSON_OUT"
    echo "JSON results written to $JSON_OUT."
fi

# --- Regression guard against the committed baseline -------------------------
regression_count=0
if [[ -f "$BASELINE_FILE" ]]; then
    while IFS=' ' read -r label median min pct ratio; do
        [[ -n "$label" ]] || continue
        [[ "$label" != "baseline" ]] || continue
        # Pull this scene's baseline median from baseline.json. The JSON is
        # written by this very script (one object per line), so a line-oriented
        # awk extraction is safe and avoids a jq dependency.
        base_median=$(awk -v s="\"$label\"" '
            $0 ~ "\"scene\": " s {
                if (match($0, /"median_ms": [0-9.]+/)) {
                    v = substr($0, RSTART, RLENGTH)
                    sub(/"median_ms": /, "", v)
                    print v
                }
            }' "$BASELINE_FILE")
        if [[ -z "$base_median" ]]; then
            continue  # scene not in baseline (newly added) — nothing to compare
        fi
        # FAIL if current median is slower than baseline by > REGRESSION_PCT %.
        if awk -v cur="$median" -v base="$base_median" -v pct="$REGRESSION_PCT" \
            'BEGIN{ exit !(base > 0 && cur > base * (1.0 + pct/100.0)) }'; then
            delta=$(awk -v cur="$median" -v base="$base_median" \
                'BEGIN{ printf "%.1f", (cur/base - 1.0) * 100.0 }')
            echo "REGRESSION: $label is ${delta}% slower than baseline (${median} ms vs ${base_median} ms, limit ${REGRESSION_PCT}%)." >&2
            regression_count=$((regression_count + 1))
        fi
    done <<< "$RESULTS"
fi

# --- Final verdict ----------------------------------------------------------
status=0
if [[ "$over_count" -gt 0 ]]; then
    echo "RESULT: $over_count scene(s) exceed their collection's frame budget." >&2
    status=1
fi
if [[ "$regression_count" -gt 0 ]]; then
    echo "FAIL: $regression_count scene(s) regressed > ${REGRESSION_PCT}% against bench/baseline.json." >&2
    status=1
fi
if [[ "$status" -eq 0 ]]; then
    msg="RESULT: all scenes within their collection's frame budget"
    [[ -f "$BASELINE_FILE" ]] && msg="$msg and within ${REGRESSION_PCT}% of baseline"
    echo "${msg}."
fi
exit "$status"
