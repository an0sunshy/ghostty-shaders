#!/usr/bin/env bash
# run-tests.sh — unit tests for the pure decision logic in bin/.
#
# No framework, no dependencies: the scripts under test return early when
# sourced (see the sourced-return guard in each), so this harness sources
# them and asserts on their pure functions directly. Runs on macOS and
# Linux; CI runs it on ubuntu-latest.
#
#   tests/run-tests.sh        # exits non-zero if any assertion fails

set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
PASS=0
FAIL=0

t() {  # t <description> <expected> <actual>
    local desc="$1" want="$2" got="$3"
    if [[ "$got" == "$want" ]]; then
        PASS=$((PASS + 1)); printf 'ok   %s\n' "$desc"
    else
        FAIL=$((FAIL + 1)); printf 'FAIL %s\n     want: %q\n     got:  %q\n' "$desc" "$want" "$got"
    fi
}

t_close() {  # t_close <description> <expected> <actual> <abs-tolerance>
    local desc="$1" want="$2" got="$3" tol="$4"
    # awk coerces a non-numeric/empty string to 0, which would make
    # zero-expected assertions pass vacuously when the function under test
    # produced no output at all. Require a numeric literal first.
    if [[ ! "$got" =~ ^-?[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?$ ]]; then
        FAIL=$((FAIL + 1)); printf 'FAIL %s\n     want: %s ±%s\n     got:  %q (not numeric)\n' "$desc" "$want" "$tol" "$got"
        return
    fi
    if awk -v a="$want" -v b="$got" -v t="$tol" 'BEGIN{d=a-b; if (d<0) d=-d; exit !(d<=t)}'; then
        PASS=$((PASS + 1)); printf 'ok   %s\n' "$desc"
    else
        FAIL=$((FAIL + 1)); printf 'FAIL %s\n     want: %s ±%s\n     got:  %s\n' "$desc" "$want" "$tol" "$got"
    fi
}

# Source the scripts under test (each stops at its sourced-return guard).
# They are shellcheck'd in their own right; no need to follow them here.
# Their `set -e` would abort this harness on the first failed assertion;
# turn it back off.
# shellcheck disable=SC1091
source "$REPO_ROOT/bin/ghostty-weather-poll"
# shellcheck disable=SC1091
source "$REPO_ROOT/bin/ghostty-weather-swap"
set +e +o pipefail

# --- pick_scene: the full WMO mapping table from the README ------------------
# 2>/dev/null drops the diagnostic log() on the unknown-code path; these
# also pin the regression where that log line used to leak into stdout and
# corrupt the captured scene name.

while read -r code day want; do
    t "pick_scene $code (is_day=$day) -> $want" "$want" "$(pick_scene "$code" "$day" 2>/dev/null)"
done <<'EOF'
0 1 clear-day
0 0 clear-night
1 1 clear-day
1 0 clear-night
2 1 cloudy
3 1 cloudy
45 1 cloudy
48 0 cloudy
51 1 rain
53 1 rain
55 1 rain
56 1 rain
57 1 rain
61 1 rain
63 0 rain
65 1 rain
66 1 rain
67 1 rain
80 1 rain
81 1 rain
82 0 rain
71 1 snow
73 1 snow
75 1 snow
77 0 snow
85 1 snow
86 1 snow
95 1 thunderstorm
96 0 thunderstorm
99 1 thunderstorm
33 1 clear-day
33 0 clear-night
EOF

# Unknown codes must emit EXACTLY the scene name on stdout (the diagnostic
# goes to stderr) — a multi-line result here would reach swap as a garbage
# scene path.
t "pick_scene unknown code emits a single clean line" \
  "clear-day" "$(pick_scene 12345 1 2>/dev/null)"

# --- scene_by_hour: offline fallback boundaries -------------------------------

while read -r hour want; do
    t "scene_by_hour $hour -> $want" "$want" "$(scene_by_hour "$hour")"
done <<'EOF'
00 clear-night
05 clear-night
06 clear-day
08 clear-day
09 clear-day
12 clear-day
17 clear-day
18 clear-night
23 clear-night
EOF

# --- read_env_var: .env parsing without sourcing user config as code ----------

ENV_FIXTURE="$(mktemp "${TMPDIR:-/tmp}/gw-test-env.XXXXXX")"
trap 'rm -f "$ENV_FIXTURE"' EXIT
cat > "$ENV_FIXTURE" <<'EOF'
# comment line
LAT=47.6062
  LON = -122.3321
LOCATION="Seattle, WA"
export PAUSE_ON_BATTERY=true
CITY=San Francisco  # trailing comment
DUP=first
DUP=second
#DISABLED=should-not-match
EOF

t "read_env_var plain value"            "47.6062"       "$(read_env_var LAT "$ENV_FIXTURE")"
t "read_env_var spaces around ="        "-122.3321"     "$(read_env_var LON "$ENV_FIXTURE")"
t "read_env_var double-quoted value"    "Seattle, WA"   "$(read_env_var LOCATION "$ENV_FIXTURE")"
t "read_env_var export prefix"          "true"          "$(read_env_var PAUSE_ON_BATTERY "$ENV_FIXTURE")"
t "read_env_var strips trailing comment" "San Francisco" "$(read_env_var CITY "$ENV_FIXTURE")"
t "read_env_var first match wins"       "first"         "$(read_env_var DUP "$ENV_FIXTURE")"
t "read_env_var commented-out key"      ""              "$(read_env_var DISABLED "$ENV_FIXTURE")"
t "read_env_var missing key"            ""              "$(read_env_var NOPE "$ENV_FIXTURE")"
read_env_var NOPE /nonexistent-file >/dev/null 2>&1
t "read_env_var missing file -> rc 1"   "1"             "$?"

# --- moon_phase_at: synodic anchors -----------------------------------------
# Reference new moon: 2000-01-06 18:14 UTC = unix 946794840.
# Synodic period: 29.530588 d = 2551442.8 s.

REF=946794840
t_close "moon_phase_at reference new moon -> 0"     0    "$(moon_phase_at $REF)"                 0.000001
t_close "moon_phase_at +quarter synodic -> 0.25"    0.25 "$(moon_phase_at $((REF + 637861)))"    0.001
t_close "moon_phase_at +half synodic -> 0.5 (full)" 0.5  "$(moon_phase_at $((REF + 1275721)))"   0.001
t_close "moon_phase_at +full synodic +1h -> ~0"     0.0014 "$(moon_phase_at $((REF + 2551443 + 3600)))" 0.001
t_close "moon_phase_at pre-reference stays in [0,1)" 0.5 "$(moon_phase_at $((REF - 1275721)))"   0.001
# Rounding edge: ~1.3s before an exact synodic wrap, %.6f rounds to
# 1.000000 — the guard must map it to 0, never emit "1" (old %.6g did).
t "moon_phase_at wrap edge stays in [0,1)" "0.000000" "$(moon_phase_at $((REF + 2551442)))"

# --- normalize_is_day: flag normalization + clock fallback --------------------

while read -r raw hour want; do
    t "normalize_is_day '$raw' hour=$hour -> $want" "$want" \
      "$(normalize_is_day "$raw" "$hour")"
done <<'EOF'
1 12 1.0
1.0 12 1.0
true 12 1.0
yes 12 1.0
TRUE 12 1.0
Yes 12 1.0
0 12 0.0
0.0 12 0.0
false 12 0.0
no 12 0.0
FALSE 12 0.0
No 12 0.0
maybe 12 1.0
EOF

# Empty input falls back to the clock heuristic...
t "normalize_is_day '' hour=12 -> 1.0" "1.0" "$(normalize_is_day "" 12)"
t "normalize_is_day '' hour=05 -> 0.0" "0.0" "$(normalize_is_day "" 05)"

# ...which must agree with the poller's scene_by_hour at EVERY hour — these
# two day-window definitions live in different scripts and drifting apart
# would mean a manual swap dims differently than the offline poll fallback.
mismatch=""
for i in 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23; do
    h="$(printf '%02d' "$i")"
    if [[ "$(scene_by_hour "$h")" == "clear-day" ]]; then want_day="1.0"; else want_day="0.0"; fi
    [[ "$(normalize_is_day "" "$h")" == "$want_day" ]] || mismatch="$mismatch$h "
done
t "normalize_is_day clock fallback agrees with scene_by_hour all 24h" "" "$mismatch"

# --- seconds_since_midnight: zero-padded inputs (octal trap) -------------------

t "seconds_since_midnight 00:00:00" "0"     "$(seconds_since_midnight 00 00 00)"
t "seconds_since_midnight 08:09:07" "29347" "$(seconds_since_midnight 08 09 07)"
t "seconds_since_midnight 12:00:00" "43200" "$(seconds_since_midnight 12 00 00)"
t "seconds_since_midnight 23:59:59" "86399" "$(seconds_since_midnight 23 59 59)"

# --- web gallery registry ------------------------------------------------------
# The gallery derives its scene list from index.html's picker buttons; a
# scene shipped in shaders/scenes/ but missing a button would silently
# never appear on the Pages demo (and vice versa for a deleted scene).

fs_scenes="$(cd "$REPO_ROOT/shaders/scenes" && for f in *.glsl; do printf '%s ' "${f%.glsl}"; done)"
html_scenes="$(grep -oE 'data-scene="[^"]+"' "$REPO_ROOT/web/index.html" | sed -E 's/.*"([^"]+)"/\1/' | sort | tr '\n' ' ')"
t "web gallery picker offers exactly the shipped scenes" "$fs_scenes" "$html_scenes"

# --- summary -------------------------------------------------------------------

echo
echo "tests: $((PASS + FAIL)) · pass: $PASS · fail: $FAIL"
[[ $FAIL -eq 0 ]]
