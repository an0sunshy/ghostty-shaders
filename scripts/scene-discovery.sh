#!/usr/bin/env bash
# scene-discovery.sh — the single source of truth for locating scene shaders.
#
# Scenes live under shaders/<category>/<name>.glsl (e.g. shaders/weather/rain.glsl,
# shaders/poems/jing-ye-si.glsl). Scene names are GLOBALLY UNIQUE across
# categories, so a bare name resolves to exactly one file regardless of which
# collection it belongs to. Every consumer (the dispatcher, build-site, the
# benchmarks, the gallery==scenes test) discovers scenes through these helpers
# so they can never drift apart.
#
# Usage: source this file, then call the helpers with the shaders ROOT dir:
#   source scripts/scene-discovery.sh
#   scene_names  "$REPO/shaders"          # one name per line, sorted
#   scene_files  "$REPO/shaders"          # one full path per line, sorted by name
#   scene_path   "$REPO/shaders" rain     # full path for a name, or empty + rc 1
#
# This file only defines functions (no side effects), so it is safe to source
# under `set -euo pipefail`.

# Full paths of every scene .glsl, recursively, in a deterministic order.
scene_files() {
    find "$1" -type f -name '*.glsl' | sort
}

# Scene names (basename without .glsl), one per line, sorted alphabetically.
scene_names() {
    find "$1" -type f -name '*.glsl' -exec basename {} .glsl \; | sort
}

# Resolve a scene NAME to its full path. Prints the path and returns 0 on a
# single match; prints nothing and returns 1 if the name does not exist.
# Names are unique by contract; if two ever collide, the first (sorted) wins.
scene_path() {
    local match
    match=$(find "$1" -type f -name "$2.glsl" | sort | head -1)
    [ -n "$match" ] || return 1
    printf '%s\n' "$match"
}
