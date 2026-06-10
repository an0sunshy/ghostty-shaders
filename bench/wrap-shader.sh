#!/usr/bin/env bash
# wrap-shader.sh — emit a complete, stand-alone GLSL fragment shader for a
# ghostty-weather scene, to stdout.
#
# Scenes are Shadertoy-style bodies (mainImage + helpers, no #version, no
# uniform declarations); each HOST supplies a small preamble/epilogue and
# compiles the result. This script reproduces that wrapping per host profile
# so a syntax checker such as glslangValidator (Linux CI) can validate the
# exact text each host compiles, without the host or a GPU:
#
#   bench/wrap-shader.sh shaders/scenes/cloudy.glsl                 > out.frag
#   bench/wrap-shader.sh --profile es300 shaders/scenes/cloudy.glsl > out.frag
#   glslangValidator out.frag
#
# Profiles:
#   gl410  (default)  The EXACT wrapping the headless bench harness uses.
#                     Preamble/epilogue are mirrored from glsl_bench.c
#                     PREAMBLE/EPILOGUE — keep them in sync if that wrapping
#                     ever changes.
#   es300             The EXACT wrapping the web gallery (web/) uses for
#                     WebGL2. Preamble/epilogue are read from
#                     web/glsl/{preamble,epilogue}.glsl — the same files the
#                     browser fetches — so there is one source of truth.
#
# Pure text; fully cross-platform (no macOS/GL dependency).

set -euo pipefail

usage() {
    echo "usage: $0 [--profile gl410|es300] <scene.glsl>" >&2
}

PROFILE="gl410"
SCENE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --profile)   PROFILE="${2:?--profile requires a value}"; shift 2 ;;
        --profile=*) PROFILE="${1#*=}"; shift ;;
        -h|--help)   usage; exit 0 ;;
        -*)          echo "wrap-shader.sh: unknown option: $1" >&2; usage; exit 2 ;;
        *)           SCENE="$1"; shift ;;
    esac
done

if [[ -z "$SCENE" ]]; then
    usage
    exit 2
fi
if [[ ! -f "$SCENE" ]]; then
    echo "wrap-shader.sh: no such file: $SCENE" >&2
    exit 1
fi

REPO_ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"

case "$PROFILE" in
gl410)
    # Preamble — identical to glsl_bench.c PREAMBLE. The "#line 1" makes any
    # compiler diagnostics report scene-relative line numbers.
    cat <<'PREAMBLE'
#version 410 core
uniform vec3  iResolution;
uniform float iTime;
uniform sampler2D iChannel0;
uniform vec3  iBackgroundColor;
out vec4 _ghostty_fragColor;
#line 1
PREAMBLE

    cat "$SCENE"

    # Epilogue — identical to glsl_bench.c EPILOGUE.
    cat <<'EPILOGUE'

void main() {
    vec4 c;
    mainImage(c, gl_FragCoord.xy);
    _ghostty_fragColor = c;
}
EPILOGUE
    ;;
es300)
    # The web gallery assembles preamble + baked #defines + "#line 1" + scene
    # + epilogue. Validation exercises the no-defines path (every scene must
    # compile on its #ifndef fallbacks alone).
    cat "$REPO_ROOT/web/glsl/preamble.glsl"
    printf '#line 1\n'
    cat "$SCENE"
    printf '\n'
    cat "$REPO_ROOT/web/glsl/epilogue.glsl"
    ;;
*)
    echo "wrap-shader.sh: unknown profile: $PROFILE (expected gl410 or es300)" >&2
    exit 2
    ;;
esac
