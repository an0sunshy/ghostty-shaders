#!/usr/bin/env bash
# location-lib.sh — the single source of truth for resolving the user's
# location (LAT/LON), shared by the weather provider, the `select` engine, and
# the `weather` subcommand (install/set-city).
#
# Location is read from one of two files (priority order):
#   1. ~/.config/ghostty-shaders/config.env — user-editable, .env format.
#      Set ONE of:  LAT=.. + LON=..  (never calls any 3P) ; or
#                   LOCATION=98101 / "Seattle, WA" (geocoded ONCE, then cached).
#   2. ~/.config/ghostty-shaders/location.json — the geocoded cache (also
#      written by `weather set-city`): {"lat":..,"lon":..,"city":..,"source":..}.
# If neither has a usable value, read_location falls back to NYC with a warning.
#
# This file only defines functions + path constants (no side effects beyond
# those), so it is safe to source under `set -euo pipefail`.

# Path constants. A caller that has already defined these (with the same
# values) is unaffected; we only set them when unset.
: "${LOC_DIR:=$HOME/.config/ghostty-shaders}"
: "${LOC_FILE:=$LOC_DIR/location.json}"
: "${ENV_FILE:=$LOC_DIR/config.env}"
# Fallback location used only if the user hasn't configured one (NYC coords,
# chosen for visibility). The user overrides by writing $LOC_FILE / config.env.
: "${FALLBACK_LAT:=40.7128}"
: "${FALLBACK_LON:=-74.0060}"

# Provide a log() only if the caller hasn't already defined one, so this lib is
# safe to source standalone (e.g. from tests) yet defers to the caller's logger.
if ! command -v log >/dev/null 2>&1; then
    log() { printf '%s ghostty-shaders: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2; }
fi

# Extract a KEY=value pair from an .env-style file. Tolerates surrounding
# whitespace, optional `export `, single/double quotes around the value, and
# trailing comments. Won't execute the file (no `source`) so we don't treat
# user config as code.
read_env_var() {
    local key="$1" file="$2"
    [[ -f $file ]] || return 1
    sed -nE "s/^[[:space:]]*(export[[:space:]]+)?${key}[[:space:]]*=[[:space:]]*\"?([^\"#]+)\"?[[:space:]]*(#.*)?\$/\2/p" "$file" \
        | head -1 \
        | sed -E 's/[[:space:]]+$//'
}

read_json_lat_lon() {
    local file="$1"
    [[ -f $file ]] || return 1
    if command -v jq >/dev/null 2>&1; then
        LAT=$(jq -r '.lat // empty' "$file")
        LON=$(jq -r '.lon // empty' "$file")
    else
        LAT=$(grep -oE '"lat"[[:space:]]*:[[:space:]]*-?[0-9.]+' "$file" | grep -oE '\-?[0-9.]+$')
        LON=$(grep -oE '"lon"[[:space:]]*:[[:space:]]*-?[0-9.]+' "$file" | grep -oE '\-?[0-9.]+$')
    fi
    [[ -n $LAT && -n $LON && $LAT != "null" && $LON != "null" ]]
}

# Geocode a city name or US ZIP via Open-Meteo's /v1/search. Writes a fresh
# location.json and sets LAT/LON plus GEO_NAME. Caller decides when to call
# (only on first-use or when the configured LOCATION changes).
geocode_to_cache() {
    local query="$1"
    log "geocoding '$query' once via Open-Meteo, caching to $LOC_FILE"
    local geo
    geo=$(curl -sf -m 10 -G \
              --data-urlencode "name=$query" \
              --data-urlencode 'count=1' \
              --data-urlencode 'format=json' \
              'https://geocoding-api.open-meteo.com/v1/search' || true)
    local name
    if command -v jq >/dev/null 2>&1; then
        LAT=$(jq -r '.results[0].latitude // empty'  <<<"$geo")
        LON=$(jq -r '.results[0].longitude // empty' <<<"$geo")
        name=$(jq -r '.results[0] | "\(.name), \(.admin1 // "") \(.country // "")"' <<<"$geo" 2>/dev/null)
    else
        LAT=$(echo "$geo" | grep -oE '"latitude"[[:space:]]*:[[:space:]]*-?[0-9.]+' | head -1 | grep -oE '\-?[0-9.]+$')
        LON=$(echo "$geo" | grep -oE '"longitude"[[:space:]]*:[[:space:]]*-?[0-9.]+' | head -1 | grep -oE '\-?[0-9.]+$')
        name=$query
    fi
    if [[ -z $LAT || -z $LON ]]; then
        log "geocoding failed for '$query' (no match)"
        return 1
    fi
    mkdir -p "$LOC_DIR"
    # shellcheck disable=SC2034  # GEO_NAME is an output global, read by callers (weather set-city)
    GEO_NAME=$name
    printf '{"lat": %s, "lon": %s, "city": "%s", "source": "%s"}\n' "$LAT" "$LON" "$name" "$query" > "$LOC_FILE"
}

# Resolve the user's location into LAT/LON. Priority: direct LAT+LON in
# config.env (zero 3P calls) → LOCATION geocoded-once-and-cached → existing
# location.json → NYC fallback (with a warning).
read_location() {
    local env_lat env_lon env_loc
    env_lat=$(read_env_var LAT      "$ENV_FILE" || true)
    env_lon=$(read_env_var LON      "$ENV_FILE" || true)
    env_loc=$(read_env_var LOCATION "$ENV_FILE" || true)
    if [[ -n $env_lat && -n $env_lon ]]; then
        LAT=$env_lat; LON=$env_lon
        return 0
    fi

    if [[ -n $env_loc ]]; then
        local cached_source=""
        if [[ -f $LOC_FILE ]] && command -v jq >/dev/null 2>&1; then
            cached_source=$(jq -r '.source // empty' "$LOC_FILE")
        elif [[ -f $LOC_FILE ]]; then
            cached_source=$(grep -oE '"source"[[:space:]]*:[[:space:]]*"[^"]*"' "$LOC_FILE" | sed -E 's/.*"([^"]*)"$/\1/')
        fi
        if [[ $cached_source == "$env_loc" ]] && read_json_lat_lon "$LOC_FILE"; then
            return 0
        fi
        if geocode_to_cache "$env_loc" && read_json_lat_lon "$LOC_FILE"; then
            return 0
        fi
    fi

    if read_json_lat_lon "$LOC_FILE"; then
        return 0
    fi

    log "WARN: no location configured. Edit $ENV_FILE (LAT/LON or LOCATION) or run set-city. Using fallback ($FALLBACK_LAT, $FALLBACK_LON)."
    LAT=$FALLBACK_LAT; LON=$FALLBACK_LON
}

# True if the user has actually configured a location (direct LAT+LON, a
# LOCATION to geocode, or a cached location.json). Read-only: read_json_lat_lon
# runs in a subshell so it can't clobber the LAT/LON globals.
location_is_set() {
    local lat lon loc
    lat=$(read_env_var LAT      "$ENV_FILE" 2>/dev/null || true)
    lon=$(read_env_var LON      "$ENV_FILE" 2>/dev/null || true)
    loc=$(read_env_var LOCATION "$ENV_FILE" 2>/dev/null || true)
    [[ -n $lat && -n $lon ]] && return 0
    [[ -n $loc ]] && return 0
    ( read_json_lat_lon "$LOC_FILE" ) >/dev/null 2>&1
}
