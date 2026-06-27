#!/usr/bin/env bash
# run-tests.sh — unit tests for the pure decision logic in
# libexec/ghostty-shaders/.
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
source "$REPO_ROOT/libexec/ghostty-shaders/weather"
# shellcheck disable=SC1091
source "$REPO_ROOT/libexec/ghostty-shaders/apply"
# The matcher engine + its input providers (each returns at its own guard,
# exposing only pure functions: time_phase, season_for, weather_class,
# days_until, select_conf_num, score_scenes, sample_scene).
# shellcheck disable=SC1091
source "$REPO_ROOT/libexec/ghostty-shaders/select"
for _p in "$REPO_ROOT"/libexec/ghostty-shaders/providers/*; do
    # shellcheck disable=SC1090
    source "$_p"
done
set +e +o pipefail

# (The legacy weather poller's pick_scene / scene_by_hour mapping was removed
# with the weather scenes; the matcher's equivalents — weather_class, time_phase,
# score_scenes — are tested further down.)

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

# ...whose day window is 06:00–17:59. Pin it at EVERY hour so the manual-swap
# dimming boundary can't silently drift.
mismatch=""
for i in 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23; do
    h="$(printf '%02d' "$i")"
    if (( 10#$h >= 6 && 10#$h < 18 )); then want_day="1.0"; else want_day="0.0"; fi
    [[ "$(normalize_is_day "" "$h")" == "$want_day" ]] || mismatch="$mismatch$h "
done
t "normalize_is_day clock fallback day window (06–17) holds all 24h" "" "$mismatch"

# --- seconds_since_midnight: zero-padded inputs (octal trap) -------------------

t "seconds_since_midnight 00:00:00" "0"     "$(seconds_since_midnight 00 00 00)"
t "seconds_since_midnight 08:09:07" "29347" "$(seconds_since_midnight 08 09 07)"
t "seconds_since_midnight 12:00:00" "43200" "$(seconds_since_midnight 12 00 00)"
t "seconds_since_midnight 23:59:59" "86399" "$(seconds_since_midnight 23 59 59)"

# --- web gallery registry ------------------------------------------------------
# The gallery derives its scene list from index.html's picker buttons; a
# scene shipped under shaders/ but missing a button would silently never
# appear on the Pages demo (and vice versa for a deleted scene). scene_names
# is the same discovery the apply/build/bench use (sourced via the apply module).

fs_scenes="$(scene_names "$REPO_ROOT/shaders" | tr '\n' ' ')"
html_scenes="$(grep -oE 'data-scene="[^"]+"' "$REPO_ROOT/web/index.html" | sed -E 's/.*"([^"]+)"/\1/' | sort | tr '\n' ' ')"
t "web gallery picker offers exactly the shipped scenes" "$fs_scenes" "$html_scenes"

# --- ghostty_pids_from_ps: the Ghostty process matcher -------------------------
# Regression for the macOS bug where `pgrep -x ghostty` matched nothing for a
# .app-bundle launch (comm is the full exec path, which pgrep truncates to 16
# chars), so apply/toggle silently never signalled Ghostty to reload. They now
# parse `ps -o pid=,comm=` and match the exact comm basename, via the shared
# scripts/ghostty-process.sh (sourced here through the apply module). Pin that:
# a full path matches, a bare `ghostty` matches, spaces in the path are
# tolerated, and the match is EXACT so the `ghostty-shaders` helper and a
# `notghostty` binary are excluded (a substring match would catch them).
#
# CRITICAL: real `ps -axo pid=,comm=` RIGHT-JUSTIFIES the pid column, so every
# line starts with leading spaces. These inputs reproduce that exactly — an
# earlier version used unpadded lines and silently passed while the bare-comm
# case (Linux / CLI launch) was actually broken.

t "ghostty_pids_from_ps full .app path -> pid" "1306" \
  "$(printf '%s\n' ' 1306 /Applications/Ghostty.app/Contents/MacOS/ghostty' | ghostty_pids_from_ps)"
t "ghostty_pids_from_ps padded bare comm 'ghostty' -> pid" "2000" \
  "$(printf '%s\n' '  2000 ghostty' | ghostty_pids_from_ps)"
t "ghostty_pids_from_ps tolerates spaces in path" "5000" \
  "$(printf '%s\n' '  5000 /Apps/My Stuff/ghostty' | ghostty_pids_from_ps)"
t "ghostty_pids_from_ps excludes the ghostty-shaders helper" "" \
  "$(printf '%s\n' '  3000 /Users/me/.local/bin/ghostty-shaders' | ghostty_pids_from_ps)"
t "ghostty_pids_from_ps is exact, not substring (notghostty)" "" \
  "$(printf '%s\n' '  6000 /usr/bin/notghostty' | ghostty_pids_from_ps)"
t "ghostty_pids_from_ps also matches an unpadded line" "7000" \
  "$(printf '%s\n' '7000 ghostty' | ghostty_pids_from_ps)"
t "ghostty_pids_from_ps empty input -> empty" "" \
  "$(printf '' | ghostty_pids_from_ps)"
t "ghostty_pids_from_ps filters a mixed ps table" "1306
2000" "$(printf '%s\n' \
  ' 1306 /Applications/Ghostty.app/Contents/MacOS/ghostty' \
  '  2000 ghostty' \
  '  3000 /usr/bin/ghostty-shaders' \
  '  4000 bash' | ghostty_pids_from_ps)"

# The matcher now lives in exactly one place (scripts/ghostty-process.sh), so
# it cannot drift between apply and toggle. Pin that both subcommands actually
# source it — a copy-paste regression would reintroduce the macOS bug above.
sources_matcher() { grep -qF 'scripts/ghostty-process.sh' "$1" && echo yes || echo no; }
t "apply sources the shared process matcher"  "yes" "$(sources_matcher "$REPO_ROOT/libexec/ghostty-shaders/apply")"
t "toggle sources the shared process matcher" "yes" "$(sources_matcher "$REPO_ROOT/libexec/ghostty-shaders/toggle")"

# --- toggle lifecycle ----------------------------------------------------------
# Regression for the `set -e` abort that left active.conf shaderless while the
# pause marker was never written, so --status wrongly reported "active". Drive
# the real `ghostty-shaders` dispatcher as a subprocess against a throwaway HOME
# (all its state lives under $HOME), exercising the full router→libexec path. A
# stub `ps` on PATH makes the matcher find no Ghostty — that is the exact path
# that used to abort do_pause, and it stops the test from signalling a real
# Ghostty that may be running on the dev machine.

GS="$REPO_ROOT/bin/ghostty-shaders"
TT_HOME="$(mktemp -d)"
ACT="$TT_HOME/.config/ghostty-shaders/active.conf"
MRK="$TT_HOME/Library/Caches/ghostty-shaders/paused"
STUB="$TT_HOME/stubbin"
mkdir -p "$STUB"
printf '#!/bin/sh\nexit 0\n' > "$STUB/ps"   # pretend no Ghostty is running
chmod +x "$STUB/ps"

run_tt()    { HOME="$TT_HOME" PATH="$STUB:$PATH" "$@"; }
has_shader() { if grep -q '^custom-shader' "$ACT" 2>/dev/null; then echo shader; else echo none; fi; }
has_marker() { if [[ -f $MRK ]]; then echo yes; else echo no; fi; }

run_tt "$GS" apply jing-ye-si >/dev/null 2>&1
t "lifecycle: apply seeds an active shader include" "shader" "$(has_shader)"
t "lifecycle: active state has no pause marker"     "no"     "$(has_marker)"
t "lifecycle: toggle --status reports active"       "active" "$(run_tt "$GS" toggle --status | head -n 1)"

run_tt "$GS" toggle --pause >/dev/null
t "lifecycle: --pause writes the pause marker"      "yes"    "$(has_marker)"
t "lifecycle: --pause leaves a shaderless include"  "none"   "$(has_shader)"
t "lifecycle: toggle --status reports paused"       "paused" "$(run_tt "$GS" toggle --status | head -n 1)"

run_tt "$GS" toggle --pause >/dev/null
t "lifecycle: --pause is idempotent (still paused)" "yes"    "$(has_marker)"

run_tt "$GS" toggle --resume >/dev/null 2>&1
t "lifecycle: --resume clears the pause marker"     "no"     "$(has_marker)"
t "lifecycle: --resume restores a shader include"   "shader" "$(has_shader)"

run_tt "$GS" toggle >/dev/null
t "lifecycle: bare toggle from active pauses"       "yes"    "$(has_marker)"

[[ -n ${TT_HOME:-} && -d $TT_HOME ]] && rm -rf "$TT_HOME"

# --- install.sh migration (ghostty-weather → ghostty-shaders) -------------------
# Regression for the data-loss bug where cmd_install pre-created the new config
# dir before migrate ran, so the move was skipped and the user's location was
# replaced by a blank seeded config. Drive the real install.sh against a
# throwaway HOME seeded with a pre-rename install, with launchctl/ps stubbed so
# nothing touches the real machine. Linux-portable (uses the Linux Ghostty
# config path; mv/sed/grep only).

MIG_HOME="$(mktemp -d)"
mkdir -p "$MIG_HOME/.config/ghostty-weather" \
         "$MIG_HOME/Library/Caches/ghostty-weather" \
         "$MIG_HOME/Library/Logs" "$MIG_HOME/Library/LaunchAgents" \
         "$MIG_HOME/.local/bin" "$MIG_HOME/stubbin"
# Compute the Ghostty config path exactly as install.sh does, and pin
# XDG_CONFIG_HOME under the sandbox so the Linux branch can't escape it.
case "$(uname -s)" in
    Darwin) MIG_GCONF="$MIG_HOME/Library/Application Support/com.mitchellh.ghostty/config" ;;
    *)      MIG_GCONF="$MIG_HOME/.config/ghostty/config" ;;
esac
mkdir -p "$(dirname "$MIG_GCONF")"
MIG_ROT="$MIG_HOME/Library/Caches/ghostty-weather/weather-1781299360-52083.glsl"
printf '// rotated scene\n' > "$MIG_ROT"
cat > "$MIG_HOME/.config/ghostty-weather/active.conf" <<EOF
# Generated by ghostty-weather-swap; do not edit by hand.
# Active scenario: clear-day  (2026-06-12T00:00:00Z)
custom-shader = $MIG_ROT
EOF
printf 'LAT=47.6062\nLON=-122.3321\n' > "$MIG_HOME/.config/ghostty-weather/config.env"
printf '{"lat":47.6,"lon":-122.3,"city":"Seattle"}\n' > "$MIG_HOME/.config/ghostty-weather/location.json"
printf 'old log\n' > "$MIG_HOME/Library/Logs/ghostty-weather-poll.log"
printf '<plist/>\n' > "$MIG_HOME/Library/LaunchAgents/dev.ghostty-weather.poll.plist"
cat > "$MIG_GCONF" <<EOF
font-family = "Berkeley Mono"

# ghostty-weather (managed by ~/dev/ghostty-weather)
config-file = ?$MIG_HOME/.config/ghostty-weather/active.conf
EOF
ln -sf /dev/null "$MIG_HOME/.local/bin/ghostty-weather-swap"
printf '#!/bin/sh\nexit 0\n' > "$MIG_HOME/stubbin/launchctl"; chmod +x "$MIG_HOME/stubbin/launchctl"
printf '#!/bin/sh\nexit 0\n' > "$MIG_HOME/stubbin/ps"; chmod +x "$MIG_HOME/stubbin/ps"

run_mig() { HOME="$MIG_HOME" XDG_CONFIG_HOME="$MIG_HOME/.config" PATH="$MIG_HOME/stubbin:$PATH" bash "$REPO_ROOT/install.sh" >/dev/null 2>&1; }
run_mig

t "migrate: new config dir created"         "yes" "$([[ -d $MIG_HOME/.config/ghostty-shaders ]] && echo yes || echo no)"
t "migrate: old config dir moved away"      "yes" "$([[ ! -d $MIG_HOME/.config/ghostty-weather ]] && echo yes || echo no)"
t "migrate: user location config preserved" "47.6062" "$(read_env_var LAT "$MIG_HOME/.config/ghostty-shaders/config.env")"
t "migrate: location.json preserved"        "yes" "$([[ -f $MIG_HOME/.config/ghostty-shaders/location.json ]] && echo yes || echo no)"
t "migrate: rotated scene file moved"       "yes" "$([[ -f $MIG_HOME/Library/Caches/ghostty-shaders/weather-1781299360-52083.glsl ]] && echo yes || echo no)"
t "migrate: active.conf repointed to new cache" "yes" \
  "$(grep -q 'Caches/ghostty-shaders' "$MIG_HOME/.config/ghostty-shaders/active.conf" && ! grep -q 'Caches/ghostty-weather' "$MIG_HOME/.config/ghostty-shaders/active.conf" && echo yes || echo no)"
t "migrate: log renamed"                    "yes" "$([[ -f $MIG_HOME/Library/Logs/ghostty-shaders-poll.log && ! -f $MIG_HOME/Library/Logs/ghostty-weather-poll.log ]] && echo yes || echo no)"
t "migrate: old plist removed"              "yes" "$([[ ! -f $MIG_HOME/Library/LaunchAgents/dev.ghostty-weather.poll.plist ]] && echo yes || echo no)"
t "migrate: ghostty include rewritten"      "yes" \
  "$(grep -qF "ghostty-shaders/active.conf" "$MIG_GCONF" && ! grep -qF "ghostty-weather/active.conf" "$MIG_GCONF" && echo yes || echo no)"
t "migrate: unrelated ghostty config kept"  "yes" "$(grep -qF 'Berkeley Mono' "$MIG_GCONF" && echo yes || echo no)"
t "migrate: single new symlink present"     "yes" "$([[ -L $MIG_HOME/.local/bin/ghostty-shaders ]] && echo yes || echo no)"
t "migrate: legacy symlink removed"         "yes" "$([[ ! -e $MIG_HOME/.local/bin/ghostty-weather-swap ]] && echo yes || echo no)"

# Idempotent: a second run must not duplicate the include or error.
run_mig
t "migrate: re-run keeps include un-duplicated" "1" "$(grep -cF 'ghostty-shaders/active.conf' "$MIG_GCONF")"

[[ -n ${MIG_HOME:-} && -d $MIG_HOME ]] && rm -rf "$MIG_HOME"

# --- static selection (use / random) + collections -----------------------------
# `use`/`random` pin a scene so the cron weather poller stands down; a manual
# `weather` clears the pin. Drive the real dispatcher against a throwaway HOME
# with ps/curl/launchctl stubbed (no real machine state, no network).

SEL_HOME="$(mktemp -d)"; mkdir -p "$SEL_HOME/stubbin"
printf '#!/bin/sh\nexit 0\n' > "$SEL_HOME/stubbin/ps";        chmod +x "$SEL_HOME/stubbin/ps"
printf '#!/bin/sh\nexit 0\n' > "$SEL_HOME/stubbin/launchctl"; chmod +x "$SEL_HOME/stubbin/launchctl"
printf '#!/bin/sh\nexit 1\n' > "$SEL_HOME/stubbin/curl";      chmod +x "$SEL_HOME/stubbin/curl"
SEL_FILE="$SEL_HOME/.config/ghostty-shaders/selection"
SEL_ACT="$SEL_HOME/.config/ghostty-shaders/active.conf"
run_sel() { HOME="$SEL_HOME" PATH="$SEL_HOME/stubbin:$PATH" "$GS" "$@"; }

t "list names the poems collection" "poems" \
  "$(run_sel list 2>/dev/null | grep -oE '^  poems' | awk '{print $1}')"
t "list <collection> emits that collection's scenes" "24" \
  "$(run_sel list poems 2>/dev/null | grep -c .)"

run_sel use jing-ye-si >/dev/null 2>&1
t "use pins the scene"                "jing-ye-si" "$(cat "$SEL_FILE" 2>/dev/null)"
t "use applies the scene"             "shader"     "$(grep -q '^custom-shader' "$SEL_ACT" 2>/dev/null && echo shader || echo none)"
run_sel use not-a-real-scene >/dev/null 2>&1
t "use rejects an unknown scene (rc)" "1"          "$?"
t "use rejection leaves prior pin"    "jing-ye-si" "$(cat "$SEL_FILE" 2>/dev/null)"

run_sel random poems >/dev/null 2>&1
sel_pick="$(cat "$SEL_FILE" 2>/dev/null)"
t "random <collection> pins a scene from it" "yes" \
  "$(scene_path "$REPO_ROOT/shaders/poems" "$sel_pick" >/dev/null 2>&1 && echo yes || echo no)"

# --- select --cron poller guards (Phase 2) ------------------------------------
# The matcher poller stands down under a static pin, exactly like the legacy one.
mkdir -p "$SEL_HOME/Library/Caches/ghostty-shaders"
printf 'jing-ye-si\n' > "$SEL_FILE"
rm -f "$SEL_ACT"
HOME="$SEL_HOME" PATH="$SEL_HOME/stubbin:$PATH" "$REPO_ROOT/libexec/ghostty-shaders/select" --cron >/dev/null 2>&1
t "select --cron stands down under a static pin" "jing-ye-si" "$(cat "$SEL_FILE" 2>/dev/null)"
t "select --cron wrote no active include"        "none"       "$([[ -f $SEL_ACT ]] && echo some || echo none)"

# ... and under a manual pause marker (no swap).
rm -f "$SEL_FILE" "$SEL_ACT"
touch "$SEL_HOME/Library/Caches/ghostty-shaders/paused"
HOME="$SEL_HOME" PATH="$SEL_HOME/stubbin:$PATH" "$REPO_ROOT/libexec/ghostty-shaders/select" --cron >/dev/null 2>&1
t "select --cron stands down when paused" "none" "$([[ -f $SEL_ACT ]] && echo some || echo none)"
rm -f "$SEL_HOME/Library/Caches/ghostty-shaders/paused"

# A manual `select` (auto-match now) clears any static pin and applies a poem.
printf 'jing-ye-si\n' > "$SEL_FILE"
HOME="$SEL_HOME" PATH="$SEL_HOME/stubbin:$PATH" GHOSTTY_SHADERS_SELECT_TEMP=0 \
  GHOSTTY_SHADERS_FACTS='{"weather":"snow","phase":"night","season":"winter","temp_c":-3}' \
  "$REPO_ROOT/libexec/ghostty-shaders/select" >/dev/null 2>&1
t "manual select clears the static pin" "gone" "$([[ -f $SEL_FILE ]] && echo present || echo gone)"
t "manual select applied the matched poem" "ye-xue" \
  "$(grep -oE 'Active scen[a-z]*: [a-z-]+' "$SEL_ACT" 2>/dev/null | awk '{print $NF}')"

[[ -n ${SEL_HOME:-} && -d $SEL_HOME ]] && rm -rf "$SEL_HOME"

# --- poem display titles (collections/poems.titles) ----------------------------
# Every poems/ scene must have an English title row, and the gallery's poem-button
# `title=` tooltips must match that file — so the CLI (`list poems`) and the demo
# can't drift from each other.

pt_file="$REPO_ROOT/collections/poems.titles"
pt_names="$(awk -F'|' '!/^#/ && NF==3 {print $1}' "$pt_file" | sort | tr '\n' ' ')"
fs_poems="$(scene_names "$REPO_ROOT/shaders/poems" | tr '\n' ' ')"
t "every poem scene has a poems.titles row" "$fs_poems" "$pt_names"

pt_expected="$(awk -F'|' '!/^#/ && NF==3 {print $1 "\t" $2 " — " $3}' "$pt_file" | sort)"
html_titles="$(grep -oE 'data-scene="[^"]+"[[:space:]]+title="[^"]+"' "$REPO_ROOT/web/index.html" \
  | sed -E 's/data-scene="([^"]+)"[[:space:]]+title="([^"]+)"/\1\t\2/' | sort)"
t "gallery poem tooltips match poems.titles" "$pt_expected" "$html_titles"

# --- matcher: 20-time time_phase ----------------------------------------------
while IFS=' ' read -r hh want; do
    [[ -z $hh ]] && continue
    t "time_phase $hh → $want" "$want" "$(time_phase "$hh")"
done <<'EOF'
00 night
04 night
05 dawn
07 dawn
08 day
12 day
16 day
17 dusk
20 dusk
21 night
23 night
EOF

# --- matcher: 30-season season_for (hemisphere-aware) -------------------------
t "season_for north Jun → summer" "summer" "$(season_for 06 40.7)"
t "season_for north Dec → winter" "winter" "$(season_for 12 40)"
t "season_for north Mar → spring" "spring" "$(season_for 03 51)"
t "season_for north Sep → autumn" "autumn" "$(season_for 09 35)"
t "season_for south Jun → winter" "winter" "$(season_for 06 -33.8)"
t "season_for south Dec → summer" "summer" "$(season_for 12 -33)"
t "season_for equator Jun → summer (north default)" "summer" "$(season_for 06 0)"

# --- matcher: 10-weather weather_class (WMO code → class) ----------------------
t "weather_class 0  → clear" "clear" "$(weather_class 0)"
t "weather_class 2  → cloud" "cloud" "$(weather_class 2)"
t "weather_class 48 → fog"   "fog"   "$(weather_class 48)"
t "weather_class 61 → rain"  "rain"  "$(weather_class 61)"
t "weather_class 71 → snow"  "snow"  "$(weather_class 71)"
t "weather_class 95 → storm" "storm" "$(weather_class 95)"
t "weather_class 999 → clear (unknown)" "clear" "$(weather_class 999)"

# --- matcher: 40-festival days_until ------------------------------------------
t "days_until upcoming (58d)" "58" "$(days_until 2026-06-22 2026-08-19)"
t "days_until tomorrow (1d)"  "1"  "$(days_until 2026-09-24 2026-09-25)"
t "days_until today (0d)"     "0"  "$(days_until 2026-09-25 2026-09-25)"
t "days_until passed (-1d)"   "-1" "$(days_until 2026-09-26 2026-09-25)"
# Integration: the provider picks the nearest upcoming festival from the table.
fest_out="$(GHOSTTY_SHADERS_TODAY=2026-09-24 "$REPO_ROOT/libexec/ghostty-shaders/providers/40-festival")"
t "40-festival picks mid-autumn 1 day out" \
  '{"festival":"mid-autumn","days_to_festival":1}' "$fest_out"

# --- matcher: score_scenes (the rule engine) ----------------------------------
# Snowy winter night: the night-snow poem (winter+night+snow) tops the list.
snow_top="$(printf '%s' '{"weather":"snow","phase":"night","season":"winter","temp_c":-3}' \
  | score_scenes | sort -t"$(printf '\t')" -k2 -nr | head -1 | cut -f1)"
t "score_scenes snowy night top = ye-xue" "ye-xue" "$snow_top"
# Veto: a warm clear day removes every snow-tagged scene from candidacy.
warm_snow="$(printf '%s' '{"weather":"clear","phase":"day","temp_c":24}' \
  | score_scenes | cut -f1 | grep -cE '^(jiang-xue|ye-xue|bai-xue-ge|feng-xue-su)$')"
t "score_scenes vetoes snow scenes when warm" "0" "$warm_snow"
# Offline (empty facts): all 24 poems remain candidates at score 0.
empty_n="$(printf '%s' '{}' | score_scenes | wc -l | tr -d ' ')"
t "score_scenes empty facts → 24 candidates" "24" "$empty_n"

# --- matcher: sample_scene (deterministic weighted pick) ----------------------
t "sample_scene argmax (temp 0)" "b" "$(printf 'a\t5\nb\t10\nc\t3\n' | sample_scene 0 0.5 '' 2.0)"
t "sample_scene argmax breaks ties to first" "a" "$(printf 'a\t10\nb\t10\n' | sample_scene 0 0.5 '' 2.0)"
t "sample_scene recency penalty drops a below equal-scored b" \
  "b" "$(printf 'a\t10\nb\t10\n' | sample_scene 0 0.5 'a' 2.0)"
t "sample_scene weighted draw low uniform → a" "a" "$(printf 'a\t0\nb\t0\n' | sample_scene 1 0.4 '' 0)"
t "sample_scene weighted draw high uniform → b" "b" "$(printf 'a\t0\nb\t0\n' | sample_scene 1 0.6 '' 0)"

# --- matcher: data consistency (index/rules ↔ scenes) -------------------------
idx_scenes="$(jq -r '.scenes | keys[]' "$REPO_ROOT/collections/poems.index.json" | sort | tr '\n' ' ')"
fs_poems="$(scene_names "$REPO_ROOT/shaders/poems" | tr '\n' ' ')"
t "poems.index covers exactly the poem scenes" "$fs_poems" "$idx_scenes"

rule_tags="$(jq -r '[.rules[] | ((.boost // {}) | keys[]), ((.veto // [])[])] | unique[]' \
  "$REPO_ROOT/collections/poems.rules.json" | sort)"
scene_tags="$(jq -r '[.scenes[].tags[]] | unique[]' "$REPO_ROOT/collections/poems.index.json" | sort)"
unknown_tags="$(comm -23 <(printf '%s\n' "$rule_tags") <(printf '%s\n' "$scene_tags") | tr '\n' ' ' | sed -E 's/ +$//')"
t "every rule boost/veto tag exists on some scene" "" "$unknown_tags"

# Data files parse as JSON.
t "poems.index.json parses"  "ok" "$(jq -e . "$REPO_ROOT/collections/poems.index.json" >/dev/null 2>&1 && echo ok || echo bad)"
t "poems.rules.json parses"  "ok" "$(jq -e . "$REPO_ROOT/collections/poems.rules.json" >/dev/null 2>&1 && echo ok || echo bad)"
t "festivals.json parses"    "ok" "$(jq -e . "$REPO_ROOT/data/festivals.json" >/dev/null 2>&1 && echo ok || echo bad)"

# --- location-lib.sh: the shared extraction reads config faithfully -----------
ll_env="$(mktemp)"
printf 'LAT=12.5\nLON=-7.0\n' > "$ll_env"
ll_lat="$( source "$REPO_ROOT/scripts/location-lib.sh"; read_env_var LAT "$ll_env" )"
t "location-lib read_env_var extracts LAT" "12.5" "$ll_lat"
rm -f "$ll_env"

# --- summary -------------------------------------------------------------------

echo
echo "tests: $((PASS + FAIL)) · pass: $PASS · fail: $FAIL"
[[ $FAIL -eq 0 ]]
